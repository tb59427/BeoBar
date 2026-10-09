// BeoBar – Mac-Audio: Anruf-Erkennung (CoreAudio) und Medientasten

import Cocoa
import Combine
import CoreAudio

// ── CoreAudio: läuft gerade irgendein Programm auf einem Gerät? ──
enum AudioDevices {
    static func all() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func name(_ id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let n = name?.takeRetainedValue() else { return "" }
        return n as String
    }

    static func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func isRunning(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    // Namen aller Ausgabegeräte (für die Auswahl in den Einstellungen)
    static func outputNames() -> [String] {
        all().filter { hasStreams($0, kAudioObjectPropertyScopeOutput) }.map(name).filter { !$0.isEmpty }
    }

    // Anruf = irgendein Mikrofon nimmt auf UND der Ausgang zum PC2 spielt.
    // (Mit Headset läuft der PC2-Ausgang nicht → Musik bleibt an.)
    static func callActive(pc2Output: String) -> Bool {
        var micInUse = false, pc2OutInUse = false
        for d in all() where isRunning(d) {
            if hasStreams(d, kAudioObjectPropertyScopeInput) { micInUse = true }
            if hasStreams(d, kAudioObjectPropertyScopeOutput) && name(d).contains(pc2Output) { pc2OutInUse = true }
        }
        return micInUse && pc2OutInUse
    }
}

// ── Bei Anruf PC2 auf den lokalen Eingang (Mac) schalten, danach zurück ──
final class CallWatcher {
    var onChange: ((Bool) -> Void)?       // true = wir haben auf den Mac umgeschaltet
    private(set) var switched = false     // nur zurückschalten, was wir selbst umgeschaltet haben
    private var busy = false              // ein Befehl an den Server läuft gerade
    private var skipThisCall = false      // PC2 spielte kein Masterlink → diesen Anruf ignorieren
    private var activeSince: Date?
    private var quietSince: Date?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let now = Date()
        if AudioDevices.callActive(pc2Output: settings.pc2Output) {
            quietSince = nil
            if activeSince == nil { activeSince = now }
            if settings.callSwitch, !switched, !busy, !skipThisCall,
               now.timeIntervalSince(activeSince!) >= settings.callOnDelay { callStarted() }
        } else {
            activeSince = nil
            if quietSince == nil { quietSince = now }
            if now.timeIntervalSince(quietSince!) >= settings.callOffDelay {
                skipThisCall = false
                if switched, !busy { callEnded() }
            }
        }
    }

    // Nur umschalten, wenn der PC2 gerade Masterlink spielt
    private func callStarted() {
        guard beo.busPlayback else { skipThisCall = true; return }
        busy = true
        beo.send("pc") { ok in
            self.busy = false
            self.switched = ok
            if ok { self.onChange?(true) }
        }
    }

    // Zurück auf Masterlink – außer jemand hat inzwischen selbst etwas anderes gewählt
    private func callEnded() {
        switched = false
        onChange?(false)
        guard let p = beo.status?.pc2, p.speakersOn, p.local, !p.fromMasterlink else { return }
        busy = true
        beo.send("on") { _ in self.busy = false }
    }
}

// ── Medientasten der Tastatur (lauter/leiser/Mute/Play/Vor/Zurück) → BeoControl ──
// Fängt die Tasten systemweit ab (macOS sieht sie dann nicht mehr), solange BeoBar läuft:
// Lautstärke/Mute immer; Play/Vor/Zurück nur, wenn der PC2 Masterlink spielt – sonst
// gehen sie an das laufende Mac-Programm. Abschaltbar in den Einstellungen.
// Braucht die Freigabe unter Datenschutz & Sicherheit → Bedienungshilfen.
final class MediaKeys {
    // NX_KEYTYPE_* aus IOKit/hidsystem/ev_keymap.h
    private let volumeCommands: [Int: String] = [0: "vol+", 1: "vol-", 7: "mute"]
    private let transportCommands: [Int: String] = [17: "up", 18: "down", 19: "up", 20: "down"]
    private let keyPlay = 16
    private var playing = true          // Play/Pause schaltet abwechselnd stop / play
    private var tap: CFMachPort?
    private var watch: AnyCancellable?

    func start() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)   // fragt beim ersten Mal nach der Freigabe
        installTap()
        // Startet Bus-Musik, läuft sie → nächstes Play/Pause hält an
        var wasBus = false
        watch = beo.$status.sink { _ in
            DispatchQueue.main.async {
                let bus = beo.busPlayback
                if bus && !wasBus { self.playing = true }
                wasBus = bus
            }
        }
    }

    // Versucht den Event-Tap einzurichten, bis die Freigabe erteilt ist
    private func installTap() {
        let mask = CGEventMask(1 << 14)   // NSEvent.EventType.systemDefined
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask,
                                callback: { _, type, event, info in
                                    let me = Unmanaged<MediaKeys>.fromOpaque(info!).takeUnretainedValue()
                                    return me.handle(type, event)
                                },
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            NSLog("BeoBar: Medientasten noch nicht freigegeben (Bedienungshilfen) – neuer Versuch in 5 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.installTap() }
            return
        }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("BeoBar: Medientasten aktiv")
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS schaltet einen zu langsamen Tap ab → wieder einschalten
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard settings.mediaKeys, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {   // 8 = Medientasten
            return Unmanaged.passUnretained(event)
        }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let down = ((ns.data1 & 0xFF00) >> 8) == 0x0A
        let isRepeat = (ns.data1 & 0x1) != 0

        if let cmd = volumeCommands[key] {
            if down && (!isRepeat || cmd != "mute") { beo.send(cmd) }   // Lautstärke auch beim Gedrückthalten
            return nil   // Taste verschlucken (gedrückt und losgelassen)
        }
        guard key == keyPlay || transportCommands[key] != nil else { return Unmanaged.passUnretained(event) }
        guard beo.busPlayback else { return Unmanaged.passUnretained(event) }   // lokale Wiedergabe → Mac-Programm

        if down && !isRepeat {
            if key == keyPlay {
                playing.toggle()
                beo.send(playing ? "play" : "stop")
            } else if let cmd = transportCommands[key] {
                beo.send(cmd)
            }
        }
        return nil
    }
}

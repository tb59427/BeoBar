// BeoBar – Menüleisten-App für BeoControl (Beolink PC2)
// Startet den BeoControl-Blazor-Server im Hintergrund und zeigt
// die Fernbedienung als Popover in der Menüleiste.

import Cocoa
import CoreAudio
import WebKit

// ── Konfiguration ────────────────────────────────────────────────
let serverDir    = NSString(string: "~/BeoControlServer").expandingTildeInPath
let serverBinary = serverDir + "/BeoControlBlazor"
let port         = 5239
// 0.0.0.0 = auch vom Handy erreichbar; 127.0.0.1 = nur dieser Mac
let listenURL    = "http://0.0.0.0:\(port)"
let uiURL        = URL(string: "http://127.0.0.1:\(port)/")!
// Breite = --body-width der BeoControl-Oberfläche; wird nach dem Laden aus der Seite übernommen
let popoverSize  = NSSize(width: 210, height: 640)
let apiURL       = "http://127.0.0.1:\(port)/api"
// Anruf-Erkennung: Ausgabegerät, das in den PC2-Eingang speist (Teil des Namens)
let pc2OutputName  = "Cambridge Audio"
let callOnDelay    = 1.0   // s: so lange müssen Mikro + Ausgang laufen, bevor umgeschaltet wird
let callOffDelay   = 4.0   // s: so lange muss es ruhig sein, bevor zurückgeschaltet wird
// ─────────────────────────────────────────────────────────────────

// ── Menüleisten-Symbol: B&O-Logo ─────────────────────────────────
// Nach "bang-and-olufsen" aus Arcticons (CC BY-SA 4.0, https://github.com/Arcticons-Team/Arcticons),
// Strich für die Menüleiste verstärkt (1 → 2.6). Als Vorlage: macOS färbt es hell/dunkel passend.
let boLogoSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 48 48">
<g fill="none" stroke="black" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">
<circle cx="28.884" cy="29.69" r="6.262"/>
<path d="M12.854 26.813c4.904 0 7.93-3.316 7.93-7.407S17.758 12 12.854 12v23.95c4.127.379 6.075-1.486 6.075-4.569s-1.948-4.948-6.075-4.57m17.313-14.233a1.743 1.743 0 1 0-2.465 2.465l5.34 5.34"/>
<path d="m33.041 16.673l-3.198 3.199a1.743 1.743 0 1 1-2.465-2.465l1.344-1.344"/>
<circle cx="24" cy="24" r="20.7"/>
</g></svg>
"""

func boLogo() -> NSImage? {
    guard let img = NSImage(data: Data(boLogoSVG.utf8)) else { return nil }
    img.size = NSSize(width: 18, height: 18)
    img.isTemplate = true
    img.accessibilityDescription = "BeoControl"
    return img
}

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

    // Anruf = irgendein Mikrofon nimmt auf UND der Ausgang zum PC2 spielt.
    // (Mit Headset läuft der PC2-Ausgang nicht → Musik bleibt an.)
    static func callActive() -> Bool {
        var micInUse = false, pc2OutInUse = false
        for d in all() where isRunning(d) {
            if hasStreams(d, kAudioObjectPropertyScopeInput) { micInUse = true }
            if hasStreams(d, kAudioObjectPropertyScopeOutput) && name(d).contains(pc2OutputName) { pc2OutInUse = true }
        }
        return micInUse && pc2OutInUse
    }
}

// ── Befehl an BeoControl schicken (HTTP-API) ─────────────────────
func sendCommand(_ cmd: String, _ done: ((Bool) -> Void)? = nil) {
    var req = URLRequest(url: URL(string: "\(apiURL)/command/\(cmd)")!)
    req.httpMethod = "POST"
    req.timeoutInterval = 2
    URLSession.shared.dataTask(with: req) { _, response, _ in
        let ok = (response as? HTTPURLResponse)?.statusCode == 200
        if !ok { NSLog("BeoBar: Befehl '\(cmd)' fehlgeschlagen") }
        DispatchQueue.main.async { done?(ok) }
    }.resume()
}

// ── Medientasten der Tastatur (lauter/leiser/Mute/Play/Vor/Zurück) → BeoControl ──
// Fängt die Tasten systemweit ab (macOS sieht sie dann nicht mehr), solange BeoBar läuft:
// Lautstärke/Mute immer; Play/Vor/Zurück nur, wenn der PC2 Masterlink spielt – sonst
// gehen sie an das laufende Mac-Programm.
// Braucht die Freigabe unter Datenschutz & Sicherheit → Bedienungshilfen.
final class MediaKeys {
    // NX_KEYTYPE_* aus IOKit/hidsystem/ev_keymap.h
    private let volumeCommands: [Int: String] = [0: "vol+", 1: "vol-", 7: "mute"]
    private let transportCommands: [Int: String] = [17: "up", 18: "down", 19: "up", 20: "down"]
    private let keyPlay = 16
    private var playing = true          // Play/Pause schaltet abwechselnd stop / play
    private var busPlayback = false     // PC2 spielt gerade Masterlink (aus /api/status)
    private var tap: CFMachPort?
    private var poll: Timer?

    // Versucht den Event-Tap einzurichten, bis die Freigabe erteilt ist
    func start() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)   // fragt beim ersten Mal nach der Freigabe
        installTap()
        // Der Tap muss sofort entscheiden → PC2-Zustand regelmäßig vorab holen
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshState() }
        refreshState()
    }

    private func refreshState() {
        var req = URLRequest(url: URL(string: "\(apiURL)/status")!)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let pc2 = json?["pc2"] as? [String: Any]
            let bus = pc2?["speakersOn"] as? Bool == true && pc2?["fromMasterlink"] as? Bool == true
                && pc2?["local"] as? Bool != true
            DispatchQueue.main.async {
                if bus && !self.busPlayback { self.playing = true }   // Bus-Musik startet → läuft
                self.busPlayback = bus
            }
        }.resume()
    }

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
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {   // 8 = Medientasten
            return Unmanaged.passUnretained(event)
        }
        let key = (ns.data1 & 0xFFFF0000) >> 16
        let down = ((ns.data1 & 0xFF00) >> 8) == 0x0A
        let isRepeat = (ns.data1 & 0x1) != 0

        if let cmd = volumeCommands[key] {
            if down && (!isRepeat || cmd != "mute") { sendCommand(cmd) }   // Lautstärke auch beim Gedrückthalten
            return nil   // Taste verschlucken (gedrückt und losgelassen)
        }
        guard key == keyPlay || transportCommands[key] != nil else { return Unmanaged.passUnretained(event) }
        guard busPlayback else { return Unmanaged.passUnretained(event) }   // lokale Wiedergabe → Mac-Programm

        if down && !isRepeat {
            if key == keyPlay {
                playing.toggle()
                sendCommand(playing ? "play" : "stop")
            } else if let cmd = transportCommands[key] {
                sendCommand(cmd)
            }
        }
        return nil
    }
}

// ── Bei Anruf PC2 auf den lokalen Eingang (Mac) schalten, danach zurück ──
final class CallWatcher {
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "callSwitch") }
    }
    var onChange: ((Bool) -> Void)?       // true = wir haben auf PC umgeschaltet
    private(set) var switched = false     // nur zurückschalten, was wir selbst umgeschaltet haben
    private var busy = false              // eine Anfrage an den Server läuft gerade
    private var skipThisCall = false      // PC2 spielte kein Masterlink → diesen Anruf ignorieren
    private var activeSince: Date?
    private var quietSince: Date?
    private var timer: Timer?

    init() {
        enabled = UserDefaults.standard.object(forKey: "callSwitch") as? Bool ?? true
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let now = Date()
        if AudioDevices.callActive() {
            quietSince = nil
            if activeSince == nil { activeSince = now }
            if enabled, !switched, !busy, !skipThisCall,
               now.timeIntervalSince(activeSince!) >= callOnDelay { callStarted() }
        } else {
            activeSince = nil
            if quietSince == nil { quietSince = now }
            if now.timeIntervalSince(quietSince!) >= callOffDelay {
                skipThisCall = false
                if switched, !busy { callEnded() }
            }
        }
    }

    // Nur umschalten, wenn der PC2 gerade Masterlink spielt
    private func callStarted() {
        busy = true
        status { pc2 in
            guard let pc2, pc2["speakersOn"] as? Bool == true, pc2["fromMasterlink"] as? Bool == true,
                  pc2["local"] as? Bool != true else {
                self.skipThisCall = true
                self.busy = false
                return
            }
            sendCommand("pc") { ok in
                self.busy = false
                self.switched = ok
                if ok { self.onChange?(true) }
            }
        }
    }

    // Zurück auf Masterlink – außer jemand hat inzwischen selbst etwas anderes gewählt
    private func callEnded() {
        busy = true
        switched = false
        onChange?(false)
        status { pc2 in
            guard let pc2, pc2["speakersOn"] as? Bool == true, pc2["local"] as? Bool == true,
                  pc2["fromMasterlink"] as? Bool != true else { self.busy = false; return }
            sendCommand("on") { _ in self.busy = false }
        }
    }

    private func status(_ done: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: URL(string: "\(apiURL)/status")!)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(json?["pc2"] as? [String: Any]) }
        }.resume()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var webView: WKWebView!
    var server: Process?
    let callWatcher = CallWatcher()
    let mediaKeys = MediaKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServer()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            setIcon(call: false)
            button.action = #selector(clicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        webView = WKWebView(frame: NSRect(origin: .zero, size: popoverSize),
                            configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        let vc = NSViewController()
        vc.view = webView
        popover.contentViewController = vc
        popover.contentSize = popoverSize
        popover.behavior = .transient

        loadWhenReady(attempt: 0)

        callWatcher.onChange = { [weak self] call in self?.setIcon(call: call) }
        callWatcher.start()
        mediaKeys.start()
    }

    // B&O-Logo; während eines Anrufs (PC2 auf Mac umgeschaltet) Telefon-Symbol
    func setIcon(call: Bool) {
        statusItem.button?.image = call
            ? NSImage(systemSymbolName: "phone.fill", accessibilityDescription: "BeoControl")
            : boLogo() ?? NSImage(systemSymbolName: "hifispeaker.2", accessibilityDescription: "BeoControl")
    }

    // Server als Kindprozess starten (Ausgabe nach server.log)
    func startServer() {
        guard FileManager.default.isExecutableFile(atPath: serverBinary) else {
            NSLog("BeoBar: Server nicht gefunden unter \(serverBinary)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverBinary)
        p.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        var env = ProcessInfo.processInfo.environment
        env["ASPNETCORE_URLS"] = listenURL
        env["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib:/usr/local/lib"
        p.environment = env

        let logPath = serverDir + "/server.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let log = FileHandle(forWritingAtPath: logPath) {
            p.standardOutput = log
            p.standardError = log
        }
        do {
            try p.run()
            server = p
        } catch {
            NSLog("BeoBar: Server-Start fehlgeschlagen: \(error)")
        }
    }

    // Warten, bis der Server antwortet, dann Oberfläche laden
    func loadWhenReady(attempt: Int) {
        var request = URLRequest(url: uiURL)
        request.timeoutInterval = 1
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if response != nil {
                    self.webView.load(URLRequest(url: uiURL))
                } else if attempt < 60 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.loadWhenReady(attempt: attempt + 1)
                    }
                } else {
                    self.webView.loadHTMLString(
                        "<p style='font-family:-apple-system;padding:20px'>" +
                        "BeoControl-Server antwortet nicht.<br>Log: \(serverDir)/server.log</p>",
                        baseURL: nil)
                }
            }
        }.resume()
    }

    // Popover so breit wie die Seite selbst (body hat eine feste Breite) → keine Ränder
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == uiURL.host else { return }   // nicht für die Fehlerseite
        webView.evaluateJavaScript("document.body.getBoundingClientRect().width") { width, _ in
            guard let w = (width as? NSNumber)?.doubleValue, w >= 120, w <= 600 else { return }
            self.popover.contentSize = NSSize(width: ceil(w), height: popoverSize.height)
        }
    }

    // Linksklick: Popover; Rechtsklick: Menü
    @objc func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Neu laden", action: #selector(reload), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "Im Browser öffnen", action: #selector(openInBrowser), keyEquivalent: "b").target = self
            menu.addItem(.separator())
            let call = menu.addItem(withTitle: "Bei Anruf auf Mac umschalten", action: #selector(toggleCallSwitch), keyEquivalent: "")
            call.target = self
            call.state = callWatcher.enabled ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "BeoBar beenden", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func reload()        { webView.reload() }
    @objc func openInBrowser() { NSWorkspace.shared.open(uiURL) }
    @objc func quit()          { NSApp.terminate(nil) }
    @objc func toggleCallSwitch() { callWatcher.enabled.toggle() }

    func applicationWillTerminate(_ notification: Notification) {
        server?.terminate()   // gibt den PC2 wieder frei
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // kein Dock-Symbol
app.run()

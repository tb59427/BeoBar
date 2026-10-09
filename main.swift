// BeoBar – Menüleisten-App für BeoControl (Beolink PC2)
// Startet den BeoControl-Server im Hintergrund und zeigt eine eigene
// Fernbedienung als Popover in der Menüleiste; spricht BeoControl über dessen HTTP-API.

import Cocoa
import SwiftUI

// ── Konfiguration ────────────────────────────────────────────────
let serverDir    = NSString(string: "~/BeoControlServer").expandingTildeInPath
let serverBinary = serverDir + "/BeoControlBlazor"
let port         = 5239
// 0.0.0.0 = auch vom Handy erreichbar; 127.0.0.1 = nur dieser Mac
let listenURL    = "http://0.0.0.0:\(port)"
let uiURL        = URL(string: "http://127.0.0.1:\(port)/")!
let setupURL     = URL(string: "http://127.0.0.1:\(port)/setup")!
let apiURL       = "http://127.0.0.1:\(port)/api"
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var server: Process?
    let callWatcher = CallWatcher()
    let mediaKeys = MediaKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServer()
        beo.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            setIcon(call: false)
            button.action = #selector(clicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let remote = NSHostingController(rootView: RemoteView(openSettings: { [weak self] in self?.showSettings() }))
        remote.sizingOptions = .preferredContentSize   // Popover passt sich der Fernbedienung an
        popover.contentViewController = remote
        popover.behavior = .transient

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

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "BeoBar – Einstellungen"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Linksklick: Fernbedienung; Rechtsklick: Menü
    @objc func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Einstellungen …", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            let call = menu.addItem(withTitle: "Bei Anruf auf Mac umschalten", action: #selector(toggleCallSwitch), keyEquivalent: "")
            call.target = self
            call.state = settings.callSwitch ? .on : .off
            menu.addItem(withTitle: "Web-Oberfläche im Browser", action: #selector(openInBrowser), keyEquivalent: "b").target = self
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

    @objc func openInBrowser()    { NSWorkspace.shared.open(uiURL) }
    @objc func quit()             { NSApp.terminate(nil) }
    @objc func toggleCallSwitch() { settings.callSwitch.toggle() }

    func applicationWillTerminate(_ notification: Notification) {
        server?.terminate()   // gibt den PC2 wieder frei
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // kein Dock-Symbol
app.run()

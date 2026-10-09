// BeoBar – Menüleisten-App für BeoControl (Beolink PC2)
// Startet den BeoControl-Blazor-Server im Hintergrund und zeigt
// die Fernbedienung als Popover in der Menüleiste.

import Cocoa
import WebKit

// ── Konfiguration ────────────────────────────────────────────────
let serverDir    = NSString(string: "~/BeoControlServer").expandingTildeInPath
let serverBinary = serverDir + "/BeoControlBlazor"
let port         = 5239
// 0.0.0.0 = auch vom Handy erreichbar; 127.0.0.1 = nur dieser Mac
let listenURL    = "http://0.0.0.0:\(port)"
let uiURL        = URL(string: "http://127.0.0.1:\(port)/")!
let popoverSize  = NSSize(width: 360, height: 640)
// ─────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var webView: WKWebView!
    var server: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServer()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.2",
                                   accessibilityDescription: "BeoControl")
            button.action = #selector(clicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        webView = WKWebView(frame: NSRect(origin: .zero, size: popoverSize),
                            configuration: WKWebViewConfiguration())
        let vc = NSViewController()
        vc.view = webView
        popover.contentViewController = vc
        popover.contentSize = popoverSize
        popover.behavior = .transient

        loadWhenReady(attempt: 0)
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

    // Linksklick: Popover; Rechtsklick: Menü
    @objc func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Neu laden", action: #selector(reload), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "Im Browser öffnen", action: #selector(openInBrowser), keyEquivalent: "b").target = self
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

    func applicationWillTerminate(_ notification: Notification) {
        server?.terminate()   // gibt den PC2 wieder frei
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // kein Dock-Symbol
app.run()

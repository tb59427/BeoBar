// BeoBar – Fernbedienung (Popover), angelehnt an die Beo4

import SwiftUI

private let bodyColor = Color(red: 0.11, green: 0.11, blue: 0.12)
private let keyColor = Color(white: 0.24)
private let keyText = Color(white: 0.92)
private let displayColor = Color(red: 0.55, green: 0.85, blue: 0.95)

// Taste im Beo4-Stil
struct BeoKey: ButtonStyle {
    var fill: Color = keyColor
    var text: Color = keyText
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill.opacity(configuration.isPressed ? 0.6 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct RemoteView: View {
    @ObservedObject var client = beo
    @ObservedObject var config = settings
    var openSettings: () -> Void = {}

    private let grid = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(spacing: 10) {
            display
            sources
            digits
            colours
            navigation
            volume
            standby
        }
        .padding(12)
        .frame(width: 210)
        .background(bodyColor)
    }

    // ── Display: Quelle, Zustand, Lautstärke ──
    private var display: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(sourceText).font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(displayColor.opacity(0.7)).help("Einstellungen")
            }
            HStack {
                Text(stateText)
                Spacer()
                if let a = client.status?.audio { Text("VOL \(a.volume)") }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .opacity(0.8)
        }
        .foregroundStyle(displayColor)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
    }

    private var sourceText: String {
        guard client.reachable, let s = client.status, s.connected else { return "– – –" }
        if let p = s.pc2, !p.speakersOn { return "STANDBY" }
        if let p = s.pc2, p.local, !p.fromMasterlink { return config.displayName(forCommand: "pc") }
        guard let src = s.source else { return "–" }
        let name = config.displayName(forCommand: src.command)
        if let i = src.index, i > 0 { return "\(name) \(i)" }
        return name
    }

    private var stateText: String {
        guard client.reachable else { return "BeoControl startet …" }
        guard let s = client.status, s.connected else { return "PC2 nicht verbunden" }
        guard let p = s.pc2 else { return s.device ?? "" }
        if !p.speakersOn { return "AUS" }
        if p.muted { return "STUMM" }
        if p.local && !p.fromMasterlink { return "MAC" }
        return p.fromMasterlink ? "MASTERLINK" : "EIN"
    }

    // ── Quellen (konfigurierbar) ──
    private var sources: some View {
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach(config.sources) { b in
                Button(b.label.isEmpty ? " " : b.label) { if !b.command.isEmpty { client.send(b.command, arg: b.arg) } }
                    .buttonStyle(BeoKey(fill: Color(white: 0.32)))
                    .disabled(b.command.isEmpty)
            }
        }
    }

    // ── Ziffern ──
    private var digits: some View {
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach(1...9, id: \.self) { n in key("\(n)", "\(n)") }
            key("STOP", "stop")
            key("0", "0")
            key("PLAY", "play")
        }
    }

    // ── Farbtasten ──
    private var colours: some View {
        HStack(spacing: 6) {
            colourKey(.red, "red")
            colourKey(.green, "green")
            colourKey(.yellow, "yellow")
            colourKey(.blue, "blue")
        }
    }

    // ── Steuerkreuz mit GO ──
    private var navigation: some View {
        VStack(spacing: 6) {
            key("▲", "up").frame(width: 56)
            HStack(spacing: 6) {
                key("◀", "left")
                Button("GO") { client.send("go") }.buttonStyle(BeoKey(fill: Color(white: 0.45), height: 32))
                key("▶", "right")
            }
            key("▼", "down").frame(width: 56)
        }
    }

    // ── Lautstärke ──
    private var volume: some View {
        HStack(spacing: 6) {
            key("−", "vol-")
            key("MUTE", "mute")
            key("+", "vol+")
        }
    }

    private var standby: some View {
        Button { client.send("standby") } label: { Image(systemName: "power") }
            .buttonStyle(BeoKey(fill: Color(red: 0.62, green: 0.1, blue: 0.1), height: 28))
            .help("Standby")
    }

    private func key(_ title: String, _ cmd: String) -> some View {
        Button(title) { client.send(cmd) }.buttonStyle(BeoKey())
    }

    private func colourKey(_ c: Color, _ cmd: String) -> some View {
        Button("") { client.send(cmd) }.buttonStyle(BeoKey(fill: c.opacity(0.85), height: 14))
    }
}

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
            navigation
            volume
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

    // ── Ziffern, Anordnung wie auf der Beo4 ──
    private var digits: some View {
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach([9, 8, 7, 6, 5, 4, 1, 2, 3], id: \.self) { n in key("\(n)", "\(n)") }
            key("TEXT", "text")
            key("0", "0")
            key("MENU", "menu")
        }
    }

    // ── Navigation wie auf der Beo4: auf der Spitze stehendes Quadrat, die
    //    Ecken zeigen in die Richtungen, GO in der Mitte; die Farbtasten
    //    liegen diagonal außen an den Kanten ──
    private let navCell: CGFloat = 44
    private let navGap: CGFloat = 4

    private var navigation: some View {
        ZStack {
            // 2×2-Raster, um 45° gedreht: oben links → oben, oben rechts → rechts, …
            VStack(spacing: navGap) {
                HStack(spacing: navGap) { navKey("▲", "up", corner: .topLeading); navKey("▶", "right", corner: .topTrailing) }
                HStack(spacing: navGap) { navKey("◀", "left", corner: .bottomLeading); navKey("▼", "down", corner: .bottomTrailing) }
            }
            .rotationEffect(.degrees(45))

            Button("GO") { client.send("go") }
                .buttonStyle(RoundKey(fill: Color(white: 0.45), size: 40))

            colourKey(.green, "green").rotationEffect(.degrees(-45)).offset(x: -48, y: -48)
            colourKey(.yellow, "yellow").rotationEffect(.degrees(45)).offset(x: 48, y: -48)
            colourKey(.red, "red").rotationEffect(.degrees(45)).offset(x: -48, y: 48)
            colourKey(.blue, "blue").rotationEffect(.degrees(-45)).offset(x: 48, y: 48)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }

    // Richtungstaste: Pfeil zur äußeren Ecke versetzt und zurückgedreht
    private func navKey(_ arrow: String, _ cmd: String, corner: UnitPoint) -> some View {
        let shift = navCell * 0.14
        let dx: CGFloat = corner == .topLeading || corner == .bottomLeading ? -shift : shift
        let dy: CGFloat = corner == .topLeading || corner == .topTrailing ? -shift : shift
        return Button { client.send(cmd) } label: {
            Text(arrow).rotationEffect(.degrees(-45)).offset(x: dx, y: dy)
        }
        .buttonStyle(BeoKey(height: navCell))
        .frame(width: navCell)
    }

    // ── Lautstärke-Block wie auf der Beo4 ──
    //    (LIST)  +   (EXIT)     LIST/EXIT braucht's am Mac nicht
    //           MUTE
    //    STOP    −   Standby
    private var volume: some View {
        LazyVGrid(columns: grid, spacing: 6) {
            Color.clear.frame(height: 26)
            key("+", "vol+")
            Color.clear.frame(height: 26)
            Color.clear.frame(height: 26)
            key("MUTE", "mute")
            Color.clear.frame(height: 26)
            key("STOP", "stop")
            key("−", "vol-")
            Button { client.send("standby") } label: { Image(systemName: "power") }
                .buttonStyle(BeoKey(fill: Color(red: 0.62, green: 0.1, blue: 0.1)))
                .help("Standby")
        }
    }

    private func key(_ title: String, _ cmd: String) -> some View {
        Button(title) { client.send(cmd) }.buttonStyle(BeoKey())
    }

    private func colourKey(_ c: Color, _ cmd: String) -> some View {
        Button("") { client.send(cmd) }
            .buttonStyle(BeoKey(fill: c.opacity(0.85), height: 14))
            .frame(width: 50)
    }
}

// Runde Taste (GO)
struct RoundKey: ButtonStyle {
    var fill: Color
    var size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(keyText)
            .frame(width: size, height: size)
            .background(Circle().fill(fill.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(Circle().stroke(bodyColor, lineWidth: 3))
            .contentShape(Circle())
    }
}

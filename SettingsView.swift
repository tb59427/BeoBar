// BeoBar – Einstellungsfenster

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SourcesTab().tabItem { Label("Quellentasten", systemImage: "square.grid.3x3") }
            SoundTab().tabItem { Label("PC2-Klang", systemImage: "slider.horizontal.3") }
            CallKeysTab().tabItem { Label("Anruf & Tasten", systemImage: "phone") }
            GeneralTab().tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(width: 480, height: 420)
    }
}

// ── Quellentasten: Beschriftung, Befehl, optionale Nummer ──
private struct SourcesTab: View {
    @ObservedObject var config = settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Die 9 Tasten oben auf der Fernbedienung (von links nach rechts, Zeile für Zeile).")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Beschriftung").font(.caption).foregroundStyle(.secondary)
                    Text("Befehl").font(.caption).foregroundStyle(.secondary)
                    Text("Nr.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(config.sources.indices, id: \.self) { i in
                    GridRow {
                        Text("\(i + 1)").foregroundStyle(.secondary)
                        TextField("", text: $config.sources[i].label).frame(width: 110)
                        HStack(spacing: 4) {
                            TextField("", text: $config.sources[i].command).frame(width: 90)
                            Menu {
                                ForEach(knownCommands, id: \.command) { k in
                                    Button("\(k.label) (\(k.command))") {
                                        config.sources[i].command = k.command
                                        config.sources[i].label = k.label
                                    }
                                }
                                Divider()
                                Button("Leer") { config.sources[i].command = ""; config.sources[i].label = "" }
                            } label: { Image(systemName: "list.bullet") }
                                .menuStyle(.borderlessButton).frame(width: 28)
                        }
                        TextField("", value: $config.sources[i].arg, format: .number).frame(width: 40)
                    }
                }
            }
            Spacer()
            HStack {
                Text("Nr. z. B. für RADIO 3; leer = keine.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Standard wiederherstellen") { config.sources = defaultSources }
            }
        }
    }
}

// ── PC2-Klang: über BeoControl-Befehle, Werte live aus dem Status ──
private struct SoundTab: View {
    @ObservedObject var client = beo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = client.status?.audio {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    row("Lautstärke", "\(a.volume)", "vol-", "vol+")
                    row("Bass", signed(a.bass), "bas-", "bas+")
                    row("Höhen", signed(a.treble), "tre-", "tre+")
                    row("Balance", signed(a.balance), "bal-", "bal+")
                    GridRow {
                        Text("Loudness")
                        Text(a.loudness ? "an" : "aus").monospacedDigit()
                        Button(a.loudness ? "Ausschalten" : "Einschalten") { client.send(a.loudness ? "lou-" : "lou+") }
                    }
                }
                Text("Speichert BeoControl automatisch.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Kein PC2 verbunden.").foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Text("Standardquelle und Geräteverbindung:").foregroundStyle(.secondary)
                Button("BeoControl-Einstellungen …") { NSWorkspace.shared.open(setupURL) }
            }
        }
    }

    private func row(_ title: String, _ value: String, _ minus: String, _ plus: String) -> some View {
        GridRow {
            Text(title)
            Text(value).monospacedDigit().frame(width: 30, alignment: .trailing)
            HStack {
                Button("−") { client.send(minus) }
                Button("+") { client.send(plus) }
            }
        }
    }

    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
}

// ── Anruf-Umschaltung und Medientasten ──
private struct CallKeysTab: View {
    @ObservedObject var config = settings
    @State private var outputs = AudioDevices.outputNames()

    var body: some View {
        Form {
            Section("Bei Anruf") {
                Toggle("PC2 während eines Anrufs auf den Mac umschalten", isOn: $config.callSwitch)
                Picker("Ausgang zum PC2", selection: $config.pc2Output) {
                    ForEach(outputChoices, id: \.tag) { Text($0.label).tag($0.tag) }
                }
                Stepper("Umschalten nach \(config.callOnDelay, specifier: "%.1f") s", value: $config.callOnDelay, in: 0.5...10, step: 0.5)
                Stepper("Zurück nach \(config.callOffDelay, specifier: "%.0f") s Ruhe", value: $config.callOffDelay, in: 1...30, step: 1)
                Text("Anruf = ein Mikrofon nimmt auf und der Ausgang zum PC2 spielt. Nur wenn der PC2 Masterlink spielt; danach geht die Musik weiter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Medientasten") {
                Toggle("Tastatur-Medientasten an BeoControl", isOn: $config.mediaKeys)
                Text("Lautstärke und Mute immer, Play/Vor/Zurück nur bei Masterlink-Wiedergabe. Braucht Datenschutz & Sicherheit → Bedienungshilfen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { outputs = AudioDevices.outputNames() }
    }

    // Gespeichert ist ein Teil des Gerätenamens; das passende Gerät zeigt seinen vollen Namen.
    // Fehlt es gerade, bleibt der gespeicherte Wert trotzdem wählbar.
    private var outputChoices: [(label: String, tag: String)] {
        var choices = outputs.map { name in (label: name, tag: name.contains(config.pc2Output) ? config.pc2Output : name) }
        if !choices.contains(where: { $0.tag == config.pc2Output }) {
            choices.insert((label: "\(config.pc2Output) (nicht angeschlossen)", tag: config.pc2Output), at: 0)
        }
        return choices
    }
}

// ── Allgemein ──
private struct GeneralTab: View {
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Beim Anmelden starten", isOn: $loginItem)
                    .onChange(of: loginItem) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            loginItem = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("BeoControl") {
                Button("Web-Oberfläche im Browser öffnen") { NSWorkspace.shared.open(uiURL) }
                Button("BeoControl-Einstellungen öffnen") { NSWorkspace.shared.open(setupURL) }
            }
        }
        .formStyle(.grouped)
    }
}

// BeoBar – Einstellungen (in UserDefaults gespeichert)

import Foundation

// Eine Quellentaste der Fernbedienung: Beschriftung + BeoControl-Befehl (+ optionale Nummer)
struct SourceButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var command: String
    var arg: Int?
}

// Bekannte BeoControl-Befehle für die Auswahl (Beschriftung, Befehl)
let knownCommands: [(label: String, command: String)] = [
    ("N.MUSIC", "atape2"), ("N.RADIO", "phono"), ("RADIO", "radio"), ("CD", "cd"),
    ("A.MEM", "atape"), ("A.AUX", "a.aux"), ("PC (Mac)", "pc"), ("TV", "tv"),
    ("SAT", "sat"), ("DVD", "dvd"), ("V.MEM", "vtape"), ("V.AUX", "v.aux"),
    ("DOORCAM", "doorcam"), ("BUS AN", "on"),
]

let defaultSources: [SourceButton] = [
    SourceButton(label: "N.MUSIC", command: "atape2"),
    SourceButton(label: "N.RADIO", command: "phono"),
    SourceButton(label: "RADIO", command: "radio"),
    SourceButton(label: "CD", command: "cd"),
    SourceButton(label: "A.MEM", command: "atape"),
    SourceButton(label: "A.AUX", command: "a.aux"),
    SourceButton(label: "MAC", command: "pc"),
    SourceButton(label: "TV", command: "tv"),
    SourceButton(label: "DVD", command: "dvd"),
]

final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var sources: [SourceButton] {
        didSet { d.set(try? JSONEncoder().encode(sources), forKey: "sources") }
    }
    // Anruf-Umschaltung
    @Published var callSwitch: Bool { didSet { d.set(callSwitch, forKey: "callSwitch") } }
    @Published var pc2Output: String { didSet { d.set(pc2Output, forKey: "pc2Output") } }   // Teil des Gerätenamens
    @Published var callOnDelay: Double { didSet { d.set(callOnDelay, forKey: "callOnDelay") } }
    @Published var callOffDelay: Double { didSet { d.set(callOffDelay, forKey: "callOffDelay") } }
    // Medientasten der Tastatur
    @Published var mediaKeys: Bool { didSet { d.set(mediaKeys, forKey: "mediaKeys") } }

    init() {
        sources = (d.data(forKey: "sources")).flatMap { try? JSONDecoder().decode([SourceButton].self, from: $0) }
            ?? defaultSources
        callSwitch = d.object(forKey: "callSwitch") as? Bool ?? true
        pc2Output = d.string(forKey: "pc2Output") ?? "Cambridge Audio"
        callOnDelay = d.object(forKey: "callOnDelay") as? Double ?? 1.0
        callOffDelay = d.object(forKey: "callOffDelay") as? Double ?? 4.0
        mediaKeys = d.object(forKey: "mediaKeys") as? Bool ?? true
    }

    // Anzeigename für eine Quelle: eigene Tastenbeschriftung, sonst bekannter Name
    func displayName(forCommand cmd: String) -> String {
        if let b = sources.first(where: { $0.command == cmd && !$0.label.isEmpty }) { return b.label }
        if let k = knownCommands.first(where: { $0.command == cmd }) { return k.label }
        return cmd.uppercased()
    }
}

let settings = AppSettings()

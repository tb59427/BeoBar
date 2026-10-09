// BeoBar – Verbindung zu BeoControl über dessen HTTP-API
//   POST /api/command/{cmd}?arg=N   Befehl ausführen
//   GET  /api/events                Status live (server-sent events, wie /api/status)

import Foundation

struct BeoStatus: Decodable, Equatable {
    struct Pc2: Decodable, Equatable {
        var speakersOn: Bool
        var muted: Bool
        var fromMasterlink: Bool
        var local: Bool
    }
    struct Source: Decodable, Equatable {
        var command: String
        var index: Int?
    }
    struct Audio: Decodable, Equatable {
        var volume: Int
        var bass: Int
        var treble: Int
        var balance: Int
        var loudness: Bool
    }
    var connected: Bool
    var device: String?
    var pc2: Pc2?
    var source: Source?
    var audio: Audio?
}

final class BeoClient: ObservableObject {
    @Published private(set) var status: BeoStatus?
    @Published private(set) var reachable = false

    // PC2 spielt gerade Masterlink (nicht den Mac-Eingang, nicht aus)
    var busPlayback: Bool {
        guard let p = status?.pc2 else { return false }
        return p.speakersOn && p.fromMasterlink && !p.local
    }

    func start() {
        Task.detached { [weak self] in await self?.eventLoop() }
    }

    func send(_ cmd: String, arg: Int? = nil, _ done: ((Bool) -> Void)? = nil) {
        var comps = URLComponents(string: "\(apiURL)/command/")!
        comps.path += cmd.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cmd
        if let arg { comps.queryItems = [URLQueryItem(name: "arg", value: String(arg))] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if !ok { NSLog("BeoBar: Befehl '\(cmd)' fehlgeschlagen") }
            DispatchQueue.main.async { done?(ok) }
        }.resume()
    }

    // Status-Ereignisse lesen; bei Abbruch (Server startet noch, Neustart) alle 2 s neu verbinden
    private func eventLoop() async {
        while true {
            do {
                var req = URLRequest(url: URL(string: "\(apiURL)/events")!)
                req.timeoutInterval = 30   // Server schickt spätestens alle 15 s etwas
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                for try await line in bytes.lines where line.hasPrefix("data: ") {
                    guard let s = try? JSONDecoder().decode(BeoStatus.self, from: Data(line.dropFirst(6).utf8)) else { continue }
                    await MainActor.run {
                        self.reachable = true
                        if self.status != s { self.status = s }
                    }
                }
            } catch {}
            await MainActor.run { self.reachable = false }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

let beo = BeoClient()

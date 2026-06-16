import Foundation

class P25Client {
    static let shared = P25Client()
    private init() {}

    // MARK: - Config (persisted in UserDefaults)

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? Secrets.serverURL }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }
    var username: String {
        get { UserDefaults.standard.string(forKey: "username") ?? Secrets.username }
        set { UserDefaults.standard.set(newValue, forKey: "username") }
    }
    var password: String {
        get { UserDefaults.standard.string(forKey: "password") ?? Secrets.password }
        set { UserDefaults.standard.set(newValue, forKey: "password") }
    }

    var isConfigured: Bool { true }

    var authHeader: String {
        let creds = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(creds)"
    }

    // MARK: - Request building

    private func req(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: "\(baseURL)\(path)")!, timeoutInterval: 15)
        r.httpMethod = method
        r.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    // MARK: - API calls

    func fetchState() async throws -> StateResponse {
        // scope=all: the app shows full history (All filter) + feeds the map heatmap.
        // The server defaults to a light 24h window; we explicitly opt into everything.
        let (data, _) = try await URLSession.shared.data(for: req("/api/state?scope=all"))
        return try JSONDecoder().decode(StateResponse.self, from: data)
    }

    func fetchALPR() async throws -> [ALPRCamera] {
        let (data, _) = try await URLSession.shared.data(for: req("/api/alpr"))
        return try JSONDecoder().decode(ALPRResponse.self, from: data).cameras
    }

    func setAudioFilter(_ filter: String) async throws {
        let body = try JSONEncoder().encode(["filter": filter])
        _ = try await URLSession.shared.data(for: req("/api/audio-filter", method: "POST", body: body))
    }

    func audioURL() -> URL { URL(string: "\(baseURL)/api/audio")! }

    func fetchAudioToken() async throws -> String {
        let (data, _) = try await URLSession.shared.data(for: req("/api/audio/token"))
        struct TokenResp: Decodable { let token: String }
        return try JSONDecoder().decode(TokenResp.self, from: data).token
    }

    func fetchTransmissions(limit: Int = 50, beforeId: Int = 0, afterId: Int = 0, fromId: Int = 0, toId: Int = 0) async throws -> [TXEvent] {
        var path = "/api/transmissions?limit=\(limit)"
        if fromId > 0 && toId > 0 { path += "&from_id=\(fromId)&to_id=\(toId)" }
        else if beforeId > 0      { path += "&before_id=\(beforeId)" }
        else if afterId  > 0      { path += "&after_id=\(afterId)" }
        let (data, _) = try await URLSession.shared.data(for: req(path))
        let rows = try JSONDecoder().decode([TXRow].self, from: data)
        return rows.map { $0.toTXEvent() }
    }

    func clipURL(filename: String, token: String) -> URL {
        let enc = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        let tok = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        return URL(string: "\(baseURL)/api/audio/clip/\(enc)?t=\(tok)")!
    }

    // MARK: - SSE stream

    func streamEvents() -> AsyncThrowingStream<TXEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var r = self.req("/api/stream")
                    r.timeoutInterval = .infinity
                    let (bytes, _) = try await URLSession.shared.bytes(for: r)
                    var buffer = ""
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if buffer.hasPrefix("data: "),
                               let data = String(buffer.dropFirst(6)).data(using: .utf8),
                               let event = try? JSONDecoder().decode(TXEvent.self, from: data) {
                                continuation.yield(event)
                            }
                            buffer = ""
                        } else {
                            buffer = buffer.isEmpty ? line : "\(buffer)\n\(line)"
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

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

    // Default to the light 24h window for fast load/poll; pass scope="all" only
    // when something (the heatmap) genuinely needs full history.
    func fetchState(scope: String = "window") async throws -> StateResponse {
        let (data, _) = try await URLSession.shared.data(for: req("/api/state?scope=\(scope)"))
        return try JSONDecoder().decode(StateResponse.self, from: data)
    }

    func fetchALPR() async throws -> [ALPRCamera] {
        let (data, _) = try await URLSession.shared.data(for: req("/api/alpr"))
        return try JSONDecoder().decode(ALPRResponse.self, from: data).cameras
    }

    // MARK: - Push notifications (device registration + prefs)

    /// Whether the server has APNs credentials provisioned — readable without a
    /// device token, so the Notifications screen can show accurate status before
    /// the user has registered.
    func fetchPushConfigured() async -> Bool {
        struct Health: Decodable { let push_configured: Bool? }
        guard let (data, _) = try? await URLSession.shared.data(for: req("/api/health")),
              let h = try? JSONDecoder().decode(Health.self, from: data) else { return false }
        return h.push_configured ?? false
    }

    /// Register/refresh this device's APNs token with the server. Returns the
    /// prefs the server now has for it, plus whether APNs is configured server-side.
    @discardableResult
    func registerDevice(token: String, environment: String, prefs: NotifPrefs?) async throws -> DeviceRegisterResponse {
        struct Body: Encodable { let token: String; let platform: String; let environment: String; let prefs: NotifPrefs? }
        let body = try JSONEncoder().encode(Body(token: token, platform: "ios", environment: environment, prefs: prefs))
        let (data, _) = try await URLSession.shared.data(for: req("/api/devices/register", method: "POST", body: body))
        return try JSONDecoder().decode(DeviceRegisterResponse.self, from: data)
    }

    func fetchPrefs(token: String) async throws -> DeviceRegisterResponse {
        let enc = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let (data, _) = try await URLSession.shared.data(for: req("/api/devices/prefs?token=\(enc)"))
        return try JSONDecoder().decode(DeviceRegisterResponse.self, from: data)
    }

    @discardableResult
    func savePrefs(token: String, prefs: NotifPrefs) async throws -> NotifPrefs {
        struct Body: Encodable { let token: String; let prefs: NotifPrefs }
        let body = try JSONEncoder().encode(Body(token: token, prefs: prefs))
        let (data, _) = try await URLSession.shared.data(for: req("/api/devices/prefs", method: "POST", body: body))
        struct Resp: Decodable { let ok: Bool; let prefs: NotifPrefs }
        return try JSONDecoder().decode(Resp.self, from: data).prefs
    }

    /// Ask the server to fire a test push to this device. Throws on non-2xx.
    func sendTestPush(token: String) async throws {
        struct Body: Encodable { let token: String }
        let body = try JSONEncoder().encode(Body(token: token))
        let (_, resp) = try await URLSession.shared.data(for: req("/api/devices/test", method: "POST", body: body))
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw NSError(domain: "P25", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server returned \(http.statusCode)"])
        }
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

import Foundation

/// The Destin SDR station has one general-purpose radio that gets switched
/// between modes (ACARS, APRS, NOAA weather, marine...). Marine Ch16 audio only
/// exists while it's tuned to "marine", so this polls the current mode.
///
/// Served by the EC2 nginx at destin.sadbabyrabbit.com/app/ - a listen-only
/// path that takes the app's P25 login, not the site login.
@MainActor
final class DestinRadio: ObservableObject {
    static let shared = DestinRadio()
    static let base = "https://destin.sadbabyrabbit.com/app"
    static let marineStreamURL = URL(string: "\(base)/marine/voice.m3u8")!

    @Published private(set) var mode: String?
    @Published private(set) var modeLabel: String?
    @Published private(set) var reachable = false

    var isOnMarine: Bool { mode == "marine" }

    private var timer: Timer?
    private init() {}

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in await DestinRadio.shared.refresh() }
        }
    }

    func refresh() async {
        struct Resp: Decodable { let mode: String?; let label: String? }
        var r = URLRequest(url: URL(string: "\(Self.base)/mode")!, timeoutInterval: 10)
        r.setValue(P25Client.shared.authHeader, forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let m = try JSONDecoder().decode(Resp.self, from: data)
            if mode != m.mode { mode = m.mode }
            if modeLabel != m.label { modeLabel = m.label }
            if !reachable { reachable = true }
        } catch {
            // Keep the last known mode: one dropped poll shouldn't stop playback.
            if reachable { reachable = false }
        }
        P25AudioPlayer.shared.destinModeChanged()
    }
}

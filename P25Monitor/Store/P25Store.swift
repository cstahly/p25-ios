import Foundation
import Combine

extension Notification.Name {
    static let p25NewTX = Notification.Name("p25NewTX")
}

@MainActor
class P25Store: ObservableObject {
    static let shared = P25Store()

    @Published var incidents: [Incident] = []
    @Published var heatIncidents: [Incident] = []   // full history, loaded on demand for the heatmap
    @Published var alprCameras: [ALPRCamera] = []
    @Published var recentTX: [TXEvent] = []
    @Published var audioFilter: String = "all"
    @Published var selectedTab: Int = 0          // drives ContentView's TabView
    @Published var mapFocus: Incident?           // set to jump the Map tab to an incident
    @Published var isStreaming = false
    @Published var lastError: String?

    private var streamTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var txPollTimer: Timer?
    private var lastRefresh: Date = .distantPast

    private init() {}

    func start() {
        guard P25Client.shared.isConfigured else { return }
        guard streamTask == nil else { return }
        Task { await refresh() }
        Task { await backfillTX() }
        Task { await loadALPR() }
        startStreaming()
        // Poll recentTX so the radio log (esp. CarPlay, which reads recentTX) stays
        // fresh even if the SSE stream stalls.
        txPollTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { await self?.pollRecentTX() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Seed recentTX with history so consumers that only read the store
    /// (CarPlay log) aren't empty until new traffic streams in.
    func backfillTX() async {
        guard recentTX.isEmpty else { return }
        if let rows = try? await P25Client.shared.fetchTransmissions(limit: 50) {
            if recentTX.isEmpty { recentTX = rows }
        }
    }

    /// Full-history incidents for the heatmap (precise points), fetched on demand
    /// when the heatmap is toggled on — keeps the normal poll light/fast.
    func loadHeatData() async {
        if let r = try? await P25Client.shared.fetchState(scope: "all") {
            heatIncidents = r.incidents
        }
    }

    /// ALPR (Flock) camera locations from DeFlock/OSM — static, loaded once.
    func loadALPR() async {
        guard alprCameras.isEmpty else { return }
        if let cams = try? await P25Client.shared.fetchALPR() {
            alprCameras = cams
        }
    }

    func stop() {
        streamTask?.cancel()
        refreshTimer?.invalidate()
        txPollTimer?.invalidate()
        isStreaming = false
    }

    /// Poll for new transmissions so recentTX (the CarPlay log) updates reliably,
    /// independent of the SSE stream. Deduped by db id.
    func pollRecentTX() async {
        let maxId = recentTX.map(\.dbId).max() ?? 0
        let rows: [TXEvent]
        if maxId > 0 {
            guard let r = try? await P25Client.shared.fetchTransmissions(afterId: maxId) else { return }
            rows = r
        } else {
            guard let r = try? await P25Client.shared.fetchTransmissions() else { return }
            rows = r
        }
        let existing = Set(recentTX.map(\.dbId))
        let fresh = rows.filter { $0.dbId > 0 && !existing.contains($0.dbId) }
        guard !fresh.isEmpty else { return }
        recentTX.insert(contentsOf: fresh, at: 0)
        if recentTX.count > 100 { recentTX = Array(recentTX.prefix(100)) }
    }

    func refresh() async {
        guard P25Client.shared.isConfigured else { return }
        do {
            let state = try await P25Client.shared.fetchState()
            incidents = state.incidents
            lastError = nil
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startStreaming() {
        streamTask?.cancel()
        streamTask = Task {
            isStreaming = true
            defer { isStreaming = false }
            do {
                for try await event in P25Client.shared.streamEvents() {
                    guard !Task.isCancelled else { return }
                    if event.type == "tx" {
                        // recentTX is fed by pollRecentTX() (deduped by db id); the
                        // SSE event carries no id, so don't insert it here (avoids
                        // duplicates). Still use the stream to nudge incident refresh.
                        NotificationCenter.default.post(name: .p25NewTX, object: event)
                        if Date().timeIntervalSince(lastRefresh) > 5 {
                            await refresh()
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { startStreaming() }
            }
        }
    }

    func setAudioFilter(_ filter: String) {
        audioFilter = filter
        Task { try? await P25Client.shared.setAudioFilter(filter) }
    }

    /// Distinct agency names from currently-loaded incidents — feeds the
    /// notification agency allowlist picker.
    var availableAgencies: [String] {
        Array(Set(incidents.map(\.agency).filter { !$0.isEmpty })).sorted()
    }

    /// Jump the Map tab to an incident (used by a notification tap). If the
    /// incident isn't in the current window, refresh once and try again.
    func focusIncident(number: Int) {
        selectedTab = 0
        if let inc = incidents.first(where: { $0.number == number }) {
            mapFocus = inc
            return
        }
        Task {
            await refresh()
            if let inc = incidents.first(where: { $0.number == number }) {
                mapFocus = inc
            }
        }
    }
}

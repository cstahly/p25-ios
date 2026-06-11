import Foundation
import Combine

extension Notification.Name {
    static let p25NewTX = Notification.Name("p25NewTX")
}

@MainActor
class P25Store: ObservableObject {
    static let shared = P25Store()

    @Published var incidents: [Incident] = []
    @Published var recentTX: [TXEvent] = []
    @Published var audioFilter: String = "all"
    @Published var isStreaming = false
    @Published var lastError: String?

    private var streamTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var lastRefresh: Date = .distantPast

    private init() {}

    func start() {
        guard P25Client.shared.isConfigured else { return }
        guard streamTask == nil else { return }
        Task { await refresh() }
        Task { await backfillTX() }
        startStreaming()
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

    func stop() {
        streamTask?.cancel()
        refreshTimer?.invalidate()
        isStreaming = false
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
                        recentTX.insert(event, at: 0)
                        if recentTX.count > 100 { recentTX.removeLast() }
                        NotificationCenter.default.post(name: .p25NewTX, object: event)
                        // Throttle incident refreshes to once per 5 seconds
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
}

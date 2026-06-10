import SwiftUI

struct LogView: View {
    @State private var entries: [TXEvent] = []
    @State private var searchText = ""
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var maxId = 0
    @State private var minId = 0

    private var filtered: [TXEvent] {
        guard !searchText.isEmpty else { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            ($0.talkgroup ?? "").lowercased().contains(q) ||
            ($0.text ?? "").lowercased().contains(q) ||
            ($0.agency ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { tx in
                    LogRow(event: tx, audio: P25AudioPlayer.shared)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                if hasMore && searchText.isEmpty {
                    HStack {
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Color.clear.frame(height: 1)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { loadOlder() }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search talkgroup or transcript")
            .navigationTitle("Log")
            .refreshable { await loadNewer() }
            .task { await initialLoad() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await loadNewer()
                }
            }
        }
    }

    private func initialLoad() async {
        guard entries.isEmpty else { return }
        do {
            let rows = try await P25Client.shared.fetchTransmissions()
            entries = rows
            maxId = rows.map(\.dbId).max() ?? 0
            minId = rows.map(\.dbId).min() ?? 0
            hasMore = rows.count >= 50
        } catch {}
    }

    private func loadNewer() async {
        guard maxId > 0 else { await initialLoad(); return }
        do {
            let rows = try await P25Client.shared.fetchTransmissions(afterId: maxId)
            if rows.isEmpty { return }
            entries.insert(contentsOf: rows, at: 0)
            maxId = rows.map(\.dbId).max() ?? maxId
        } catch {}
    }

    private func loadOlder() {
        guard !isLoadingMore && hasMore && minId > 0 else { return }
        isLoadingMore = true
        Task {
            do {
                let rows = try await P25Client.shared.fetchTransmissions(beforeId: minId)
                entries.append(contentsOf: rows)
                minId = rows.map(\.dbId).min() ?? minId
                hasMore = rows.count >= 50
            } catch {}
            isLoadingMore = false
        }
    }
}

@MainActor
struct LogRow: View {
    let event: TXEvent
    @ObservedObject var audio: P25AudioPlayer

    private var isPlaying: Bool {
        audio.isPlayingClip && audio.currentClipFile == event.wavFile
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.talkgroup ?? "Unknown")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let trunk = event.trunk {
                        Text(trunk == "tippecanoe" ? "TC" : "ST")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(trunk == "tippecanoe" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                            .foregroundColor(trunk == "tippecanoe" ? .blue : .purple)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(event.time ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let text = event.text, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let wav = event.wavFile {
                Button {
                    if isPlaying { audio.stopClip() }
                    else { Task { await audio.playClip(wav) } }
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

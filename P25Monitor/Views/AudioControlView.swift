import SwiftUI

struct AudioControlView: View {
    @EnvironmentObject var store: P25Store
    @EnvironmentObject var audio: P25AudioPlayer

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Play button
                VStack(spacing: 16) {
                    Button(action: audio.toggle) {
                        ZStack {
                            Circle()
                                .fill(audio.isPlaying ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
                                .frame(width: 120, height: 120)
                            Image(systemName: audio.isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 44))
                                .foregroundColor(audio.isPlaying ? .red : .accentColor)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(audio.isPlaying ? "LIVE" : "Stopped")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(audio.isPlaying ? .red : .secondary)
                        .animation(.default, value: audio.isPlaying)

                    if audio.isPlaying {
                        Text(audio.currentTalkgroup)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(.secondarySystemBackground))

                // Channel filter
                VStack(alignment: .leading, spacing: 12) {
                    Text("Channel")
                        .font(.headline)
                        .padding(.horizontal)

                    Picker("Channel", selection: Binding(
                        get: { store.audioFilter },
                        set: { store.setAudioFilter($0) }
                    )) {
                        Text("All").tag("all")
                        Text("Tippecanoe").tag("0")
                        Text("SAFE-T").tag("1")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.top, 24)

                Divider().padding(.vertical, 24)

                // Recent traffic
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent Traffic")
                            .font(.headline)
                        Spacer()
                        if store.isStreaming {
                            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal)

                    if store.recentTX.isEmpty {
                        Text("No traffic yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(store.recentTX.prefix(20)) { tx in
                                    TXEventRow(event: tx)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("Audio")
            .onReceive(store.$recentTX) { tx in
                if let latest = tx.first, audio.isPlaying {
                    audio.updateNowPlaying(talkgroup: latest.talkgroup ?? "P25 Monitor")
                }
            }
        }
    }
}

struct TXEventRow: View {
    let event: TXEvent
    @EnvironmentObject var audio: P25AudioPlayer

    var isThisClipPlaying: Bool {
        audio.isPlayingClip && audio.currentClipFile == event.wavFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.talkgroup ?? "Unknown")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let wav = event.wavFile {
                    Button {
                        if isThisClipPlaying { audio.stopClip() }
                        else { Task { await audio.playClip(wav) } }
                    } label: {
                        Image(systemName: isThisClipPlaying ? "stop.circle.fill" : "play.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                Text(event.time ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let trunk = event.trunk {
                    Text(trunk == "tippecanoe" ? "TC" : "SAFE-T")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(trunk == "tippecanoe" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                        .foregroundColor(trunk == "tippecanoe" ? .blue : .purple)
                        .clipShape(Capsule())
                }
            }
            if let text = event.text, !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

import SwiftUI

struct AudioControlView: View {
    @EnvironmentObject var store: P25Store
    @EnvironmentObject var audio: P25AudioPlayer

    private var p25Playing: Bool { audio.isPlaying && audio.source == .p25 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Play button
                VStack(spacing: 16) {
                    Button(action: { p25Playing ? audio.stop() : audio.play(.p25) }) {
                        ZStack {
                            Circle()
                                .fill(p25Playing ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.12))
                                .frame(width: 120, height: 120)
                            Image(systemName: p25Playing ? "stop.fill" : "play.fill")
                                .font(.system(size: 44))
                                .foregroundColor(p25Playing ? .red : .accentColor)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(p25Playing ? "LIVE" : "Stopped")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(p25Playing ? .red : .secondary)
                        .animation(.default, value: p25Playing)

                    if p25Playing {
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

                MarineRow()
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
                if let latest = tx.first, p25Playing {
                    audio.updateNowPlaying(talkgroup: latest.talkgroup ?? "P25 Monitor")
                }
            }
        }
    }
}

/// Marine Ch16 from the Destin station. Only playable while that radio is
/// tuned to marine; otherwise says what it's doing instead.
struct MarineRow: View {
    @EnvironmentObject var audio: P25AudioPlayer
    @ObservedObject private var destin = DestinRadio.shared

    private var playing: Bool { audio.isPlaying && audio.source == .marine }
    private var available: Bool { destin.isOnMarine || playing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destin")
                .font(.headline)
            Button {
                playing ? audio.stop() : audio.play(.marine)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(!available ? .secondary : playing ? .red : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Marine Ch16")
                            .font(.body.weight(.semibold))
                            .foregroundColor(available ? .primary : .secondary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if playing {
                        Text("LIVE")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        .padding(.horizontal)
        .task { await destin.refresh() }
    }

    private var subtitle: String {
        if playing { return "Live from the Destin station" }
        if destin.isOnMarine { return "Radio is tuned to Ch16" }
        if let note = audio.marineNote { return note }
        if let label = destin.modeLabel { return "Radio is on \(label) right now" }
        return destin.reachable ? "Radio is off Ch16" : "Can't reach Destin"
    }
}

struct TXEventRow: View {
    let event: TXEvent
    @EnvironmentObject var audio: P25AudioPlayer

    var isThisClipPlaying: Bool { audio.isPlayingClip && audio.currentClipFile == event.wavFile }
    var isThisClipLoading: Bool { audio.isLoadingClip && audio.currentClipFile == event.wavFile }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.talkgroup ?? "Unknown")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let wav = event.wavFile {
                    Button {
                        if isThisClipPlaying || isThisClipLoading { audio.stopClip() }
                        else { Task { await audio.playClip(wav) } }
                    } label: {
                        Group {
                            if isThisClipLoading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: isThisClipPlaying ? "stop.circle.fill" : "play.circle")
                                    .font(.system(size: 18))
                            }
                        }
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(audio.isLoadingClip && !isThisClipLoading)
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

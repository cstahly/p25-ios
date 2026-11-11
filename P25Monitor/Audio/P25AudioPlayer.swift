import AVFoundation
import MediaPlayer

@MainActor
class P25AudioPlayer: ObservableObject {
    static let shared = P25AudioPlayer()

    /// What the live player is (or was last) playing.
    enum Source { case p25, marine }

    @Published var isPlaying = false
    @Published private(set) var source: Source = .p25
    @Published var currentTalkgroup: String = "P25 Monitor"
    /// Why marine playback stopped on its own (the Destin radio changed mode).
    @Published var marineNote: String?

    private var player: AVPlayer?
    private var clipPlayer: AVPlayer?
    @Published var isPlayingClip = false
    @Published var isLoadingClip = false
    @Published var currentClipFile: String?

    private init() {
        setupSession()
        setupRemoteCommands()
    }

    private func setupSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        center.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
    }

    func play() { play(source) }

    func play(_ src: Source) {
        player?.pause()
        source = src
        let url: URL
        switch src {
        case .p25:
            url = P25Client.shared.audioURL()
            currentTalkgroup = "P25 Monitor"
        case .marine:
            url = DestinRadio.marineStreamURL
            currentTalkgroup = "Marine Ch16"
            marineNote = nil
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        let headers = ["Authorization": P25Client.shared.authHeader]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        // A live stream that drops (Wi-Fi blip, the Destin radio restarting)
        // ends the item; try again while the user still wants it playing.
        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                               object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retry(src, item: item) }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func retry(_ src: Source, item: AVPlayerItem) {
        guard isPlaying, source == src, player?.currentItem === item else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard isPlaying, source == src, player?.currentItem === item else { return }
            if src == .marine && !DestinRadio.shared.isOnMarine { destinModeChanged(); return }
            play(src)
        }
    }

    /// Called after every Destin mode poll.
    func destinModeChanged() {
        let d = DestinRadio.shared
        guard isPlaying, source == .marine, let m = d.mode, m != "marine" else { return }
        stop()
        marineNote = "Stopped - Destin radio switched to \(d.modeLabel ?? m)"
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func toggle() {
        isPlaying ? stop() : play()
    }

    func playClip(_ filename: String) async {
        guard !isLoadingClip else { return }
        stopClip()
        // Re-activate the session — it may be inactive when launched via CarPlay
        try? AVAudioSession.sharedInstance().setActive(true)
        isLoadingClip = true
        currentClipFile = filename
        defer { isLoadingClip = false }
        guard let token = try? await P25Client.shared.fetchAudioToken() else {
            currentClipFile = nil; return
        }
        let url = P25Client.shared.clipURL(filename: filename, token: token)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        clipPlayer = player
        isPlayingClip = true
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clipPlayer = nil
                self?.isPlayingClip = false
                self?.currentClipFile = nil
            }
        }
        player.play()
    }

    func stopClip() {
        clipPlayer?.pause()
        clipPlayer = nil
        isPlayingClip = false
        isLoadingClip = false
        currentClipFile = nil
    }

    func updateNowPlaying(talkgroup: String? = nil) {
        if let tg = talkgroup { currentTalkgroup = tg }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTalkgroup,
            MPMediaItemPropertyArtist: source == .marine ? "Destin, FL" : "Tippecanoe County P25",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}

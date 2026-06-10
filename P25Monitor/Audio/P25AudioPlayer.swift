import AVFoundation
import MediaPlayer

@MainActor
class P25AudioPlayer: ObservableObject {
    static let shared = P25AudioPlayer()

    @Published var isPlaying = false
    @Published var currentTalkgroup: String = "P25 Monitor"

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

    func play() {
        let url = P25Client.shared.audioURL()
        let headers = ["Authorization": P25Client.shared.authHeader]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
        updateNowPlaying()
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
            MPMediaItemPropertyArtist: "Tippecanoe County P25",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}

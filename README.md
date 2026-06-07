# P25 Monitor — iOS + CarPlay

iOS app for [p25.sadbabyrabbit.com](https://p25.sadbabyrabbit.com) — live P25 radio incidents, map, and audio for Tippecanoe County, Indiana. Works on iPhone and CarPlay.

## Features

- **Map** — incident pins with status color, tap for callout, filter by Active/Watch/Clear
- **Incidents list** — live updates via SSE, pull to refresh, status filter
- **Audio** — live P25 audio stream (MP3), channel filter (All / Tippecanoe / SAFE-T)
- **CarPlay** — map tab + incidents list tab, now playing bar shows current talkgroup
- **Recent traffic** — last 50 transcribed transmissions with talkgroup, trunk, and text

## Build

### Prerequisites

```bash
brew install xcodegen
```

And an Apple Developer account (free or paid — paid required for CarPlay entitlements).

### Steps

1. Clone this repo
2. Fill in your Team ID in `project.yml`:
   ```yaml
   DEVELOPMENT_TEAM: "XXXXXXXXXX"   # Settings → Apple ID → team ID
   ```
3. Generate the Xcode project:
   ```bash
   xcodegen
   ```
4. Open `P25Monitor.xcodeproj` in Xcode
5. Run on your device

### First launch

Enter your credentials (same as the web app login) in the Connect screen. They're stored in UserDefaults on-device.

## CarPlay entitlements

CarPlay requires Apple entitlements — apply at [developer.apple.com/carplay](https://developer.apple.com/carplay):

| Entitlement | What it enables |
|-------------|----------------|
| `com.apple.developer.carplay-maps` | CPMapTemplate, CPTabBarTemplate |
| `com.apple.developer.carplay-audio` | CPNowPlayingTemplate |

Apply for **Navigation** (maps) to get the full map + tab bar experience. Without the entitlement you can test in the CarPlay Simulator (Xcode → Features → CarPlay) but it won't load on a real head unit.

**To test without entitlements**: Open the CarPlay Simulator via Xcode's `I/O → Simulator → CarPlay`. The app will appear and templates will render — entitlements are only enforced on real hardware via the App Store / TestFlight.

## Architecture

```
P25Client       — URLSession API client, SSE stream, auth headers
P25Store        — @MainActor ObservableObject, shared state, 30s refresh timer
P25AudioPlayer  — AVPlayer wrapper, MPRemoteCommandCenter, MPNowPlayingInfoCenter
CarPlayCoordinator — CPMapTemplate + CPListTemplate + MKMapView in CPWindow
```

## API (p25_server.py)

| Endpoint | Description |
|----------|-------------|
| `GET /api/state` | Incidents + entries snapshot |
| `GET /api/stream` | SSE: `{type,time,talkgroup,agency,trunk,text}` |
| `GET /api/audio` | Live MP3 stream (Icecast-style) |
| `GET /api/audio-filter` | Current channel filter |
| `POST /api/audio-filter` | Set channel filter: `{"filter":"all"\|"0"\|"1"}` |

All endpoints require HTTP Basic Auth.

## Related repos

- [cstahly/op25_tippecanoe](https://github.com/cstahly/op25_tippecanoe) — server, web app, talkgroup tags
- [cstahly/op25](https://github.com/cstahly/op25) — OP25 fork with Whisper STT + audio filter

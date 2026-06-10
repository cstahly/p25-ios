import Foundation
import CoreLocation

struct Incident: Identifiable, Codable, Equatable {
    let id: String
    let number: Int
    let title: String
    let agency: String
    let status: String
    let statusKind: String
    let location: String
    let firstSeen: String?
    let lastSeen: String?
    let lat: Double?
    let lng: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var statusEmoji: String {
        switch statusKind {
        case "active":  return "🔴"
        case "watch":   return "🟡"
        case "clear":   return "⚪"
        default:        return "🟠"
        }
    }

    var age: String {
        guard let lastSeen else { return "" }
        let fmts = ["yyyy-MM-dd HH:mm:ss", "HH:mm:ss"]
        let df = DateFormatter()
        for fmt in fmts {
            df.dateFormat = fmt
            if var date = df.date(from: lastSeen) {
                if fmt == "HH:mm:ss" {
                    let cal = Calendar.current
                    let now = Date()
                    date = cal.date(bySettingHour: cal.component(.hour, from: date),
                                   minute: cal.component(.minute, from: date),
                                   second: cal.component(.second, from: date),
                                   of: now) ?? date
                }
                let secs = -date.timeIntervalSinceNow
                if secs < 60  { return "just now" }
                if secs < 3600 { return "\(Int(secs/60))m ago" }
                return "\(Int(secs/3600))h ago"
            }
        }
        return lastSeen
    }

    var firstSeenDisplay: String {
        guard let firstSeen else { return "" }
        return _timeDisplay(from: firstSeen)
    }

    var lastSeenDisplay: String {
        guard let lastSeen else { return "" }
        return _timeDisplay(from: lastSeen)
    }

    private func _timeDisplay(from raw: String) -> String {
        let fmts = ["yyyy-MM-dd HH:mm:ss", "HH:mm:ss"]
        let df = DateFormatter()
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        for fmt in fmts {
            df.dateFormat = fmt
            if var date = df.date(from: raw) {
                if fmt == "HH:mm:ss" {
                    let cal = Calendar.current
                    let now = Date()
                    date = cal.date(bySettingHour: cal.component(.hour, from: date),
                                   minute: cal.component(.minute, from: date),
                                   second: cal.component(.second, from: date),
                                   of: now) ?? date
                }
                return out.string(from: date)
            }
        }
        return raw
    }

    let details: [String]?
    let action: String?
    let firstTxId: Int?
    let lastTxId: Int?
    let priority: Int?  // 1-5 urgency; nil from older server = treat as 3

    enum CodingKeys: String, CodingKey {
        case id, number, title, agency, status, location, lat, lng
        case statusKind = "status_kind"
        case firstSeen  = "first_seen"
        case lastSeen   = "last_seen"
        case details, action, priority
        case firstTxId  = "first_tx_id"
        case lastTxId   = "last_tx_id"
    }
}

struct TXEvent: Identifiable, Codable {
    var id = UUID().uuidString
    let type: String
    let time: String?
    let talkgroup: String?
    let agency: String?
    let trunk: String?
    let text: String?
    let wavFile: String?
    var dbId: Int = 0

    enum CodingKeys: String, CodingKey {
        case type, time, talkgroup, agency, trunk, text
        case wavFile = "wav_file"
    }
}

struct StateResponse: Codable {
    let incidents: [Incident]
}

struct TXRow: Codable {
    let id: Int
    let time: String?
    let talkgroup: String?
    let agency: String?
    let trunk: String?
    let text: String?
    let wavFile: String?

    enum CodingKeys: String, CodingKey {
        case id, time, talkgroup, agency, trunk, text
        case wavFile = "wav_file"
    }

    func toTXEvent() -> TXEvent {
        TXEvent(type: "tx", time: time, talkgroup: talkgroup, agency: agency,
                trunk: trunk, text: text, wavFile: wavFile, dbId: id)
    }
}


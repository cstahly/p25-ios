import Foundation
import CoreLocation
import SwiftUI

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

    var isCleared: Bool { statusKind == "clear" }

    var priorityLevel: Int { priority ?? 3 }

    var priorityLabel: String {
        switch priorityLevel {
        case 1: return "1 - Critical"
        case 2: return "2 - Serious"
        case 4: return "4 - Minor"
        case 5: return "5 - Routine"
        default: return "3 - Moderate"
        }
    }

    var priorityColor: Color { IncidentStyle.color(priority: priorityLevel) }

    var firstSeenDate: Date? { IncidentStyle.parseServerDate(firstSeen) }
    var lastSeenDate: Date? { IncidentStyle.parseServerDate(lastSeen) }

    var age: String {
        guard let d = lastSeenDate else { return lastSeen ?? "" }
        let secs = -d.timeIntervalSinceNow
        if secs < 60  { return "just now" }
        if secs < 3600 { return "\(Int(secs/60))m ago" }
        return "\(Int(secs/3600))h ago"
    }

    var firstSeenDisplay: String {
        firstSeenDate.map { IncidentStyle.displayFormatter.string(from: $0) } ?? (firstSeen ?? "")
    }

    var lastSeenDisplay: String {
        lastSeenDate.map { IncidentStyle.displayFormatter.string(from: $0) } ?? (lastSeen ?? "")
    }

    let details: [String]?
    let action: String?
    let firstTxId: Int?
    let lastTxId: Int?
    let priority: Int?  // 1-5 urgency; nil from older server = treat as 3
    let isStale: Bool?
    let precise: Int?   // 1 = precise geocode, 0 = approximate; nil from older server = precise

    var stale: Bool { isStale ?? false }
    var approxLocation: Bool { precise == 0 }  // excluded from the heatmap density

    enum CodingKeys: String, CodingKey {
        case id, number, title, agency, status, location, lat, lng
        case statusKind = "status_kind"
        case firstSeen  = "first_seen"
        case lastSeen   = "last_seen"
        case details, action, priority, precise
        case firstTxId  = "first_tx_id"
        case lastTxId   = "last_tx_id"
        case isStale    = "is_stale"
    }
}

/// DeFlock-sourced ALPR (Flock) camera from /api/alpr.
struct ALPRCamera: Identifiable, Codable {
    let lat: Double
    let lng: Double
    let dir: Double?
    let maker: String?
    let zone: String?

    var id: String { "\(lat),\(lng)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var operatorName: String { maker ?? "ALPR" }

    enum CodingKeys: String, CodingKey {
        case lat, lng, dir, zone
        case maker = "operator"
    }
}

struct ALPRResponse: Codable { let cameras: [ALPRCamera] }

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


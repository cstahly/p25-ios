import SwiftUI
import UIKit

/// The one visual language for incidents, shared by the list, map, callout,
/// detail screen and CarPlay:
///   color  = priority (P1 purple, P2 red, P3 yellow, P4 blue, P5 slate)
///   solid  = still going (active / routine)
///   dashed = still open but gone quiet (server's is_stale)
///   hollow gray = cleared
enum IncidentStyle {

    static func uiColor(priority: Int) -> UIColor {
        switch priority {
        case 1:  return UIColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1) // #a855f7
        case 2:  return UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1) // #ef4444
        case 3:  return UIColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1) // #eab308
        case 4:  return UIColor(red: 0.05, green: 0.65, blue: 0.91, alpha: 1) // #0ea5e9
        default: return UIColor(red: 0.28, green: 0.33, blue: 0.41, alpha: 1) // #475569
        }
    }

    static func color(priority: Int) -> Color { Color(uiColor(priority: priority)) }

    static let clearedGray = UIColor(red: 0.61, green: 0.64, blue: 0.69, alpha: 1)

    /// Numbered priority circle. `scale` lets CarPlay draw slightly larger pins.
    /// A week of history is ~3,000 pins drawn from ~20 distinct images - cache them.
    private static let pinCache = NSCache<NSString, UIImage>()

    static func pinImage(for inc: Incident, scale: CGFloat = 1) -> UIImage {
        let key = "\(inc.priorityLevel)|\(inc.isCleared)|\(inc.stale)|\(scale)" as NSString
        if let hit = pinCache.object(forKey: key) { return hit }
        let img = renderPin(for: inc, scale: scale)
        pinCache.setObject(img, forKey: key)
        return img
    }

    private static func renderPin(for inc: Incident, scale: CGFloat) -> UIImage {
        let prio = inc.priorityLevel
        let base: CGFloat = [1: 30, 2: 26, 3: 22, 4: 18, 5: 16][prio] ?? 22
        // Cleared pins shrink so the live ones stand out.
        let size = (inc.isCleared ? max(14, base - 6) : base) * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
            let fill: UIColor
            let ink: UIColor
            if inc.isCleared {
                fill = UIColor(white: 0.92, alpha: 0.9)
                ink = clearedGray
            } else {
                fill = uiColor(priority: prio)
                ink = .white
            }
            fill.setFill()
            c.fillEllipse(in: rect)
            ink.setStroke()
            c.setLineWidth(inc.isCleared ? 1.5 : 2)
            if inc.stale && !inc.isCleared { c.setLineDash(phase: 0, lengths: [3, 2]) }
            c.strokeEllipse(in: rect)
            let text = "\(prio)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.48, weight: .heavy),
                .foregroundColor: ink]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
        }
    }

    // MARK: - Server timestamps

    /// Server times are local to Tippecanoe County (Eastern), either
    /// "yyyy-MM-dd HH:mm:ss" or a bare "HH:mm:ss" meaning today.
    private static let serverTZ = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = serverTZ
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = serverTZ
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static func parseServerDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = fullFormatter.date(from: raw) { return d }
        guard let t = timeFormatter.date(from: raw) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = serverTZ
        let hms = cal.dateComponents([.hour, .minute, .second], from: t)
        return cal.date(bySettingHour: hms.hour ?? 0, minute: hms.minute ?? 0,
                        second: hms.second ?? 0, of: Date())
    }
}

/// SwiftUI version of the pin: one dot, same rules as the map.
struct IncidentDot: View {
    let incident: Incident
    var size: CGFloat = 14

    var body: some View {
        let color = IncidentStyle.color(priority: incident.priorityLevel)
        ZStack {
            if incident.isCleared {
                Circle().strokeBorder(Color(IncidentStyle.clearedGray), lineWidth: 1.5)
            } else if incident.stale {
                Circle().fill(color.opacity(0.6))
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(incident.priorityLabel), \(incident.isCleared ? "cleared" : "active")")
    }
}

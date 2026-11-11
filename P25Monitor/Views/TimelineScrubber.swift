import SwiftUI

/// Splunk-style time picker: a histogram of cleared calls per hour for the past
/// week, with a handle you drag to choose how far back the map reaches. "Now" is
/// the right edge.
///
/// The x-axis is stretched so recent hours are wide and old ones narrow: the
/// labelled stops (1h, 4h, 12h, 1d, 3d, 7d) are evenly spaced. Every bar is still
/// exactly one hour, so the daily rhythm shows, and the last few hours are easy
/// to hit with a thumb.
struct TimelineScrubber: View {
    let counts: [Int]               // [0] = most recent hour
    let committedHours: Int
    let onCommit: (Int) -> Void

    @State private var draft: Int?  // while dragging

    static let maxHours = 168
    private static let stops: [Double] = [0, 1, 2, 4, 8, 12, 24, 48, 72, 120, 168]
    private static let labelled: [(Double, String)] = [(1, "1h"), (4, "4h"), (12, "12h"), (24, "1d"), (72, "3d"), (168, "7d")]

    /// 0 = now, 1 = a week ago.
    static func frac(_ hours: Double) -> Double {
        let h = min(max(hours, 0), stops.last!)
        for i in 1..<stops.count where h <= stops[i] {
            let t = (h - stops[i - 1]) / (stops[i] - stops[i - 1])
            return (Double(i - 1) + t) / Double(stops.count - 1)
        }
        return 1
    }

    static func hours(atFrac f: Double) -> Double {
        let f = min(max(f, 0), 1) * Double(stops.count - 1)
        let i = min(Int(f), stops.count - 2)
        return stops[i] + (f - Double(i)) * (stops[i + 1] - stops[i])
    }

    static func label(_ hours: Int) -> String {
        if hours < 24 { return "\(hours)h" }
        let d = hours / 24, h = hours % 24
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    private var shown: Int { draft ?? committedHours }

    private var selectedCount: Int { counts.prefix(shown).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cleared calls, last \(Self.label(shown))")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(counts.isEmpty ? "" : "\(selectedCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let x: (Double) -> CGFloat = { hrs in w * (1 - Self.frac(hrs)) }
                let peak = Double(max(counts.max() ?? 1, 1))
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for (k, c) in counts.prefix(Self.maxHours).enumerated() where c > 0 {
                            let x0 = x(Double(k + 1)), x1 = x(Double(k))
                            // sqrt keeps quiet hours visible next to busy ones
                            let bh = max(2, CGFloat((Double(c) / peak).squareRoot()) * (h - 4))
                            let rect = CGRect(x: x0, y: h - bh, width: max(x1 - x0 - 0.5, 0.5), height: bh)
                            ctx.fill(Path(rect), with: .color(k < shown ? .accentColor : .secondary.opacity(0.35)))
                        }
                    }
                    // Handle
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: h + 6)
                        .offset(x: x(Double(shown)) - 1, y: -3)
                    Circle()
                        .fill(Color.accentColor)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .offset(x: x(Double(shown)) - 9, y: h / 2 - 9)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let hrs = Self.hours(atFrac: 1 - Double(g.location.x / w))
                        draft = max(1, Int(hrs.rounded()))
                    }
                    .onEnded { _ in
                        if let d = draft { onCommit(d) }
                        draft = nil
                    })
            }
            .frame(height: 56)

            GeometryReader { geo in
                ForEach(Self.labelled, id: \.0) { hrs, text in
                    Text(text)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(x: geo.size.width * (1 - Self.frac(hrs)), y: 6)
                }
                Text("now")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize()
                    .position(x: geo.size.width - 8, y: 6)
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time range")
        .accessibilityValue("Last \(Self.label(shown))")
        .accessibilityAdjustableAction { dir in
            let opts = [1, 2, 4, 8, 12, 24, 48, 72, 120, 168]
            let i = opts.lastIndex(where: { $0 <= committedHours }) ?? 0
            let n = dir == .increment ? min(i + 1, opts.count - 1) : max(i - 1, 0)
            onCommit(opts[n])
        }
    }
}

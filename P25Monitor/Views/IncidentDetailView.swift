import SwiftUI

struct IncidentDetailView: View {
    let incident: Incident
    @State private var transmissions: [TXEvent] = []
    @State private var loadingTX = false
    @Environment(\.openURL) private var openURL

    var statusColor: Color {
        switch incident.statusKind {
        case "active": return .red
        case "watch":  return .orange
        case "clear":  return .gray
        default:       return .yellow
        }
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(incident.statusEmoji) \(incident.title)")
                        .font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        Text(incident.statusKind.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(statusColor.opacity(0.15))
                            .foregroundColor(statusColor)
                            .clipShape(Capsule())
                        Text(incident.agency)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Status + location
            Section {
                LabeledContent("Status", value: incident.status)
                LabeledContent("Priority") {
                    Text(incident.priorityLabel)
                        .foregroundColor(incident.priorityLevel <= 2 ? incident.priorityColor : .primary)
                }
                if !incident.location.isEmpty {
                    LabeledContent("Location", value: incident.location)
                }
                if !incident.firstSeenDisplay.isEmpty {
                    LabeledContent("First seen", value: incident.firstSeenDisplay)
                }
                if !incident.lastSeenDisplay.isEmpty {
                    LabeledContent("Last seen", value: incident.lastSeenDisplay)
                }
            }

            // Details
            if let details = incident.details, !details.isEmpty {
                Section("Details") {
                    ForEach(details, id: \.self) { detail in
                        Text("• \(detail)")
                            .font(.subheadline)
                    }
                }
            }

            // Action / MyCase
            if let action = incident.action, !action.isEmpty {
                Section("Action") {
                    ActionView(text: action)
                }
            }

            // Related transmissions
            if let fromId = incident.firstTxId, let toId = incident.lastTxId, fromId > 0 {
                Section("Radio Traffic") {
                    if loadingTX {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if transmissions.isEmpty {
                        Text("No transmissions found")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(transmissions) { tx in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(tx.talkgroup ?? "Unknown")
                                        .font(.caption.weight(.semibold))
                                    if let trunk = tx.trunk {
                                        Text(trunk == "tippecanoe" ? "TC" : "ST")
                                            .font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(trunk == "tippecanoe" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                                            .foregroundColor(trunk == "tippecanoe" ? .blue : .purple)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(tx.time ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let text = tx.text, !text.isEmpty {
                                    Text(text)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .task {
                    loadingTX = true
                    transmissions = (try? await P25Client.shared.fetchTransmissions(
                        limit: 500, fromId: fromId, toId: toId
                    )) ?? []
                    loadingTX = false
                }
            }
        }
        .navigationTitle("Incident \(incident.number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Renders plain text with inline markdown links as tappable Link views
private struct ActionView: View {
    let text: String

    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

    struct Segment { var label: String; var url: URL? }

    var segments: [Segment] {
        var result: [Segment] = []
        let ns = text as NSString
        var cursor = 0
        let matches = Self.linkPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let preRange = NSRange(location: cursor, length: m.range.location - cursor)
            if preRange.length > 0 {
                result.append(Segment(label: ns.substring(with: preRange), url: nil))
            }
            let label = ns.substring(with: m.range(at: 1))
            let urlStr = ns.substring(with: m.range(at: 2))
            result.append(Segment(label: label, url: URL(string: urlStr)))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result.append(Segment(label: ns.substring(from: cursor), url: nil))
        }
        return result.isEmpty ? [Segment(label: text, url: nil)] : result
    }

    var body: some View {
        segments.isEmpty ? AnyView(EmptyView()) : AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if let url = seg.url {
                        Link(seg.label, destination: url)
                            .font(.subheadline)
                    } else if !seg.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(seg.label)
                            .font(.subheadline)
                    }
                }
            }
        )
    }
}

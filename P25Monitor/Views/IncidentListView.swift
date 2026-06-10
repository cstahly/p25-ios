import SwiftUI

struct IncidentListView: View {
    @EnvironmentObject var store: P25Store
    @State private var statusFilter = "active"

    var filtered: [Incident] {
        let list = store.incidents.filter {
            statusFilter == "all"    ? true :
            statusFilter == "open"   ? ($0.statusKind != "clear") :
            statusFilter == "high"   ? $0.priorityLevel <= 2 :
                                       $0.statusKind == statusFilter
        }
        return list.sorted {
            if $0.priorityLevel != $1.priorityLevel { return $0.priorityLevel < $1.priorityLevel }
            return statusWeight($0.statusKind) < statusWeight($1.statusKind)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Incidents")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { incident in
                        NavigationLink(destination: IncidentDetailView(incident: incident)) {
                            IncidentRow(incident: incident)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Incidents")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("Open") { statusFilter = "open" }
                            Button("Active") { statusFilter = "active" }
                            Button("High Priority (P1–P2)") { statusFilter = "high" }
                            Button("All") { statusFilter = "all" }
                        } label: {
                            Label(statusFilter == "high" ? "High" : statusFilter.capitalized,
                                  systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .refreshable { await store.refresh() }
        }
    }
}

struct IncidentRow: View {
    let incident: Incident

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(priorityColor(incident.priorityLevel).opacity(0.55))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(incident.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(incident.agency)
                    if !incident.location.isEmpty {
                        Text("·")
                        Text(incident.location)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !incident.firstSeenDisplay.isEmpty {
                    Text("↑ \(incident.firstSeenDisplay)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !incident.lastSeenDisplay.isEmpty {
                    Text("↓ \(incident.lastSeenDisplay)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Text("P\(incident.priorityLevel)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(incident.priorityColor.opacity(0.15))
                        .foregroundColor(incident.priorityColor)
                        .clipShape(Capsule())
                    Text(incident.statusKind.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
            }
        }
    }

    var statusColor: Color {
        switch incident.statusKind {
        case "active": return .red
        case "routine": return .orange
        case "clear":  return .gray
        default:       return .yellow
        }
    }

    func statusWeight(_ kind: String) -> Int {
        switch kind {
        case "active": return 0
        case "routine": return 1
        case "clear":  return 3
        default:       return 2
        }
    }

    func priorityColor(_ p: Int) -> Color {
        switch p {
        case 1: return Color(red: 0.66, green: 0.33, blue: 0.97) // #a855f7 purple
        case 2: return Color(red: 0.94, green: 0.27, blue: 0.27) // #ef4444 red
        case 3: return Color(red: 0.92, green: 0.70, blue: 0.03) // #eab308 yellow
        case 4: return Color(red: 0.05, green: 0.65, blue: 0.91) // #0ea5e9 sky
        default: return Color(red: 0.28, green: 0.33, blue: 0.41) // #475569 slate
        }
    }
}

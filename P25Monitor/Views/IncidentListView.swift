import SwiftUI

struct IncidentListView: View {
    @EnvironmentObject var store: P25Store
    @State private var statusFilter = "active"
    @State private var sortByPriority = false

    var filtered: [Incident] {
        var list = store.incidents.filter {
            statusFilter == "all"    ? true :
            statusFilter == "open"   ? ($0.statusKind != "clear") :
            statusFilter == "high"   ? $0.priorityLevel <= 2 :
                                       $0.statusKind == statusFilter
        }
        if sortByPriority {
            list.sort {
                if $0.priorityLevel != $1.priorityLevel { return $0.priorityLevel < $1.priorityLevel }
                return ($0.lastSeen ?? "") > ($1.lastSeen ?? "")
            }
        }
        return list
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
                        Button {
                            sortByPriority.toggle()
                        } label: {
                            Image(systemName: sortByPriority ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                .foregroundColor(sortByPriority ? .orange : .secondary)
                        }
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
                    .fill(priorityColor(incident.priorityLevel).opacity(0.25))
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
                    if incident.priorityLevel <= 2 {
                        Text("P\(incident.priorityLevel)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(incident.priorityColor.opacity(0.15))
                            .foregroundColor(incident.priorityColor)
                            .clipShape(Capsule())
                    }
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
        case "watch":  return .orange
        case "clear":  return .gray
        default:       return .yellow
        }
    }

    func priorityColor(_ p: Int) -> Color {
        switch p {
        case 1: return .red
        case 2: return .orange
        case 3: return Color(red: 0.92, green: 0.70, blue: 0.03)
        case 4: return .blue
        default: return .gray
        }
    }
}

import SwiftUI

struct IncidentListView: View {
    @EnvironmentObject var store: P25Store
    @State private var statusFilter = "active"

    var filtered: [Incident] {
        store.incidents.filter { statusFilter == "all" || $0.statusKind == statusFilter }
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
                    Menu {
                        ForEach(["all", "active", "watch", "clear"], id: \.self) { f in
                            Button(f.capitalized) { statusFilter = f }
                        }
                    } label: {
                        Label(statusFilter.capitalized, systemImage: "line.3.horizontal.decrease.circle")
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
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

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

    var statusColor: Color {
        switch incident.statusKind {
        case "active": return .red
        case "watch":  return .orange
        case "clear":  return .gray
        default:       return .yellow
        }
    }
}

import SwiftUI

struct IncidentListView: View {
    @EnvironmentObject var store: P25Store
    @State private var statusFilter = "active"

    var filtered: [Incident] {
        let list = store.incidents.filter {
            statusFilter == "all"      ? true :
            statusFilter == "critical" ? ($0.statusKind != "clear" && $0.priorityLevel <= 2) :
                                         $0.statusKind != "clear"  // "active" default
        }
        // Open calls first, then by priority, then most recently heard.
        return list.sorted {
            if $0.isCleared != $1.isCleared { return !$0.isCleared }
            if $0.priorityLevel != $1.priorityLevel { return $0.priorityLevel < $1.priorityLevel }
            let w0 = statusWeight($0.statusKind), w1 = statusWeight($1.statusKind)
            if w0 != w1 { return w0 < w1 }
            return ($0.lastSeenDate ?? .distantPast) > ($1.lastSeenDate ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: store.lastError != nil
                              ? "exclamationmark.triangle"
                              : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        // Distinguish "genuinely no incidents" from "the fetch failed"
                        // — otherwise a connection/auth error looks like an empty board.
                        if let err = store.lastError {
                            Text("Couldn't load incidents")
                                .foregroundColor(.secondary)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Text("\(store.incidents.count) loaded · filter: \(statusFilter)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button("Retry") { Task { await store.refresh() } }
                                .buttonStyle(.bordered)
                        } else if store.incidents.isEmpty {
                            Text("No Incidents")
                                .foregroundColor(.secondary)
                        } else {
                            // Incidents loaded, but the current filter hides them all.
                            Text("No \(statusFilter) incidents")
                                .foregroundColor(.secondary)
                            Text("\(store.incidents.count) total · tap the filter to show all")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                            Button("Active") { statusFilter = "active" }
                            Button("Critical (P1–P2)") { statusFilter = "critical" }
                            Button("All") { statusFilter = "all" }
                        } label: {
                            Label(statusFilter == "critical" ? "Critical" : statusFilter.capitalized,
                                  systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .refreshable { await store.refresh() }
        }
    }
}

private func statusWeight(_ kind: String) -> Int {
    switch kind {
    case "active": return 0
    case "routine": return 1
    case "clear":  return 3
    default:       return 2
    }
}

struct IncidentRow: View {
    let incident: Incident

    var body: some View {
        HStack(spacing: 12) {
            IncidentDot(incident: incident, size: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(incident.title)
                    .font(.headline)
                    .foregroundColor(incident.isCleared ? .secondary : .primary)
                    .lineLimit(2)
                Text([incident.agency, incident.location].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("P\(incident.priorityLevel)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(incident.isCleared ? .secondary : incident.priorityColor)
                Text(incident.isCleared ? "cleared \(incident.age)" : incident.age)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

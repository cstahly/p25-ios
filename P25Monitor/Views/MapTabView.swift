import SwiftUI
import MapKit

struct MapTabView: View {
    @EnvironmentObject var store: P25Store
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.4167, longitude: -86.8753),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @State private var selectedIncident: Incident?
    @State private var detailIncident: Incident?
    @State private var mapFilter = "now"  // "critical" | "now" | "8hr" | "all"

    var visibleIncidents: [Incident] {
        let cutoff8hr = Date().addingTimeInterval(-8 * 3600)
        return store.incidents.filter {
            guard $0.coordinate != nil else { return false }
            switch mapFilter {
            case "critical": return $0.statusKind != "clear" && $0.priorityLevel <= 2
            case "now":      return $0.statusKind != "clear"
            case "8hr":      return $0.statusKind != "clear" || _withinCutoff($0, cutoff: cutoff8hr)
            default:         return true
            }
        }
    }

    private func _withinCutoff(_ inc: Incident, cutoff: Date) -> Bool {
        guard let raw = inc.firstSeen else { return false }
        let df = DateFormatter()
        for fmt in ["yyyy-MM-dd HH:mm:ss", "HH:mm:ss"] {
            df.dateFormat = fmt
            if var d = df.date(from: raw) {
                if fmt == "HH:mm:ss" {
                    let cal = Calendar.current; let now = Date()
                    d = cal.date(bySettingHour: cal.component(.hour, from: d),
                                 minute: cal.component(.minute, from: d),
                                 second: cal.component(.second, from: d), of: now) ?? d
                }
                return d >= cutoff
            }
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(coordinateRegion: $region, annotationItems: visibleIncidents) { incident in
                MapAnnotation(coordinate: incident.coordinate!) {
                    IncidentMapPin(incident: incident, isSelected: selectedIncident?.id == incident.id)
                        .onTapGesture { selectedIncident = incident }
                }
            }
            .ignoresSafeArea(edges: .top)

            if let inc = selectedIncident {
                IncidentCallout(incident: inc,
                                onDismiss: { selectedIncident = nil },
                                onDetail: { detailIncident = inc; selectedIncident = nil })
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 1) {
                    ForEach([("critical", "Critical"), ("now", "Now"), ("8hr", "8hr"), ("all", "All")], id: \.0) { val, label in
                        Button(label) { mapFilter = val }
                            .font(.subheadline.weight(mapFilter == val ? .semibold : .regular))
                            .frame(minWidth: 72)
                            .padding(.vertical, 14)
                            .background(mapFilter == val ? Color.accentColor : Color(.systemBackground))
                            .foregroundColor(mapFilter == val ? .white : .primary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .animation(.default, value: mapFilter)
            }
        }
        .sheet(item: $detailIncident) { inc in
            NavigationStack {
                IncidentDetailView(incident: inc)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { detailIncident = nil }
                        }
                    }
            }
        }
    }
}

struct IncidentMapPin: View {
    let incident: Incident
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor)
                .frame(width: isSelected ? 28 : 20, height: isSelected ? 28 : 20)
                .shadow(radius: isSelected ? 6 : 2)
            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
        .animation(.spring(), value: isSelected)
    }

    var pinColor: Color { incident.priorityColor }
}

struct IncidentCallout: View {
    let incident: Incident
    let onDismiss: () -> Void
    let onDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(incident.statusEmoji) \(incident.title)")
                        .font(.headline)
                    Text(incident.agency)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !incident.location.isEmpty {
                        Label(incident.location, systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !incident.firstSeenDisplay.isEmpty {
                        Label("First: \(incident.firstSeenDisplay)", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            Button(action: onDetail) {
                Label("View Details", systemImage: "chevron.right.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}

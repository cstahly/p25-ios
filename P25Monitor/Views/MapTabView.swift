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
    @State private var statusFilter = "all"
    @State private var timeFilterHours: Int? = 4  // nil = all time

    var visibleIncidents: [Incident] {
        store.incidents.filter {
            guard $0.coordinate != nil else { return false }
            if statusFilter != "all" && $0.statusKind != statusFilter { return false }
            if let hours = timeFilterHours, let last = $0.lastSeen {
                let fmts = ["yyyy-MM-dd HH:mm:ss", "HH:mm:ss"]
                let df = DateFormatter()
                for fmt in fmts {
                    df.dateFormat = fmt
                    if var d = df.date(from: last) {
                        if fmt == "HH:mm:ss" {
                            let cal = Calendar.current; let now = Date()
                            d = cal.date(bySettingHour: cal.component(.hour, from: d),
                                         minute: cal.component(.minute, from: d),
                                         second: cal.component(.second, from: d), of: now) ?? d
                        }
                        if -d.timeIntervalSinceNow > Double(hours) * 3600 { return false }
                        break
                    }
                }
            }
            return true
        }
    }

    var body: some View {
        ZStack {
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
            }

            VStack(spacing: 6) {
                // Status filter
                HStack(spacing: 0) {
                    ForEach(["all", "active", "watch", "clear"], id: \.self) { f in
                        Button(f.capitalized) { statusFilter = f }
                            .font(.caption.weight(statusFilter == f ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusFilter == f ? Color.accentColor : Color(.systemBackground))
                            .foregroundColor(statusFilter == f ? .white : .primary)
                    }
                }
                .clipShape(Capsule())
                .shadow(radius: 4)

                // Time filter
                HStack(spacing: 0) {
                    ForEach([(nil, "All"), (4, "4h"), (12, "12h"), (24, "24h")] as [(Int?, String)], id: \.1) { hours, label in
                        Button(label) { timeFilterHours = hours }
                            .font(.caption.weight(timeFilterHours == hours ? .bold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(timeFilterHours == hours ? Color.accentColor : Color(.systemBackground))
                            .foregroundColor(timeFilterHours == hours ? .white : .primary)
                    }
                }
                .clipShape(Capsule())
                .shadow(radius: 4)
            }
            .padding(.bottom, selectedIncident == nil ? 12 : 120)
            .animation(.default, value: selectedIncident)
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

    var pinColor: Color {
        switch incident.statusKind {
        case "active": return .red
        case "watch":  return .orange
        case "clear":  return .gray
        default:       return .yellow
        }
    }
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

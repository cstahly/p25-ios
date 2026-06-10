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
    @State private var priorityFilter = 0  // 0=all, 1=P1 only, 2=P1-P2, 3=P1-P3

    var visibleIncidents: [Incident] {
        store.incidents.filter {
            guard $0.coordinate != nil else { return false }
            if priorityFilter > 0 && $0.priorityLevel > priorityFilter { return false }
            return true
        }
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
                HStack(spacing: 0) {
                    ForEach([(0, "All"), (1, "P1"), (2, "P1–2"), (3, "P1–3")], id: \.0) { val, label in
                        Button(label) { priorityFilter = val }
                            .font(.caption.weight(priorityFilter == val ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(priorityFilter == val ? Color.accentColor : Color(.systemBackground))
                            .foregroundColor(priorityFilter == val ? .white : .primary)
                    }
                }
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 12)
                .animation(.default, value: priorityFilter)
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

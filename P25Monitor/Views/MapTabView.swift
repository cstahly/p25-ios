import SwiftUI
import MapKit

struct MapTabView: View {
    @EnvironmentObject var store: P25Store
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.4167, longitude: -86.8753),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @State private var selectedIncident: Incident?
    @State private var statusFilter = "all"

    var visibleIncidents: [Incident] {
        store.incidents.filter {
            $0.coordinate != nil &&
            (statusFilter == "all" || $0.statusKind == statusFilter)
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

            VStack {
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
                .padding(.top, 8)

                Spacer()

                if let inc = selectedIncident {
                    IncidentCallout(incident: inc) { selectedIncident = nil }
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    var body: some View {
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
                Text(incident.status)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}

import SwiftUI
import MapKit
import CoreLocation

// Lafayette IN 47905 — fallback when device location is unavailable
let kFallbackCenter = CLLocationCoordinate2D(latitude: 40.3978, longitude: -86.8465)

/// Spread incidents that geocode to the identical point (e.g. "Lafayette")
/// in a small circle so they stay individually tappable.
/// Shared logic with the web map (~80 m ring).
func spreadCoincident(_ incidents: [Incident]) -> [(incident: Incident, coordinate: CLLocationCoordinate2D)] {
    var groups: [String: [Incident]] = [:]
    for inc in incidents {
        guard let c = inc.coordinate else { continue }
        let key = String(format: "%.5f,%.5f", c.latitude, c.longitude)
        groups[key, default: []].append(inc)
    }
    var out: [(Incident, CLLocationCoordinate2D)] = []
    for (_, group) in groups {
        if group.count == 1, let c = group[0].coordinate {
            out.append((group[0], c))
            continue
        }
        let r = 0.0008  // ~80 m
        for (k, inc) in group.enumerated() {
            guard let c = inc.coordinate else { continue }
            let angle = (2.0 * .pi * Double(k)) / Double(group.count)
            out.append((inc, CLLocationCoordinate2D(
                latitude: c.latitude + r * sin(angle),
                longitude: c.longitude + r * cos(angle) / cos(c.latitude * .pi / 180))))
        }
    }
    return out
}

struct MapPinItem: Identifiable {
    let incident: Incident
    let coordinate: CLLocationCoordinate2D
    var id: String { incident.id }
}

final class LocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?

    func requestLocation(_ done: @escaping (CLLocationCoordinate2D?) -> Void) {
        completion = done
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            done(nil); completion = nil
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            completion?(nil); completion = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completion?(locations.first?.coordinate); completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(nil); completion = nil
    }
}

struct MapTabView: View {
    @EnvironmentObject var store: P25Store
    @StateObject private var locator = LocationFetcher()
    @State private var region = MKCoordinateRegion(
        center: kFallbackCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @State private var selectedIncident: Incident?
    @State private var detailIncident: Incident?
    @State private var mapFilter = "now"  // "critical" | "now" | "8hr" | "all"

    // Semantics match the web map's defaults: time-windowed on last_seen.
    // now = 4h window (any status), critical = open P1-P2 within 4h,
    // 8hr = 8h window, all = everything.
    var visibleIncidents: [Incident] {
        let h4 = Date().addingTimeInterval(-4 * 3600)
        let h8 = Date().addingTimeInterval(-8 * 3600)
        return store.incidents.filter {
            guard $0.coordinate != nil else { return false }
            switch mapFilter {
            case "critical": return $0.statusKind != "clear" && $0.priorityLevel <= 2 && _seen($0, since: h4)
            case "now":      return _seen($0, since: h4)
            case "8hr":      return _seen($0, since: h8)
            default:         return true
            }
        }
    }

    var pinItems: [MapPinItem] {
        spreadCoincident(visibleIncidents).map { MapPinItem(incident: $0.incident, coordinate: $0.coordinate) }
    }

    private func _seen(_ inc: Incident, since cutoff: Date) -> Bool {
        guard let raw = inc.lastSeen else { return false }
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

    private func goToCurrentLocation() {
        locator.requestLocation { coord in
            withAnimation {
                region = MKCoordinateRegion(
                    center: coord ?? kFallbackCenter,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: pinItems) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    IncidentMapPin(incident: item.incident, isSelected: selectedIncident?.id == item.incident.id)
                        .onTapGesture { selectedIncident = item.incident }
                }
            }
            .ignoresSafeArea(edges: .top)

            // Locate button — top right
            VStack {
                HStack {
                    Spacer()
                    Button(action: goToCurrentLocation) {
                        Image(systemName: "location.fill")
                            .font(.body.weight(.semibold))
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

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

    // Sizes match the web map: P1 dominates, P5 recedes
    private var size: CGFloat {
        let s: CGFloat = [1: 30, 2: 26, 3: 22, 4: 18, 5: 16][incident.priorityLevel] ?? 22
        return isSelected ? s + 6 : s
    }

    private var stale: Bool { incident.stale }

    // Dark variants match web _darkenHex(color, 0.68)
    private var fill: Color {
        if !stale { return incident.priorityColor }
        switch incident.priorityLevel {
        case 1: return Color(red: 0.45, green: 0.00, blue: 0.89) // #7400e2
        case 2: return Color(red: 0.80, green: 0.01, blue: 0.01) // #cd0303
        case 3: return Color(red: 0.65, green: 0.49, blue: 0.00) // #a57d00
        case 4: return Color(red: 0.00, green: 0.45, blue: 0.66) // #0074a8
        default: return Color(red: 0.18, green: 0.22, blue: 0.29) // #2f3949
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .opacity(stale ? 0.85 : 1)
            if stale {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69)) // #9ca3af
            } else {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            }
            Text("\(incident.priorityLevel)")
                .font(.system(size: size * 0.48, weight: .heavy))
                .foregroundColor(stale ? Color(red: 0.61, green: 0.64, blue: 0.69) : .white)
        }
        .frame(width: size, height: size)
        .shadow(radius: isSelected ? 6 : 2)
        .animation(.spring(), value: isSelected)
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

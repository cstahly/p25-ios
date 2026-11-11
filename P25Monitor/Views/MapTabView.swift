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

// MARK: - Pin images (incident pins come from IncidentStyle.pinImage)

func cameraPinImage(dir: Double?) -> UIImage {
    let size: CGFloat = 22
    let red = UIColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
        let c = ctx.cgContext
        let center = CGPoint(x: size / 2, y: size / 2)
        // Facing-direction arrow (north-up triangle rotated clockwise by bearing).
        if let dir {
            c.saveGState()
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: CGFloat(dir) * .pi / 180)
            red.setFill()
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: 0, y: -size / 2 + 1))
            tri.addLine(to: CGPoint(x: -4, y: -2))
            tri.addLine(to: CGPoint(x: 4, y: -2))
            tri.close()
            tri.fill()
            c.restoreGState()
        }
        // Camera dot
        let r: CGFloat = 5
        let dot = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        red.setFill()
        c.fillEllipse(in: dot)
        UIColor.white.setStroke()
        c.setLineWidth(2)
        c.strokeEllipse(in: dot)
    }
}

// MARK: - Annotations

final class IncidentAnnotation: NSObject, MKAnnotation {
    var incident: Incident
    let coordinate: CLLocationCoordinate2D
    init(incident: Incident, coordinate: CLLocationCoordinate2D) {
        self.incident = incident
        self.coordinate = coordinate
    }
}

final class CameraAnnotation: NSObject, MKAnnotation {
    let camera: ALPRCamera
    var coordinate: CLLocationCoordinate2D { camera.coordinate }
    var title: String? { "\(camera.operatorName) camera" }
    var subtitle: String? {
        if let d = camera.dir { return "Faces \(Int(d.rounded()))° · DeFlock/OSM" }
        return "DeFlock/OSM"
    }
    init(camera: ALPRCamera) { self.camera = camera }
}

// MARK: - Heatmap overlay (additive radial-gradient density, precise points only)

final class HeatOverlay: NSObject, MKOverlay {
    let points: [CLLocationCoordinate2D]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect = .world
    init(points: [CLLocationCoordinate2D]) {
        self.points = points
        self.coordinate = points.first ?? kFallbackCenter
    }
}

final class HeatOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heat = overlay as? HeatOverlay else { return }
        let radius = CGFloat(26) / zoomScale
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 1, green: 1.0, blue: 0, alpha: 0.55).cgColor,
            UIColor(red: 1, green: 0.3, blue: 0, alpha: 0.35).cgColor,
            UIColor(red: 1, green: 0.0, blue: 0, alpha: 0.0).cgColor,
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.5, 1]) else { return }
        context.setBlendMode(.plusLighter)
        let drawRect = mapRect.insetBy(dx: -Double(radius), dy: -Double(radius))
        for c in heat.points {
            let mp = MKMapPoint(c)
            guard drawRect.contains(mp) else { continue }
            let p = point(for: mp)
            context.drawRadialGradient(grad, startCenter: p, startRadius: 0,
                                       endCenter: p, endRadius: radius, options: [])
        }
    }
}

// MARK: - MapKit bridge

struct IncidentMapView: UIViewRepresentable {
    var pins: [(incident: Incident, coordinate: CLLocationCoordinate2D)]
    var cameras: [ALPRCamera]
    var showHeat: Bool
    var heatPoints: [CLLocationCoordinate2D]
    var showALPR: Bool
    @Binding var recenter: CLLocationCoordinate2D?
    var onSelect: (Incident) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.setRegion(MKCoordinateRegion(center: kFallbackCenter,
                     span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)), animated: false)
        return mv
    }

    func updateUIView(_ mv: MKMapView, context: Context) {
        context.coordinator.parent = self
        if let c = recenter {
            mv.setRegion(MKCoordinateRegion(center: c,
                         span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: true)
            DispatchQueue.main.async { self.recenter = nil }
        }
        context.coordinator.syncAnnotations(mv, pins: pins, cameras: showALPR ? cameras : [])
        context.coordinator.syncHeat(mv, show: showHeat, points: heatPoints)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: IncidentMapView
        private var heat: HeatOverlay?
        private var heatKey = -2
        init(_ p: IncidentMapView) { parent = p }

        private var camCount = -1

        /// Diff pins by incident id instead of wiping the map on every refresh -
        /// the wipe was what made pins blink and reshuffle.
        func syncAnnotations(_ mv: MKMapView,
                             pins: [(incident: Incident, coordinate: CLLocationCoordinate2D)],
                             cameras: [ALPRCamera]) {
            var wanted: [String: (incident: Incident, coordinate: CLLocationCoordinate2D)] = [:]
            for p in pins { wanted[p.incident.id] = p }

            var toRemove: [MKAnnotation] = []
            var have = Set<String>()
            for case let ann as IncidentAnnotation in mv.annotations {
                guard let w = wanted[ann.incident.id],
                      abs(w.coordinate.latitude - ann.coordinate.latitude) < 1e-7,
                      abs(w.coordinate.longitude - ann.coordinate.longitude) < 1e-7 else {
                    toRemove.append(ann); continue
                }
                have.insert(ann.incident.id)
                if w.incident != ann.incident {
                    ann.incident = w.incident
                    if let v = mv.view(for: ann) { style(v, for: w.incident) }
                }
            }
            mv.removeAnnotations(toRemove)
            mv.addAnnotations(pins.filter { !have.contains($0.incident.id) }
                .map { IncidentAnnotation(incident: $0.incident, coordinate: $0.coordinate) })

            if cameras.count != camCount {
                camCount = cameras.count
                mv.removeAnnotations(mv.annotations.filter { $0 is CameraAnnotation })
                mv.addAnnotations(cameras.map { CameraAnnotation(camera: $0) })
            }
        }

        private func style(_ v: MKAnnotationView, for inc: Incident) {
            v.image = IncidentStyle.pinImage(for: inc)
            // Live calls sit on top of cleared ones and are never decluttered away.
            v.zPriority = inc.isCleared ? .defaultUnselected : .max
            v.displayPriority = inc.isCleared ? .defaultHigh : .required
        }

        func syncHeat(_ mv: MKMapView, show: Bool, points: [CLLocationCoordinate2D]) {
            let want = show ? points.count : -1
            guard want != heatKey else { return }
            heatKey = want
            if let h = heat { mv.removeOverlay(h); heat = nil }
            guard show, !points.isEmpty else { return }
            let h = HeatOverlay(points: points)
            mv.addOverlay(h, level: .aboveRoads)
            heat = h
        }

        func mapView(_ mv: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let h = overlay as? HeatOverlay { return HeatOverlayRenderer(overlay: h) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let ia = annotation as? IncidentAnnotation {
                let v = mv.dequeueReusableAnnotationView(withIdentifier: "inc")
                    ?? MKAnnotationView(annotation: ia, reuseIdentifier: "inc")
                v.annotation = ia
                v.canShowCallout = false
                v.clusteringIdentifier = nil       // never collate into a "12" bubble
                style(v, for: ia.incident)
                return v
            }
            if let ca = annotation as? CameraAnnotation {
                let v = mv.dequeueReusableAnnotationView(withIdentifier: "cam")
                    ?? MKAnnotationView(annotation: ca, reuseIdentifier: "cam")
                v.annotation = ca
                v.image = cameraPinImage(dir: ca.camera.dir)
                v.canShowCallout = true
                v.clusteringIdentifier = nil
                v.displayPriority = .required
                return v
            }
            return nil
        }

        func mapView(_ mv: MKMapView, didSelect view: MKAnnotationView) {
            guard let ia = view.annotation as? IncidentAnnotation else { return }
            mv.deselectAnnotation(ia, animated: false)
            parent.onSelect(ia.incident)
        }
    }
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
    @EnvironmentObject var audio: P25AudioPlayer
    @StateObject private var locator = LocationFetcher()
    @State private var selectedIncident: Incident?
    @State private var detailIncident: Incident?
    @State private var showHeat = false
    @State private var showALPR = false
    @State private var recenter: CLLocationCoordinate2D?

    // Everything the store holds: every open incident regardless of priority, plus
    // cleared ones inside the chosen history range (small gray pins).
    var visibleIncidents: [Incident] {
        store.incidents.filter {
            // Skip the un-mappable approximate pile (everything that geocoded to the
            // city centroid) - it's the blob that made the map unreadable.
            $0.coordinate != nil && !$0.approxLocation
        }
    }

    private var unmappedOpen: Int {
        store.incidents.filter { !$0.isCleared && ($0.coordinate == nil || $0.approxLocation) }.count
    }

    static let historyRanges: [(hours: Int, label: String)] = [
        (1, "Last hour"), (6, "Last 6 hours"), (24, "Last 24 hours"), (72, "Last 3 days"), (168, "Last week"),
    ]

    private var rangeLabel: String {
        switch store.historyHours {
        case 1:   return "in the last hour"
        case 72:  return "in 3 days"
        case 168: return "in the last week"
        default:  return "in \(store.historyHours)h"
        }
    }

    // Heatmap = full-history density of precise points (loaded on demand so the
    // normal poll stays light).
    var heatPoints: [CLLocationCoordinate2D] {
        store.heatIncidents.filter { !$0.approxLocation }.compactMap { $0.coordinate }
    }

    private func goToCurrentLocation() {
        locator.requestLocation { coord in recenter = coord ?? kFallbackCenter }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            IncidentMapView(pins: spreadCoincident(visibleIncidents),
                            cameras: store.alprCameras,
                            showHeat: showHeat,
                            heatPoints: heatPoints,
                            showALPR: showALPR,
                            recenter: $recenter,
                            onSelect: { selectedIncident = $0 })
                .ignoresSafeArea(edges: .top)

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        mapButton("location.fill", on: false) { goToCurrentLocation() }
                        mapButton("flame.fill", on: showHeat) { showHeat.toggle() }
                        mapButton("video.fill", on: showALPR) { showALPR.toggle() }
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
                VStack(spacing: 8) {
                    if unmappedOpen > 0 {
                        // Open calls with no usable location can't be pinned; don't
                        // let them silently disappear.
                        Button { store.selectedTab = 1 } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.slash")
                                Text("\(unmappedOpen) more open \(unmappedOpen == 1 ? "call has" : "calls have") no map location")
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    historyControl
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
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
            .environmentObject(store)
            .environmentObject(audio)
        }
        .onChange(of: store.mapFocus) { foc in
            // Jump here from an incident elsewhere: recenter + open its callout.
            guard let foc, let c = foc.coordinate else { return }
            recenter = c
            selectedIncident = foc
            store.mapFocus = nil
        }
        .onChange(of: showHeat) { on in
            if on { Task { await store.loadHeatData() } }   // fetch full history only when needed
        }
    }

    /// One line that says what you're looking at; tap it to reach further back.
    private var historyControl: some View {
        let open = visibleIncidents.filter { !$0.isCleared }.count
        let cleared = visibleIncidents.count - open
        return Menu {
            Picker("Show cleared calls from", selection: Binding(
                get: { store.historyHours },
                set: { store.setHistory(hours: $0) })) {
                ForEach(Self.historyRanges, id: \.hours) { r in Text(r.label).tag(r.hours) }
            }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(open > 0 ? Color.red : Color.green).frame(width: 8, height: 8)
                Text(open == 0 ? "Nothing open" : "\(open) open")
                    .font(.subheadline.weight(.semibold))
                Text("· \(cleared) cleared \(rangeLabel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if store.isLoadingHistory {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(store.historyHours > 1 ? .accentColor : .secondary)
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
    }

    private func mapButton(_ system: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(on ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundColor(on ? .white : .primary)
                .clipShape(Circle())
                .shadow(radius: 3)
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        IncidentDot(incident: incident, size: 12)
                        Text(incident.title)
                            .font(.headline)
                    }
                    Text(incident.agency)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !incident.location.isEmpty {
                        Label(incident.location, systemImage: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !incident.firstSeenDisplay.isEmpty {
                        Label(incident.isCleared ? "Cleared · last heard \(incident.age)"
                                                 : "Started \(incident.firstSeenDisplay) · last heard \(incident.age)",
                              systemImage: "clock")
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

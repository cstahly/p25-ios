import CarPlay
import MapKit
import Combine

class CarPlayCoordinator: NSObject {

    private let interfaceController: CPInterfaceController
    private let window: CPWindow
    private var mapView: MKMapView?
    private var mapTemplate: CPMapTemplate?
    private var listTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()

    init(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window
    }

    @MainActor
    func setup() {
        // Map view fills the CarPlay window
        let mv = MKMapView(frame: window.bounds)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.4167, longitude: -86.8753),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
        ), animated: false)
        mv.delegate = self
        window.addSubview(mv)
        mapView = mv

        // Map template (provides CarPlay toolbar chrome)
        let mt = CPMapTemplate()
        mt.mapDelegate = self
        mt.trailingNavigationBarButtons = [
            CPBarButton(title: "Refresh") { [weak self] _ in
                Task { await P25Store.shared.refresh() }
                self?.updateMap(incidents: P25Store.shared.incidents)
            }
        ]
        mapTemplate = mt

        // Incidents list template
        let lt = CPListTemplate(title: "Incidents", sections: [])
        lt.tabTitle = "Incidents"
        lt.tabImage = UIImage(systemName: "list.bullet.clipboard")
        listTemplate = lt

        mt.tabTitle = "Map"
        mt.tabImage = UIImage(systemName: "map.fill")

        // Tab bar combines both
        let tabs = CPTabBarTemplate(templates: [mt, lt])
        interfaceController.setRootTemplate(tabs, animated: false) { _, _ in }

        // Observe store
        Task { @MainActor in
            P25Store.shared.$incidents
                .receive(on: DispatchQueue.main)
                .sink { [weak self] incidents in
                    self?.updateMap(incidents: incidents)
                    self?.updateList(incidents: incidents)
                }
                .store(in: &cancellables)

            P25Store.shared.$recentTX
                .compactMap { $0.first }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tx in
                    self?.mapTemplate?.leadingNavigationBarButtons = [
                        CPBarButton(title: tx.talkgroup.flatMap { String($0.prefix(20)) } ?? "")
                    ]
                }
                .store(in: &cancellables)

            P25Store.shared.start()
        }
    }

    @MainActor
    private func updateMap(incidents: [Incident]) {
        guard let mapView else { return }
        mapView.removeAnnotations(mapView.annotations)
        let annotations: [MKPointAnnotation] = incidents.compactMap { inc in
            guard let coord = inc.coordinate else { return nil }
            let ann = MKPointAnnotation()
            ann.coordinate = coord
            ann.title = "\(inc.statusEmoji) \(inc.title)"
            ann.subtitle = "\(inc.agency) · \(inc.age)"
            return ann
        }
        mapView.addAnnotations(annotations)
    }

    @MainActor
    private func updateList(incidents: [Incident]) {
        let items: [CPListItem] = incidents.prefix(30).map { inc in
            let item = CPListItem(
                text: "\(inc.statusEmoji) \(inc.title)",
                detailText: "\(inc.agency)  \(inc.location.isEmpty ? "" : "· \(inc.location)")  \(inc.age)"
            )
            return item
        }
        listTemplate?.updateSections([CPListSection(items: items)])
    }
}

extension CarPlayCoordinator: CPMapTemplateDelegate {
    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {}
    func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {}
}

extension CarPlayCoordinator: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "incident")
        view.canShowCallout = true
        view.markerTintColor = .systemRed
        return view
    }
}

import CarPlay
import MapKit
import Combine
import MediaPlayer

class CarPlayCoordinator: NSObject {

    private let interfaceController: CPInterfaceController
    private let window: CPWindow
    private var mapView: MKMapView?
    private var mapTemplate: CPMapTemplate?
    private var listTemplate: CPListTemplate?
    private var logTemplate: CPListTemplate?
    private var tabBar: CPTabBarTemplate?
    private var cancellables = Set<AnyCancellable>()

    // Track annotations by incident number for incremental updates
    private var annotationMap: [Int: IncidentAnnotation] = [:]

    init(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window
    }

    @MainActor
    func setup() {
        let mv = MKMapView(frame: window.bounds)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.4167, longitude: -86.8753),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.14)
        ), animated: false)
        mv.delegate = self
        window.addSubview(mv)
        mapView = mv

        let mt = CPMapTemplate()
        mt.mapDelegate = self
        mt.trailingNavigationBarButtons = [
            CPBarButton(title: "Refresh") { [weak self] _ in
                Task { await P25Store.shared.refresh() }
            }
        ]
        mt.tabTitle = "Map"
        mt.tabImage = UIImage(systemName: "map.fill")
        mapTemplate = mt

        let lt = CPListTemplate(title: "Incidents", sections: [])
        lt.tabTitle = "Incidents"
        lt.tabImage = UIImage(systemName: "list.bullet.clipboard")
        listTemplate = lt

        let log = CPListTemplate(title: "Radio Log", sections: [])
        log.tabTitle = "Log"
        log.tabImage = UIImage(systemName: "text.bubble")
        logTemplate = log

        let tabs = CPTabBarTemplate(templates: [mt, lt, log])
        tabBar = tabs
        interfaceController.setRootTemplate(tabs, animated: false) { _, _ in }

        Task { @MainActor in
            P25Store.shared.$incidents
                .receive(on: DispatchQueue.main)
                .sink { [weak self] incidents in
                    self?.updateMap(incidents: incidents)
                    self?.updateList(incidents: incidents)
                }
                .store(in: &cancellables)

            P25Store.shared.$recentTX
                .receive(on: DispatchQueue.main)
                .sink { [weak self] txList in
                    self?.updateLog(txList: txList)
                    self?.updateNowPlayingBar(txList: txList)
                }
                .store(in: &cancellables)

            P25AudioPlayer.shared.$isPlaying
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshNowPlaying() }
                .store(in: &cancellables)

            P25Store.shared.start()
        }
    }

    // MARK: - Map

    @MainActor
    private func updateMap(incidents: [Incident]) {
        guard let mapView else { return }

        let incoming = Dictionary(uniqueKeysWithValues: incidents.compactMap { inc -> (Int, Incident)? in
            guard inc.coordinate != nil else { return nil }
            return (inc.number, inc)
        })

        // Remove stale
        for (num, ann) in annotationMap where incoming[num] == nil {
            mapView.removeAnnotation(ann)
            annotationMap.removeValue(forKey: num)
        }

        // Add/update
        for (num, inc) in incoming {
            if let existing = annotationMap[num] {
                existing.update(from: inc)
            } else {
                let ann = IncidentAnnotation(incident: inc)
                mapView.addAnnotation(ann)
                annotationMap[num] = ann
            }
        }
    }

    // MARK: - Incidents list

    @MainActor
    private func updateList(incidents: [Incident]) {
        let active  = incidents.filter { $0.statusKind != "clear" }
        let cleared = incidents.filter { $0.statusKind == "clear" }

        let makeItems: ([Incident]) -> [CPListItem] = { [weak self] list in
            list.prefix(30).map { inc in
                let detail = [inc.agency,
                              inc.location.isEmpty ? nil : inc.location,
                              inc.age.isEmpty ? nil : inc.age]
                    .compactMap { $0 }.joined(separator: " · ")
                let item = CPListItem(text: "\(inc.statusEmoji) \(inc.title)",
                                     detailText: detail)
                item.handler = { [weak self] _, completion in
                    self?.pushIncidentDetail(inc)
                    completion()
                }
                return item
            }
        }

        var sections: [CPListSection] = []
        if !active.isEmpty  { sections.append(CPListSection(items: makeItems(active),  header: "Active", sectionIndexTitle: nil)) }
        if !cleared.isEmpty { sections.append(CPListSection(items: makeItems(cleared), header: "Cleared", sectionIndexTitle: nil)) }
        if sections.isEmpty { sections = [CPListSection(items: [CPListItem(text: "No incidents", detailText: nil)])] }

        listTemplate?.updateSections(sections)
    }

    @MainActor
    private func pushIncidentDetail(_ incident: Incident) {
        var rows: [CPInformationItem] = [
            CPInformationItem(title: "Status",  detail: "\(incident.statusEmoji) \(incident.status)"),
            CPInformationItem(title: "Agency",  detail: incident.agency),
        ]
        if !incident.location.isEmpty {
            rows.append(CPInformationItem(title: "Location", detail: incident.location))
        }
        if !incident.firstSeenDisplay.isEmpty {
            rows.append(CPInformationItem(title: "First seen", detail: incident.firstSeenDisplay))
        }
        if !incident.lastSeenDisplay.isEmpty {
            rows.append(CPInformationItem(title: "Updated", detail: incident.lastSeenDisplay))
        }
        if let action = incident.action, !action.isEmpty {
            rows.append(CPInformationItem(title: "Action", detail: action))
        }
        for detail in (incident.details ?? []).prefix(4) {
            rows.append(CPInformationItem(title: nil, detail: detail))
        }

        var actions: [CPTextButton] = []
        if incident.coordinate != nil {
            actions.append(CPTextButton(title: "Show on Map", textStyle: .normal) { [weak self] _ in
                self?.focusMapOnIncident(incident)
            })
        }

        let tmpl = CPInformationTemplate(
            title: "#\(incident.number) \(incident.title)",
            layout: .twoColumn,
            items: rows,
            actions: actions
        )
        interfaceController.pushTemplate(tmpl, animated: true) { _, _ in }
    }

    @MainActor
    private func focusMapOnIncident(_ incident: Incident) {
        guard let coord = incident.coordinate, let mapView else { return }
        mapView.setRegion(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ), animated: true)
        interfaceController.popToRootTemplate(animated: true) { _, _ in }
        tabBar?.selectedTemplate = mapTemplate
    }

    // MARK: - Radio log

    @MainActor
    private func updateLog(txList: [TXEvent]) {
        let items: [CPListItem] = txList.prefix(50).map { tx in
            let tg   = tx.talkgroup ?? "Unknown"
            let time = tx.time ?? ""
            let item = CPListItem(
                text: "[\(time)] \(tg)",
                detailText: tx.text.flatMap { $0.isEmpty ? nil : $0 }
            )
            if let wav = tx.wavFile {
                item.accessoryType = .disclosureIndicator
                item.handler = { _, completion in
                    Task { @MainActor in
                        let audio = P25AudioPlayer.shared
                        if audio.isPlayingClip && audio.currentClipFile == wav {
                            audio.stopClip()
                        } else {
                            await audio.playClip(wav)
                        }
                        completion()
                    }
                }
            }
            return item
        }
        logTemplate?.updateSections([CPListSection(items: items)])
    }

    // MARK: - Now Playing bar

    @MainActor
    private func updateNowPlayingBar(txList: [TXEvent]) {
        guard let first = txList.first else { return }
        let tg = first.talkgroup.flatMap { String($0.prefix(24)) } ?? "P25"
        mapTemplate?.leadingNavigationBarButtons = [
            CPBarButton(title: "📻 \(tg)")
        ]
    }

    @MainActor
    private func refreshNowPlaying() {
        let audio = P25AudioPlayer.shared
        guard audio.isPlaying else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:           audio.currentTalkgroup,
            MPMediaItemPropertyArtist:          "Tippecanoe P25",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }
}

// MARK: - Annotation

class IncidentAnnotation: NSObject, MKAnnotation {
    private(set) var incident: Incident
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(incident: Incident) {
        self.incident = incident
        self.coordinate = incident.coordinate!
        super.init()
        update(from: incident)
    }

    func update(from inc: Incident) {
        incident = inc
        coordinate = inc.coordinate!
        title    = "\(inc.statusEmoji) \(inc.title)"
        subtitle = "\(inc.agency) · \(inc.age)"
    }
}

// MARK: - MKMapViewDelegate

extension CarPlayCoordinator: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let ann = annotation as? IncidentAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "incident") as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: "incident")
        view.annotation = ann
        view.canShowCallout = true
        view.markerTintColor = pinColor(for: ann.incident.statusKind)
        view.glyphText = ann.incident.statusEmoji
        return view
    }

    private func pinColor(for statusKind: String) -> UIColor {
        switch statusKind {
        case "active":  return .systemRed
        case "watch":   return .systemOrange
        case "clear":   return .systemGreen
        default:        return .systemYellow
        }
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlayCoordinator: CPMapTemplateDelegate {
    func mapTemplateDidShowPanningInterface(_ mapTemplate: CPMapTemplate) {}
    func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {}
}

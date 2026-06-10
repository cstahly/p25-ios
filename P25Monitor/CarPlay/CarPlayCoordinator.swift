import CarPlay
import Combine
import CoreLocation
import MapKit
import MediaPlayer

class CarPlayCoordinator: NSObject {

    private let interfaceController: CPInterfaceController
    private var poiTemplate: CPPointOfInterestTemplate?
    private var listTemplate: CPListTemplate?
    private var logTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()
    private let locationManager = CLLocationManager()

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    @MainActor
    func setup() {
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()

        let poi = CPPointOfInterestTemplate(title: "Incidents", pointsOfInterest: [], selectedIndex: NSNotFound)
        poi.pointOfInterestDelegate = self
        poi.tabTitle = "Map"
        poi.tabImage = UIImage(systemName: "map.fill")
        poiTemplate = poi

        let lt = CPListTemplate(title: "Incidents", sections: [])
        lt.tabTitle = "Incidents"
        lt.tabImage = UIImage(systemName: "list.bullet.clipboard")
        listTemplate = lt

        let log = CPListTemplate(title: "Radio Log", sections: [])
        log.tabTitle = "Log"
        log.tabImage = UIImage(systemName: "text.bubble")
        logTemplate = log

        let tabs = CPTabBarTemplate(templates: [poi, lt, log])
        interfaceController.setRootTemplate(tabs, animated: false) { _, _ in }

        Task { @MainActor in
            P25Store.shared.$incidents
                .receive(on: DispatchQueue.main)
                .sink { [weak self] incidents in
                    self?.updatePOI(incidents: incidents)
                    self?.updateList(incidents: incidents)
                }
                .store(in: &cancellables)

            P25Store.shared.$recentTX
                .receive(on: DispatchQueue.main)
                .sink { [weak self] txList in
                    self?.updateLog(txList: txList)
                }
                .store(in: &cancellables)

            P25AudioPlayer.shared.$isPlaying
                .receive(on: DispatchQueue.main)
                .sink { _ in CarPlayCoordinator.syncNowPlaying() }
                .store(in: &cancellables)

            P25Store.shared.start()
        }
    }

    // MARK: - POI map

    @MainActor
    private func updatePOI(incidents: [Incident]) {
        let prioritized = incidents
            .filter { $0.coordinate != nil }
            .sorted {
                let p0 = $0.priority ?? 3, p1 = $1.priority ?? 3
                if p0 != p1 { return p0 < p1 } // P1 = highest urgency
                let rank: (String) -> Int = { k in k == "active" ? 0 : k == "routine" ? 1 : 2 }
                return rank($0.statusKind) < rank($1.statusKind)
            }
            .prefix(12)
        let pois: [CPPointOfInterest] = prioritized.compactMap { inc in
            guard let coord = inc.coordinate else { return nil }
            let loc = MKMapItem(placemark: MKPlacemark(coordinate: coord))
            loc.name = "\(inc.statusEmoji) \(inc.title)"

            let poi = CPPointOfInterest(
                location: loc,
                title: "\(inc.statusEmoji) \(inc.title)",
                subtitle: inc.agency,
                summary: inc.location.isEmpty ? nil : inc.location,
                detailTitle: "\(inc.statusEmoji) \(inc.title)",
                detailSubtitle: "\(inc.agency) · \(inc.age)",
                detailSummary: [inc.action, inc.details?.first]
                    .compactMap { $0 }.filter { !$0.isEmpty }.first,
                pinImage: pinImage(for: inc.statusKind)
            )
            poi.userInfo = inc
            return poi
        }
        poiTemplate?.setPointsOfInterest(pois, selectedIndex: NSNotFound)
    }

    private func pinImage(for statusKind: String) -> UIImage? {
        let color: UIColor
        switch statusKind {
        case "active": color = .systemRed
        case "routine": color = .systemOrange
        case "clear":  color = .systemGreen
        default:       color = .systemYellow
        }
        let cfg = UIImage.SymbolConfiguration(paletteColors: [color])
        return UIImage(systemName: "circle.fill", withConfiguration: cfg)
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
                              inc.age.isEmpty      ? nil : inc.age]
                    .compactMap { $0 }.joined(separator: " · ")
                let item = CPListItem(text: "\(inc.statusEmoji) \(inc.title)", detailText: detail)
                item.handler = { [weak self] _, completion in
                    self?.pushIncidentDetail(inc)
                    completion()
                }
                return item
            }
        }

        var sections: [CPListSection] = []
        if !active.isEmpty  { sections.append(CPListSection(items: makeItems(active),  header: "Active",  sectionIndexTitle: nil)) }
        if !cleared.isEmpty { sections.append(CPListSection(items: makeItems(cleared), header: "Cleared", sectionIndexTitle: nil)) }
        if sections.isEmpty { sections = [CPListSection(items: [CPListItem(text: "No incidents", detailText: nil)])] }
        listTemplate?.updateSections(sections)
    }

    @MainActor
    private func pushIncidentDetail(_ incident: Incident) {
        var rows: [CPInformationItem] = [
            CPInformationItem(title: "Status",   detail: "\(incident.statusEmoji) \(incident.status)"),
            CPInformationItem(title: "Priority", detail: incident.priorityLabel),
            CPInformationItem(title: "Agency",   detail: incident.agency),
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
        for detail in (incident.details ?? []).prefix(3) {
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
        guard incident.coordinate != nil else { return }
        if let pois = poiTemplate?.pointsOfInterest,
           let idx = pois.firstIndex(where: { ($0.userInfo as? Incident)?.number == incident.number }) {
            poiTemplate?.setPointsOfInterest(pois, selectedIndex: idx)
        }
        interfaceController.popToRootTemplate(animated: true) { _, _ in }
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

    // MARK: - Now Playing

    @MainActor static func syncNowPlaying() {
        let audio = P25AudioPlayer.shared
        guard audio.isPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:             audio.currentTalkgroup,
            MPMediaItemPropertyArtist:            "Tippecanoe P25",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }
}

// MARK: - CPPointOfInterestTemplateDelegate

extension CarPlayCoordinator: CPPointOfInterestTemplateDelegate {
    func pointOfInterestTemplate(_ pointOfInterestTemplate: CPPointOfInterestTemplate,
                                 didChangeMapRegion region: MKCoordinateRegion) {}

    func pointOfInterestTemplate(_ pointOfInterestTemplate: CPPointOfInterestTemplate,
                                 didSelectPointOfInterest pointOfInterest: CPPointOfInterest) {
        guard let incident = pointOfInterest.userInfo as? Incident else { return }
        Task { @MainActor in pushIncidentDetail(incident) }
    }
}

// MARK: - CLLocationManagerDelegate

extension CarPlayCoordinator: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

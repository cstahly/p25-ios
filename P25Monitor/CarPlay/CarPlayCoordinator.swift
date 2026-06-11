import CarPlay
import Combine
import CoreLocation
import MapKit
import MediaPlayer

class CarPlayCoordinator: NSObject {

    private let interfaceController: CPInterfaceController
    private var tabBarTemplate: CPTabBarTemplate?
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
        tabBarTemplate = tabs
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
        let prioritized = Array(incidents
            .filter { $0.coordinate != nil && $0.statusKind != "clear" }
            .sorted {
                let p0 = $0.priority ?? 3, p1 = $1.priority ?? 3
                if p0 != p1 { return p0 < p1 }
                let rank: (String) -> Int = { k in k == "active" ? 0 : k == "routine" ? 1 : 2 }
                return rank($0.statusKind) < rank($1.statusKind)
            }
            .prefix(12))
        // Spread incidents that geocode to the identical point so pins don't stack
        let placed = spreadCoincident(prioritized)
        let pois: [CPPointOfInterest] = placed.map { inc, coord in
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
                pinImage: pinImage(for: inc)
            )
            poi.userInfo = inc
            return poi
        }
        poiTemplate?.setPointsOfInterest(pois, selectedIndex: NSNotFound)
    }

    /// Numbered circle sized by priority — matches the web/iOS map pins.
    private func pinImage(for inc: Incident) -> UIImage? {
        let prio = inc.priorityLevel
        let stale = inc.stale
        let live: [Int: UIColor] = [
            1: UIColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1),
            2: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1),
            3: UIColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1),
            4: UIColor(red: 0.05, green: 0.65, blue: 0.91, alpha: 1),
            5: UIColor(red: 0.28, green: 0.33, blue: 0.41, alpha: 1),
        ]
        let dark: [Int: UIColor] = [
            1: UIColor(red: 0.45, green: 0.00, blue: 0.89, alpha: 1),
            2: UIColor(red: 0.80, green: 0.01, blue: 0.01, alpha: 1),
            3: UIColor(red: 0.65, green: 0.49, blue: 0.00, alpha: 1),
            4: UIColor(red: 0.00, green: 0.45, blue: 0.66, alpha: 1),
            5: UIColor(red: 0.18, green: 0.22, blue: 0.29, alpha: 1),
        ]
        let fill = (stale ? dark[prio] : live[prio]) ?? .systemYellow
        let gray = UIColor(red: 0.61, green: 0.64, blue: 0.69, alpha: 1)
        let size: CGFloat = [1: 34, 2: 30, 3: 26, 4: 22, 5: 20][prio] ?? 26

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
            fill.setFill()
            ctx.cgContext.fillEllipse(in: rect)
            (stale ? gray : UIColor.white).setStroke()
            ctx.cgContext.setLineWidth(2)
            if stale { ctx.cgContext.setLineDash(phase: 0, lengths: [3, 2]) }
            ctx.cgContext.strokeEllipse(in: rect)
            let text = "\(prio)" as NSString
            let font = UIFont.systemFont(ofSize: size * 0.48, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: stale ? gray : UIColor.white]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
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
        // Pop the detail template first, then switch the tab bar to the Map
        // tab and select the POI — selection before the pop was being lost.
        interfaceController.popToRootTemplate(animated: false) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, let poi = self.poiTemplate else { return }
                self.tabBarTemplate?.select(poi)
                if let idx = poi.pointsOfInterest.firstIndex(where: {
                    ($0.userInfo as? Incident)?.number == incident.number
                }) {
                    poi.setPointsOfInterest(poi.pointsOfInterest, selectedIndex: idx)
                }
            }
        }
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

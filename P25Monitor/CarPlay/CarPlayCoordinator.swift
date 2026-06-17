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
    private var mapPinIndex: [Int: Int] = [:]   // incident number -> its numbered pin on the map

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
        let filterBtn = CPBarButton(title: "Filter") { [weak self] _ in
            Task { @MainActor in self?.pushLogFilterChooser() }
        }
        log.trailingNavigationBarButtons = [filterBtn]
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
        // Spread incidents that geocode to the identical point so pins don't stack,
        // then restore priority order (spreadCoincident returns arbitrary order).
        let placed = spreadCoincident(prioritized).sorted {
            let p0 = $0.incident.priorityLevel, p1 = $1.incident.priorityLevel
            if p0 != p1 { return p0 < p1 }
            return $0.incident.number > $1.incident.number
        }
        // Number pins and list rows the same so you can match a map pin to its row
        // (pin "3" == row "3.") — the list and map share this POI array order.
        var idxMap: [Int: Int] = [:]
        let pois: [CPPointOfInterest] = placed.enumerated().map { idx, pair in
            let inc = pair.incident
            let coord = pair.coordinate
            let label = "\(idx + 1)"
            idxMap[inc.number] = idx + 1
            let loc = MKMapItem(placemark: MKPlacemark(coordinate: coord))
            loc.name = "\(label). \(inc.priorityDot) \(inc.title)"

            let poi = CPPointOfInterest(
                location: loc,
                title: "\(label). \(inc.priorityDot) \(inc.title)",
                subtitle: "P\(inc.priorityLevel) · \(inc.agency)",
                summary: inc.location.isEmpty ? nil : inc.location,
                detailTitle: "\(inc.priorityDot) \(inc.title)",
                detailSubtitle: "P\(inc.priorityLevel) · \(inc.agency) · \(inc.age)",
                detailSummary: [inc.location.isEmpty ? nil : inc.location, inc.action, inc.details?.first]
                    .compactMap { $0 }.filter { !$0.isEmpty }.first,
                pinImage: pinImage(for: inc, label: label)
            )
            poi.userInfo = inc
            // Button on the forced selection card: dismiss the card and open the
            // full detail (status, radio traffic, etc.).
            poi.primaryButton = CPTextButton(title: "Details", textStyle: .normal) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let t = self.poiTemplate {
                        t.setPointsOfInterest(t.pointsOfInterest, selectedIndex: NSNotFound)
                    }
                    self.pushIncidentDetail(inc)
                }
            }
            return poi
        }
        mapPinIndex = idxMap
        poiTemplate?.setPointsOfInterest(pois, selectedIndex: NSNotFound)
    }

    /// Circle colored+sized by priority, labeled with the POI's list number so a
    /// pin can be matched to its row in the list.
    private func pinImage(for inc: Incident, label: String) -> UIImage? {
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
            let text = label as NSString
            let font = UIFont.systemFont(ofSize: size * (label.count > 1 ? 0.40 : 0.50), weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: stale ? gray : UIColor.white]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size - ts.width) / 2, y: (size - ts.height) / 2), withAttributes: attrs)
        }
    }

    // MARK: - Incidents list

    @MainActor
    private func updateList(incidents: [Incident]) {
        // Priority-first sort, matching the web incident board
        let byPriority: (Incident, Incident) -> Bool = {
            let p0 = $0.priorityLevel, p1 = $1.priorityLevel
            if p0 != p1 { return p0 < p1 }
            let rank: (String) -> Int = { k in k == "active" ? 0 : k == "routine" ? 1 : 2 }
            return rank($0.statusKind) < rank($1.statusKind)
        }
        let active  = incidents.filter { $0.statusKind != "clear" }.sorted(by: byPriority)
        let cleared = incidents.filter { $0.statusKind == "clear" }.sorted(by: byPriority)

        let makeItems: ([Incident]) -> [CPListItem] = { [weak self] list in
            list.prefix(30).map { inc in
                let detail = [inc.agency,
                              inc.location.isEmpty ? nil : inc.location,
                              inc.age.isEmpty      ? nil : inc.age]
                    .compactMap { $0 }.joined(separator: " · ")
                let item = CPListItem(text: "P\(inc.priorityLevel) \(inc.statusEmoji) \(inc.title)", detailText: detail)
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
            CPInformationItem(title: "Status",   detail: "\(incident.priorityDot) \(incident.status)"),
            CPInformationItem(title: "Priority", detail: incident.priorityLabel),
            CPInformationItem(title: "Agency",   detail: incident.agency),
        ]
        // Tell the driver which numbered pin this is, since the POI map can't
        // zoom/center programmatically (Apple template limitation).
        if let pin = mapPinIndex[incident.number] {
            rows.append(CPInformationItem(title: "Map pin", detail: "#\(pin)"))
        }
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

        let tmpl = CPInformationTemplate(
            title: "#\(incident.number) \(incident.title)",
            layout: .twoColumn,
            items: rows,
            actions: []
        )
        interfaceController.pushTemplate(tmpl, animated: true) { _, _ in }

        // Append the incident's radio traffic once it loads (the "chat").
        if let from = incident.firstTxId, let to = incident.lastTxId, from > 0 {
            Task { @MainActor in
                guard let txs = try? await P25Client.shared.fetchTransmissions(limit: 100, fromId: from, toId: to),
                      !txs.isEmpty else { return }
                var updated = rows
                updated.append(CPInformationItem(title: "— Radio Traffic —", detail: nil))
                for tx in txs.prefix(12) {
                    let body = (tx.text ?? "").isEmpty ? (tx.talkgroup ?? "Unknown") : (tx.text ?? "")
                    updated.append(CPInformationItem(title: tx.time ?? "", detail: body))
                }
                tmpl.items = updated
            }
        }
    }

    // MARK: - Radio log

    // Agency/trunk filters matching the web feed tabs (default All/All)
    private var logAgencyFilter = "all"   // all | police | fire | ems
    private var logTrunkFilter  = "all"   // all | tippecanoe | safet

    private func _agencyMatch(_ tx: TXEvent) -> Bool {
        guard logAgencyFilter != "all" else { return true }
        let a = "\(tx.agency ?? "") \(tx.talkgroup ?? "")".uppercased()
        switch logAgencyFilter {
        case "police": return a.range(of: "LPD|WLPD|TCSD|PUPD|ISP|SHERIFF|POLICE", options: .regularExpression) != nil
        case "fire":   return a.range(of: "LFD|WLFD|TCFD|PUFD|FIRE", options: .regularExpression) != nil
        case "ems":    return a.range(of: "EMS|TEAS", options: .regularExpression) != nil
        default:       return true
        }
    }

    @MainActor
    private func updateLog(txList: [TXEvent]) {
        let filtered = txList.filter {
            _agencyMatch($0) && (logTrunkFilter == "all" || $0.trunk == logTrunkFilter)
        }
        let items: [CPListItem] = filtered.prefix(50).map { tx in
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
        let header = (logAgencyFilter == "all" && logTrunkFilter == "all")
            ? nil : "Filter: \(logAgencyFilter != "all" ? logAgencyFilter.capitalized : "")\(logTrunkFilter != "all" ? " \(logTrunkFilter == "safet" ? "SAFE-T" : "Tippecanoe")" : "")"
        logTemplate?.updateSections([CPListSection(items: items.isEmpty ? [CPListItem(text: "No transmissions", detailText: nil)] : items,
                                                   header: header, sectionIndexTitle: nil)])
    }

    @MainActor
    private func pushLogFilterChooser() {
        let agency: [(String, String)] = [("all", "All agencies"), ("police", "Police"), ("fire", "Fire"), ("ems", "EMS")]
        let trunk:  [(String, String)] = [("all", "Both trunks"), ("tippecanoe", "Tippecanoe"), ("safet", "SAFE-T")]
        let makeItem: (String, String, Bool, @escaping (String) -> Void) -> CPListItem = { val, label, selected, apply in
            let item = CPListItem(text: "\(selected ? "✓ " : "")\(label)", detailText: nil)
            item.handler = { [weak self] _, completion in
                apply(val)
                Task { @MainActor in
                    self?.updateLog(txList: P25Store.shared.recentTX)
                    self?.interfaceController.popTemplate(animated: true) { _, _ in }
                    completion()
                }
            }
            return item
        }
        let agencyItems = agency.map { v, l in makeItem(v, l, logAgencyFilter == v) { [weak self] in self?.logAgencyFilter = $0 } }
        let trunkItems  = trunk.map  { v, l in makeItem(v, l, logTrunkFilter == v)  { [weak self] in self?.logTrunkFilter = $0 } }
        let tmpl = CPListTemplate(title: "Log Filter", sections: [
            CPListSection(items: agencyItems, header: "Agency", sectionIndexTitle: nil),
            CPListSection(items: trunkItems,  header: "Trunk",  sectionIndexTitle: nil),
        ])
        interfaceController.pushTemplate(tmpl, animated: true) { _, _ in }
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
        // Deliberately no push. Selecting a POI already shows the template's own
        // info card; pushing a second detail on top caused the double-popup (card
        // left underneath, needing an X). The card is the map's quick view; the
        // full detail + radio traffic lives in the Incidents tab.
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

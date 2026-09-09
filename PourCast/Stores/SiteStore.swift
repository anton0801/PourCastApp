import Foundation
import Combine

@MainActor
final class SiteStore: ObservableObject {
    static let maxSites = 3

    @Published private(set) var sites: [Site]
    @Published var selectedSiteID: UUID? {
        didSet { UserDefaults.standard.set(selectedSiteID?.uuidString, forKey: "pc.selectedSiteID") }
    }

    private let persistence: Persistence

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
        let loaded = persistence.load([Site].self, from: Persistence.sitesFile) ?? []
        sites = loaded
        let storedID = UserDefaults.standard.string(forKey: "pc.selectedSiteID").flatMap(UUID.init)
        selectedSiteID = loaded.first { $0.id == storedID }?.id ?? loaded.first?.id
    }

    var selected: Site? {
        sites.first { $0.id == selectedSiteID }
    }

    var canAdd: Bool { sites.count < Self.maxSites }

    func add(_ site: Site) {
        guard canAdd else { return }
        sites.append(site)
        if selectedSiteID == nil { selectedSiteID = site.id }
        persist()
    }

    func delete(_ site: Site) {
        sites.removeAll { $0.id == site.id }
        Persistence.shared.delete(Persistence.forecastFile(for: site.id))
        if selectedSiteID == site.id { selectedSiteID = sites.first?.id }
        persist()
    }

    func rename(_ site: Site, to name: String) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        sites[index].name = name
        persist()
    }

    private func persist() {
        persistence.save(sites, to: Persistence.sitesFile)
    }
}

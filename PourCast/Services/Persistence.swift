import Foundation

/// JSON file store in Application Support/PourCast. Every file is wrapped in a
/// Versioned container (v:1) so future schema changes can migrate on decode.
struct Persistence {
    static let shared = Persistence()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("PourCast", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func url(_ file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    func load<T: Codable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: url(file)),
              let container = try? decoder.decode(Versioned<T>.self, from: data)
        else { return nil }
        // v:1 is current; when v bumps, migrate here before returning.
        return container.payload
    }

    func save<T: Codable>(_ value: T, to file: String) {
        guard let data = try? encoder.encode(Versioned(payload: value)) else { return }
        try? data.write(to: url(file), options: .atomic)
    }

    func delete(_ file: String) {
        try? FileManager.default.removeItem(at: url(file))
    }

    // MARK: - Well-known files

    static func forecastFile(for siteID: UUID) -> String {
        "forecast-\(siteID.uuidString).json"
    }

    static let sitesFile = "sites.json"
    static let poursFile = "pours.json"

    /// Bundles every stored record into one shareable JSON file (Settings → export).
    func exportAll(sites: [Site], pours: [Pour], caches: [ForecastCache], defaults: PourDefaults) -> URL? {
        struct Export: Codable {
            let v: Int
            let exportedAt: Date
            let sites: [Site]
            let pours: [Pour]
            let forecasts: [ForecastCache]
            let defaults: PourDefaults
        }
        let export = Export(v: 1, exportedAt: Date(), sites: sites, pours: pours, forecasts: caches, defaults: defaults)
        guard let data = try? encoder.encode(export) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PourCast-export.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

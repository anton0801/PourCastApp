import Foundation
import Combine

/// Cache-first forecast state. Verdicts are ALWAYS computed from cache;
/// the network only ever replaces the cache.
@MainActor
final class ForecastStore: ObservableObject {
    /// Cache older than this triggers auto-refresh and the ochre badge.
    static let staleAfter: TimeInterval = 45 * 60
    /// Older than this adds the "verdicts based on old data" hero line.
    static let veryStaleAfter: TimeInterval = 12 * 3600

    @Published private(set) var caches: [UUID: ForecastCache] = [:]
    @Published private(set) var isRefreshing = false
    /// Last fetch failure — rendered over cache, cleared on success.
    @Published private(set) var lastError: WeatherFetchError?
    /// Derived verdicts for the selected site — recomputed only when
    /// cache / defaults / site change, never per frame.
    @Published private(set) var week: [DayVerdicts] = []

    private let persistence: Persistence

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
    }

    func loadCacheFromDisk(for site: Site) {
        guard caches[site.id] == nil,
              let cache = persistence.load(ForecastCache.self, from: Persistence.forecastFile(for: site.id))
        else { return }
        caches[site.id] = cache
    }

    func cache(for siteID: UUID?) -> ForecastCache? {
        siteID.flatMap { caches[$0] }
    }

    func age(for siteID: UUID?, now: Date = Date()) -> TimeInterval? {
        cache(for: siteID).map { now.timeIntervalSince($0.fetchedAt) }
    }

    func isStale(_ siteID: UUID?, now: Date = Date()) -> Bool {
        guard let age = age(for: siteID, now: now) else { return true }
        return age > Self.staleAfter
    }

    func isVeryStale(_ siteID: UUID?, now: Date = Date()) -> Bool {
        guard let age = age(for: siteID, now: now) else { return false }
        return age > Self.veryStaleAfter
    }

    /// Fetch via the caller-chosen provider and replace the cache. True on success.
    @discardableResult
    func refresh(site: Site, force: Bool, using provider: WeatherProviding) async -> Bool {
        if !force, !isStale(site.id) { return true }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let hours = try await provider.hourly(lat: site.lat, lon: site.lon)
            let cache = ForecastCache(siteID: site.id, fetchedAt: Date(), hours: hours)
            caches[site.id] = cache
            persistence.save(cache, to: Persistence.forecastFile(for: site.id))
            lastError = nil
            return true
        } catch let error as WeatherFetchError {
            lastError = error
            return false
        } catch {
            lastError = .serviceUnavailable
            return false
        }
    }

    func recomputeWeek(for site: Site?, defaults: PourDefaults, now: Date = Date(), calendar: Calendar = .current) {
        guard let site, let cache = caches[site.id] else {
            week = []
            return
        }
        week = WindowEngine.week(hours: cache.hours, defaults: defaults, now: now, calendar: calendar)
    }

    /// Best block of the next 7 days for a site — the Sites screen chip.
    func nextBestBlock(for site: Site, defaults: PourDefaults, now: Date = Date(), calendar: Calendar = .current) -> (day: Date, block: BestBlock)? {
        guard let cache = caches[site.id] else { return nil }
        let week = WindowEngine.week(hours: cache.hours, defaults: defaults, now: now, calendar: calendar)
        return week
            .compactMap { day in day.best.map { (day.day, $0) } }
            .max { $0.1.score < $1.1.score }
    }
}

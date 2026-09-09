import Foundation
import Combine
import UserNotifications

/// Root object: owns the stores and wires the one refresh pipeline —
/// forecast update → verdict recompute → cure re-evaluation → notification replan.
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let sites: SiteStore
    let pourStore: PourStore
    let forecast: ForecastStore
    let planner = NotificationPlanner()
    let location = LocationService()

    private let notificationDelegate = ForegroundNotificationDelegate()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        settings = SettingsStore()
        sites = SiteStore()
        pourStore = PourStore()
        forecast = ForecastStore()

        UNUserNotificationCenter.current().delegate = notificationDelegate

        for site in sites.sites {
            forecast.loadCacheFromDisk(for: site)
        }
        recompute()

        // S5 defaults edits recompute Home immediately.
        settings.$defaults
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] defaults in
                guard let self else { return }
                self.forecast.recomputeWeek(for: self.sites.selected, defaults: defaults)
                Task { await self.replan() }
            }
            .store(in: &cancellables)

        // Site change: recompute from that site's cache, refresh if stale.
        sites.$selectedSiteID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newID in
                guard let self else { return }
                let site = self.sites.sites.first { $0.id == newID }
                self.forecast.recomputeWeek(for: site, defaults: self.settings.defaults)
                Task { await self.refreshIfStale() }
            }
            .store(in: &cancellables)

        // Switching the weather source refetches through the new provider.
        settings.$weatherSource
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
    }

    /// The user-selected provider — OpenWeatherMap (built-in key) by default,
    /// WeatherKit opt-in.
    private var activeProvider: WeatherProviding {
        switch settings.weatherSource {
        case .openWeatherMap:
            return OpenWeatherMapProvider(apiKey: OWMConfig.builtInKey)
        case .weatherKit:
            return WeatherKitProvider()
        }
    }

    func recompute() {
        forecast.recomputeWeek(for: sites.selected, defaults: settings.defaults)
        pourStore.reevaluate(caches: forecast.caches)
    }

    /// Cold launch / foreground trigger: fetch only if the cache is stale.
    func refreshIfStale() async {
        guard let site = sites.selected else { return }
        guard forecast.isStale(site.id) else { return }
        await refresh()
    }

    /// Full refresh: selected site plus any site guarding an active pour.
    @discardableResult
    func refresh() async -> Bool {
        guard let site = sites.selected else { return false }
        let provider = activeProvider
        let ok = await forecast.refresh(site: site, force: true, using: provider)

        let guardedSiteIDs = Set(pourStore.active.map(\.siteID))
        for other in sites.sites
        where other.id != site.id && guardedSiteIDs.contains(other.id) {
            await forecast.refresh(site: other, force: false, using: provider)
        }

        recompute()
        await replan()
        return ok
    }

    /// Background fetch for a just-added, not-selected site (S4 chip).
    func refreshSite(_ site: Site) async {
        await forecast.refresh(site: site, force: false, using: activeProvider)
        recompute()
    }

    func replan() async {
        await planner.replan(
            week: forecast.week,
            pours: pourStore.pours,
            caches: forecast.caches,
            unit: settings.unit,
            windowTomorrowEnabled: settings.notifyWindowTomorrow,
            frostCureEnabled: settings.notifyFrostCure
        )
    }

    /// Log Pour commit: store, ask permission lazily, plan its risks.
    func logPour(_ pour: Pour) async {
        pourStore.log(pour)
        await planner.ensurePermission()
        recompute()
        await replan()
    }

    func deletePour(_ pour: Pour) async {
        pourStore.delete(pour)
        await planner.cancelRisks(for: pour.id)
    }
}

/// Cure-risk alerts mirror in-app when the app is frontmost.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

import Foundation
import Combine

@MainActor
final class PourStore: ObservableObject {
    @Published private(set) var pours: [Pour]

    private let persistence: Persistence

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
        pours = persistence.load([Pour].self, from: Persistence.poursFile) ?? []
    }

    var active: [Pour] {
        pours.filter { $0.status == .active || $0.status == .violated }
            .sorted { $0.start < $1.start }
    }

    var history: [Pour] {
        pours.filter { $0.status == .completed }
            .sorted { $0.start > $1.start }
    }

    func log(_ pour: Pour) {
        pours.append(pour)
        persist()
    }

    func delete(_ pour: Pour) {
        pours.removeAll { $0.id == pour.id }
        persist()
    }

    /// The CURED stamp fires exactly once — the view celebrates, then flips this.
    func markCelebrated(_ pour: Pour) {
        guard let index = pours.firstIndex(where: { $0.id == pour.id }) else { return }
        pours[index].curedCelebrated = true
        persist()
    }

    /// Re-evaluate every guarded pour against the refreshed forecast:
    /// append newly-passed violations, settle statuses at cure end.
    func reevaluate(caches: [UUID: ForecastCache], now: Date = Date()) {
        var changed = false

        for index in pours.indices {
            var pour = pours[index]
            guard pour.status != .completed else { continue }

            if let cache = caches[pour.siteID] {
                let occurred = WindowEngine.cureViolations(
                    start: pour.start,
                    protection: pour.protection,
                    hours: cache.hours
                ).filter { $0.hour <= now }

                for violation in occurred where !pour.violations.contains(where: { $0.id == violation.id }) {
                    pour.violations.append(violation)
                }
            }

            let settled: PourStatus
            if !pour.violations.isEmpty {
                settled = .violated
            } else if now >= pour.cureEnd {
                settled = .completed
            } else {
                settled = .active
            }

            if settled != pour.status || pour != pours[index] {
                pour.status = settled
                pours[index] = pour
                changed = true
            }
        }

        if changed { persist() }
    }

    /// Forecast risks still ahead of a pour — pinned on the ProgressRail.
    func upcomingRisks(for pour: Pour, caches: [UUID: ForecastCache], now: Date = Date()) -> [Violation] {
        guard let cache = caches[pour.siteID] else { return [] }
        return WindowEngine.cureViolations(
            start: pour.start,
            protection: pour.protection,
            hours: cache.hours,
            from: now
        ).filter { $0.hour > now }
    }

    private func persist() {
        persistence.save(pours, to: Persistence.poursFile)
    }
}

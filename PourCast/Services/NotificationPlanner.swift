import Foundation
import UserNotifications

/// Local notifications, re-planned deterministically on every forecast refresh.
/// Ids are derived from their condition, so the same risk never duplicates and
/// a risk that leaves the forecast gets its pending request cancelled.
@MainActor
final class NotificationPlanner {
    static let windowTomorrowID = "window-tomorrow"
    static let cureRiskPrefix = "cure-risk-"

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey = "pc.notifiedCureRiskIDs"

    /// Ids that already fired — a fired request is no longer pending, and must
    /// not be re-added on the next replan.
    private var notifiedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: notifiedKey) }
    }

    private(set) var permissionGranted = false

    /// Lazy permission ask — first Log Pour / Plan pour action, never at launch.
    @discardableResult
    func ensurePermission() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            permissionGranted = true
        case .notDetermined:
            permissionGranted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            permissionGranted = false
        }
        return permissionGranted
    }

    func replan(
        week: [DayVerdicts],
        pours: [Pour],
        caches: [UUID: ForecastCache],
        unit: TemperatureUnit,
        windowTomorrowEnabled: Bool,
        frostCureEnabled: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await replanWindowTomorrow(week: week, enabled: windowTomorrowEnabled, now: now, calendar: calendar)
        await replanCureRisks(pours: pours, caches: caches, unit: unit, enabled: frostCureEnabled, now: now, calendar: calendar)
    }

    // MARK: - Window opens tomorrow (18:00 local, GO run ≥ 4h)

    private func replanWindowTomorrow(week: [DayVerdicts], enabled: Bool, now: Date, calendar: Calendar) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.windowTomorrowID])

        guard enabled, week.count > 1,
              let goRun = longestGoRun(in: week[1].candidates, calendar: calendar),
              goRun.count >= WindowEngine.pourWindowHours,
              let first = goRun.first, let last = goRun.last,
              let runEnd = calendar.date(byAdding: .hour, value: 1, to: last.start)
        else { return }

        // Fire at 18:00 today; if it's already past, there's nothing to plan.
        guard let fireDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
              fireDate > now else { return }

        let best = goRun.map(\.score).max() ?? 0
        let content = UNMutableNotificationContent()
        content.title = "Pour window opens tomorrow"
        content.body = "\(PCFormat.hourRange(first.start, runEnd, calendar: calendar)) scores \(best). Book the truck."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: Self.windowTomorrowID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    private func longestGoRun(in candidates: [WindowScore], calendar: Calendar) -> [WindowScore]? {
        var runs: [[WindowScore]] = []
        var current: [WindowScore] = []
        for candidate in candidates {
            guard candidate.verdict == .go else {
                if !current.isEmpty { runs.append(current); current = [] }
                continue
            }
            if let last = current.last,
               calendar.date(byAdding: .hour, value: 1, to: last.start) != candidate.start {
                runs.append(current)
                current = []
            }
            current.append(candidate)
        }
        if !current.isEmpty { runs.append(current) }
        return runs.max { $0.count < $1.count }
    }

    // MARK: - Frost/rain entered the cure window

    private func replanCureRisks(
        pours: [Pour],
        caches: [UUID: ForecastCache],
        unit: TemperatureUnit,
        enabled: Bool,
        now: Date,
        calendar: Calendar
    ) async {
        let pendingCure = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.cureRiskPrefix) }

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: pendingCure)
            notifiedIDs = []
            return
        }

        struct Desired {
            let id: String
            let pour: Pour
            let violation: Violation
        }

        var desired: [Desired] = []
        for pour in pours where pour.status == .active || pour.status == .violated {
            guard pour.cureEnd > now, let cache = caches[pour.siteID] else { continue }
            let risks = WindowEngine.cureViolations(
                start: pour.start,
                protection: pour.protection,
                hours: cache.hours,
                from: now
            )
            for risk in risks where risk.hour > now {
                desired.append(Desired(id: Self.cureRiskPrefix + "\(pour.id.uuidString)-\(iso(risk.hour))", pour: pour, violation: risk))
            }
        }

        let desiredIDs = Set(desired.map(\.id))

        // Cancel risks that left the forecast; forget fired ones that are gone.
        let stale = pendingCure.filter { !desiredIDs.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        notifiedIDs = notifiedIDs.intersection(desiredIDs)

        // Add what's new — fires shortly after detection ("immediate on refresh").
        let known = Set(pendingCure).union(notifiedIDs)
        for item in desired where !known.contains(item.id) {
            let content = UNMutableNotificationContent()
            let when = PCFormat.weekdayHour(item.violation.hour, calendar: calendar)
            let element = item.pour.element.label.lowercased()
            switch item.violation.kind {
            case .frost:
                content.title = "Frost forecast \(when)"
                content.body = "\(PCFormat.temperature(item.violation.tempC, unit: unit)) at \(item.violation.cureHour)h into your cure. Cover the \(element) tonight."
            case .rain:
                content.title = "Rain forecast \(when)"
                content.body = "\(item.violation.cureHour)h after your pour. Protect the \(element) surface."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
            try? await center.add(request)
            notifiedIDs.insert(item.id)
        }
    }

    /// "Plan pour" reminder: crew call one hour before the planned start.
    @discardableResult
    func schedulePourReminder(at start: Date, calendar: Calendar) async -> Bool {
        guard await ensurePermission() else { return false }
        let fireDate = start.addingTimeInterval(-3600)
        guard fireDate > Date() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Pour planned \(PCFormat.hour(start, calendar: calendar))"
        content.body = "Crew call — this window scored GO when you planned it. Recheck the verdict before the truck rolls."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: "pour-reminder-\(iso(start))",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
        return true
    }

    /// Cancel everything for a pour that was deleted or completed.
    func cancelRisks(for pourID: UUID) async {
        let prefix = Self.cureRiskPrefix + pourID.uuidString
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        notifiedIDs = notifiedIDs.filter { !$0.hasPrefix(prefix) }
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

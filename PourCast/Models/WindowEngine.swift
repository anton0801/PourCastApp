import Foundation

// The signature feature: pure scoring of candidate pour-start hours and cure
// monitoring. Foundation-only, Calendar injected — verified by a standalone
// swiftc harness against the spec's acceptance numbers before any UI use.
//
// Window semantics: pour [H, H+4h), rain check [H, H+6h), cure [H, H+48h).
// Windows are physical durations (concrete cures in real hours); day/candidate
// enumeration goes through Calendar so DST days yield 23/25 candidates.

enum WindowEngine {
    static let pourWindowHours = 4
    static let rainWindowHours = 6
    static let cureWindowHours = 48
    /// Frost inside cure hours 36–48 weighs half — early frost is the killer.
    static let lateFrostFromHour = 36

    // MARK: - Mix rules

    /// Winter mix requires protection; unprotected it scores as standard.
    static func effectiveMix(_ mix: MixType, protection: ProtectionType) -> MixType {
        (mix == .winter && protection == ProtectionType.none) ? .standard : mix
    }

    /// Allowed air temperature at pour, °C.
    static func mixRange(mix: MixType, protection: ProtectionType) -> ClosedRange<Double> {
        switch effectiveMix(mix, protection: protection) {
        case .standard: return 5...32
        case .rapidSet: return 2...32
        case .winter: return -5...25
        }
    }

    /// Below this cure temperature, frost damage applies.
    static func frostThreshold(protection: ProtectionType) -> Double {
        protection == .blankets ? -2 : 0
    }

    // MARK: - Scoring

    static func score(
        startingAt start: Date,
        hours: [HourF],
        element: ElementType,
        mix: MixType,
        protection: ProtectionType
    ) -> WindowScore {
        let pourEnd = start.addingTimeInterval(Double(pourWindowHours) * 3600)
        let rainEnd = start.addingTimeInterval(Double(rainWindowHours) * 3600)
        let cureEnd = start.addingTimeInterval(Double(cureWindowHours) * 3600)

        let pourHours = hours.filter { $0.date >= start && $0.date < pourEnd }
        let rainHours = hours.filter { $0.date >= start && $0.date < rainEnd }
        let cureHours = hours.filter { $0.date >= start && $0.date < cureEnd }

        var penalties: [Penalty] = []
        var hardFail = false

        // Temp at pour: outside mix range → hard fail.
        let range = mixRange(mix: mix, protection: protection)
        if let bad = pourHours.first(where: { !range.contains($0.tempC) }) {
            hardFail = true
            penalties.append(Penalty(
                kind: .tempHardFail, hour: bad.date, points: 100,
                tempC: bad.tempC, rangeC: range
            ))
        }

        // Rain after pour: prob ≥30% AND ≥0.5mm inside [H, H+6h) — once.
        if let wet = rainHours.first(where: { $0.precipProb >= 30 && $0.precipMM >= 0.5 }) {
            penalties.append(Penalty(
                kind: .rain, hour: wet.date,
                points: element == .slab ? 40 : 25
            ))
        }

        // Frost in cure: earliest frost hour decides the weight.
        let threshold = frostThreshold(protection: protection)
        if let frost = cureHours.first(where: { $0.tempC < threshold }) {
            let cureHour = Int(frost.date.timeIntervalSince(start) / 3600)
            let base = protection == .blankets ? 30 : 60
            penalties.append(Penalty(
                kind: .frost, hour: frost.date,
                points: cureHour >= lateFrostFromHour ? base / 2 : base,
                tempC: frost.tempC
            ))
        }

        // Hot & windy (slabs only): plastic shrinkage cracking risk — once.
        if element == .slab,
           let hot = pourHours.first(where: { $0.tempC > 30 && ($0.windKMH > 25 || $0.humidity < 40) }) {
            penalties.append(Penalty(
                kind: .hotWindy, hour: hot.date, points: 25, tempC: hot.tempC
            ))
        }

        // Marginal cold: any cure hour 0…5°C — slow strength gain, once.
        if let chilly = cureHours.first(where: { $0.tempC >= 0 && $0.tempC <= 5 }) {
            penalties.append(Penalty(
                kind: .marginalCold, hour: chilly.date, points: 10, tempC: chilly.tempC
            ))
        }

        var score = hardFail ? 0 : max(0, 100 - penalties.reduce(0) { $0 + $1.points })

        // Forecast horizon: cure extending past available forecast caps at 79.
        let coveredUntil = hours.last.map { $0.date.addingTimeInterval(3600) } ?? start
        if cureEnd > coveredUntil {
            score = min(score, 79)
            penalties.append(Penalty(kind: .horizon, hour: nil, points: 0))
        }

        let verdict: VerdictClass
        if hardFail || score < 50 {
            verdict = .noGo
        } else if score >= 80 {
            verdict = .go
        } else {
            verdict = .caution
        }

        return WindowScore(
            start: start, score: score, verdict: verdict,
            penalties: penalties, hardFail: hardFail
        )
    }

    // MARK: - Candidate enumeration (DST-safe: hour-by-hour through Calendar)

    static func dayCandidates(
        day: Date,
        hours: [HourF],
        defaults: PourDefaults,
        from: Date,
        calendar: Calendar
    ) -> [WindowScore] {
        guard let firstForecast = hours.first?.date,
              let lastForecast = hours.last?.date else { return [] }

        let dayStart = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var result: [WindowScore] = []
        var cursor = dayStart
        while cursor < nextDay {
            defer { cursor = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? nextDay }
            let hourOfDay = calendar.component(.hour, from: cursor)
            guard hourOfDay >= defaults.workday.start, hourOfDay < defaults.workday.end else { continue }
            guard cursor >= from else { continue }
            guard cursor >= firstForecast, cursor <= lastForecast else { continue }
            result.append(score(
                startingAt: cursor, hours: hours,
                element: defaults.element, mix: defaults.mix, protection: defaults.protection
            ))
        }
        return result
    }

    /// 7 days from today. `from` filters out candidate hours already in the past.
    static func week(
        hours: [HourF],
        defaults: PourDefaults,
        now: Date,
        calendar: Calendar
    ) -> [DayVerdicts] {
        var fromComponents = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        fromComponents.minute = 0
        fromComponents.second = 0
        let from = calendar.date(from: fromComponents) ?? now

        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let candidates = dayCandidates(
                day: day, hours: hours, defaults: defaults, from: from, calendar: calendar
            )
            return DayVerdicts(
                day: day, candidates: candidates,
                best: bestBlock(in: candidates, calendar: calendar)
            )
        }
    }

    // MARK: - Best block: highest-scoring contiguous GO/CAUTION run ≥ 4h

    static func bestBlock(in candidates: [WindowScore], calendar: Calendar) -> BestBlock? {
        var runs: [[WindowScore]] = []
        var current: [WindowScore] = []

        for candidate in candidates {
            guard candidate.verdict != .noGo else {
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

        let qualifying = runs.filter { $0.count >= pourWindowHours }
        guard let best = qualifying.max(by: { lhs, rhs in
            let l = lhs.map(\.score).max() ?? 0
            let r = rhs.map(\.score).max() ?? 0
            return l == r ? lhs.count < rhs.count : l < r
        }) else { return nil }

        guard let first = best.first, let last = best.last,
              let end = calendar.date(byAdding: .hour, value: 1, to: last.start) else { return nil }
        return BestBlock(
            start: first.start, end: end,
            score: best.map(\.score).max() ?? 0
        )
    }

    // MARK: - Cure Watch

    /// Violations inside the (remaining) cure window. Consecutive offending
    /// hours collapse into one event at the start of the snap, so identities
    /// stay stable across refreshes and one cold night is one notification.
    static func cureViolations(
        start: Date,
        protection: ProtectionType,
        hours: [HourF],
        from lowerBound: Date? = nil
    ) -> [Violation] {
        let cureEnd = start.addingTimeInterval(Double(cureWindowHours) * 3600)
        let rainEnd = start.addingTimeInterval(Double(rainWindowHours) * 3600)
        let lower = lowerBound ?? start
        let threshold = frostThreshold(protection: protection)

        var result: [Violation] = []
        var inFrostSnap = false
        var inRainSnap = false

        for hour in hours where hour.date >= start && hour.date < cureEnd {
            let isFrost = hour.tempC < threshold
            let isRain = hour.date < rainEnd && hour.precipProb >= 30 && hour.precipMM >= 0.5

            if isFrost, !inFrostSnap, hour.date >= lower {
                result.append(Violation(
                    kind: .frost, hour: hour.date,
                    cureHour: Int(hour.date.timeIntervalSince(start) / 3600),
                    tempC: hour.tempC
                ))
            }
            if isRain, !inRainSnap, hour.date >= lower {
                result.append(Violation(
                    kind: .rain, hour: hour.date,
                    cureHour: Int(hour.date.timeIntervalSince(start) / 3600),
                    tempC: hour.tempC
                ))
            }
            inFrostSnap = isFrost
            inRainSnap = isRain
        }
        return result
    }
}

import Foundation

// Foundation-only: this file (with WindowEngine.swift) must compile under bare
// swiftc for the engine verification harness. No SwiftUI imports here.

// MARK: - Settings enums

enum WeatherSource: String, Codable, CaseIterable, Identifiable {
    case openWeatherMap, weatherKit

    var id: String { rawValue }
    var label: String {
        switch self {
        case .openWeatherMap: return "OpenWeatherMap"
        case .weatherKit: return "Apple Weather"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

enum ElementType: String, Codable, CaseIterable, Identifiable {
    case slab, footing, wallColumn

    var id: String { rawValue }
    var label: String {
        switch self {
        case .slab: return "Slab"
        case .footing: return "Footing"
        case .wallColumn: return "Wall / column"
        }
    }
    var symbol: String {
        switch self {
        case .slab: return "square.split.bottomrightquarter"
        case .footing: return "square.stack.3d.down.forward"
        case .wallColumn: return "rectangle.portrait"
        }
    }
}

enum MixType: String, Codable, CaseIterable, Identifiable {
    case standard, rapidSet, winter

    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .rapidSet: return "Rapid-set"
        case .winter: return "Winter mix"
        }
    }
}

enum ProtectionType: String, Codable, CaseIterable, Identifiable {
    case none, covering, blankets

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .covering: return "Covering"
        case .blankets: return "Insulated blankets"
        }
    }
    var shortLabel: String {
        switch self {
        case .none: return "None"
        case .covering: return "Covering"
        case .blankets: return "Blankets"
        }
    }
}

struct WorkdayHours: Codable, Equatable {
    var start: Int
    var end: Int

    static let `default` = WorkdayHours(start: 7, end: 17)
}

struct PourDefaults: Codable, Equatable {
    var element: ElementType
    var mix: MixType
    var protection: ProtectionType
    var workday: WorkdayHours

    static let initial = PourDefaults(
        element: .slab, mix: .standard, protection: .none, workday: .default
    )
}

// MARK: - Domain records

struct Site: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var lat: Double
    var lon: Double
}

struct HourF: Codable, Equatable {
    let date: Date
    let tempC: Double
    /// Precipitation probability, 0–100.
    let precipProb: Double
    /// Precipitation amount for the hour, millimeters.
    let precipMM: Double
    let windKMH: Double
    /// Relative humidity, 0–100.
    let humidity: Double
}

struct ForecastCache: Codable, Equatable {
    let siteID: UUID
    let fetchedAt: Date
    let hours: [HourF]
}

enum PourStatus: String, Codable {
    case active, completed, violated
}

struct Violation: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case frost, rain
    }

    let kind: Kind
    /// The forecast hour when the violation occurs.
    let hour: Date
    /// Whole hours into the cure at that moment (e.g. 31).
    let cureHour: Int
    let tempC: Double

    /// Stable across re-evaluations: same risk → same id → no duplicates.
    var id: String { "\(kind.rawValue)-\(Int(hour.timeIntervalSince1970))" }
}

struct Pour: Codable, Identifiable, Equatable {
    let id: UUID
    var siteID: UUID
    var start: Date
    var element: ElementType
    var mix: MixType
    var protection: ProtectionType
    var status: PourStatus
    var violations: [Violation]
    var curedCelebrated: Bool

    init(
        id: UUID = UUID(), siteID: UUID, start: Date, element: ElementType,
        mix: MixType, protection: ProtectionType, status: PourStatus = .active,
        violations: [Violation] = [], curedCelebrated: Bool = false
    ) {
        self.id = id
        self.siteID = siteID
        self.start = start
        self.element = element
        self.mix = mix
        self.protection = protection
        self.status = status
        self.violations = violations
        self.curedCelebrated = curedCelebrated
    }

    var cureEnd: Date { start.addingTimeInterval(Double(WindowEngine.cureWindowHours) * 3600) }
}

/// Versioned persistence container — v stays 1 until a migration is needed.
struct Versioned<T: Codable>: Codable {
    var v: Int
    var payload: T

    init(payload: T) {
        self.v = 1
        self.payload = payload
    }
}

// MARK: - Engine output

enum VerdictClass: String, Codable {
    case go, caution, noGo

    var word: String {
        switch self {
        case .go: return "GO"
        case .caution: return "CAUTION"
        case .noGo: return "NO-GO"
        }
    }
}

struct Penalty: Equatable, Identifiable {
    enum Kind: String {
        case tempHardFail, rain, frost, hotWindy, marginalCold, horizon
    }

    let kind: Kind
    /// The offending forecast hour (nil for horizon notes).
    let hour: Date?
    /// Points subtracted (positive). 0 for pure notes (horizon).
    let points: Int
    /// Measured temp at the offending hour, when relevant. °C — display converts.
    let tempC: Double?
    /// Allowed mix range, for hard-fail explanations. °C — display converts.
    let rangeC: ClosedRange<Double>?

    init(kind: Kind, hour: Date?, points: Int, tempC: Double? = nil, rangeC: ClosedRange<Double>? = nil) {
        self.kind = kind
        self.hour = hour
        self.points = points
        self.tempC = tempC
        self.rangeC = rangeC
    }

    var id: String { "\(kind.rawValue)-\(hour.map { String(Int($0.timeIntervalSince1970)) } ?? "x")" }

    var symbol: String {
        switch kind {
        case .tempHardFail: return "thermometer.snowflake"
        case .rain: return "cloud.rain"
        case .frost: return "snowflake"
        case .hotWindy: return "wind"
        case .marginalCold: return "thermometer.low"
        case .horizon: return "clock.arrow.circlepath"
        }
    }
}

struct WindowScore: Equatable, Identifiable {
    /// Candidate pour-start hour.
    let start: Date
    /// 0…100 after penalties and horizon cap.
    let score: Int
    let verdict: VerdictClass
    let penalties: [Penalty]
    let hardFail: Bool

    var id: Date { start }
}

struct BestBlock: Equatable {
    /// First candidate start hour of the block.
    let start: Date
    /// End of the last candidate hour (exclusive), i.e. last start + 1h.
    let end: Date
    /// Best score inside the block — the number shown on the DayRow chip.
    let score: Int
}

struct DayVerdicts: Identifiable, Equatable {
    /// Start of day.
    let day: Date
    let candidates: [WindowScore]
    let best: BestBlock?

    var id: Date { day }
}

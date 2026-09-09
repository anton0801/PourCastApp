import Foundation

// MARK: - Display-layer formatting (all math stays °C; °F conversion happens only here)

enum PCFormat {
    static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return "\(Int(celsius.rounded()))°C"
        case .fahrenheit:
            return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
    }

    static func temperatureShort(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return "\(Int(celsius.rounded()))°"
        case .fahrenheit:
            return "\(Int((celsius * 9 / 5 + 32).rounded()))°"
        }
    }

    static func wind(_ kmh: Double) -> String {
        "\(Int(kmh.rounded())) km/h"
    }

    static func precip(_ mm: Double) -> String {
        mm < 0.05 ? "0 mm" : String(format: "%.1f mm", mm)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "08:00" for a date's hour in the given calendar.
    static func hour(_ date: Date, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        return String(format: "%02d:00", h)
    }

    /// "08:00–12:00"
    static func hourRange(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        "\(hour(start, calendar: calendar))–\(hour(end, calendar: calendar))"
    }

    /// "Thu 03:00" — used in violation copy.
    static func weekdayHour(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return "\(formatter.string(from: date)) \(hour(date, calendar: calendar))"
    }

    /// Relative age for the AgeBadge: "just now", "12m ago", "3h ago", "2d ago".
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<90: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }

    /// "Mon 21" day label for DayRows.
    static func dayLabel(_ date: Date, calendar: Calendar = .current) -> (weekday: String, day: String) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let weekday = formatter.string(from: date)
        let day = "\(calendar.component(.day, from: date))"
        return (weekday, day)
    }
}

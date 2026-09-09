import SwiftUI
import Combine

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Published + UserDefaults-backed settings. @Published (not @AppStorage) so
/// changes flow through Combine into the recompute pipeline in AppModel.
@MainActor
final class SettingsStore: ObservableObject {
    private let store = UserDefaults.standard

    @Published var unit: TemperatureUnit {
        didSet { store.set(unit.rawValue, forKey: "pc.unit") }
    }
    @Published var theme: AppTheme {
        didSet { store.set(theme.rawValue, forKey: "pc.theme") }
    }
    @Published var notifyWindowTomorrow: Bool {
        didSet { store.set(notifyWindowTomorrow, forKey: "pc.notifyWindowTomorrow") }
    }
    @Published var notifyFrostCure: Bool {
        didSet { store.set(notifyFrostCure, forKey: "pc.notifyFrostCure") }
    }
    @Published var onboardingDone: Bool {
        didSet { store.set(onboardingDone, forKey: "hasCompletedOnboarding") }
    }
    @Published var weatherSource: WeatherSource {
        didSet { store.set(weatherSource.rawValue, forKey: "pc.weatherSource") }
    }
    @Published var defaults: PourDefaults {
        didSet {
            if let data = try? JSONEncoder().encode(defaults) {
                store.set(data, forKey: "pc.defaults")
            }
        }
    }

    init() {
        unit = TemperatureUnit(rawValue: store.string(forKey: "pc.unit") ?? "") ?? .celsius
        theme = AppTheme(rawValue: store.string(forKey: "pc.theme") ?? "") ?? .system
        notifyWindowTomorrow = store.object(forKey: "pc.notifyWindowTomorrow") as? Bool ?? true
        notifyFrostCure = store.object(forKey: "pc.notifyFrostCure") as? Bool ?? true
        // Legacy key fallback so pre-1.1 installs don't see onboarding again.
        onboardingDone = store.bool(forKey: "hasCompletedOnboarding") || store.bool(forKey: "pc.onboardingDone")
        weatherSource = WeatherSource(rawValue: store.string(forKey: "pc.weatherSource") ?? "") ?? .openWeatherMap
        if let data = store.data(forKey: "pc.defaults"),
           let decoded = try? JSONDecoder().decode(PourDefaults.self, from: data) {
            defaults = decoded
        } else {
            defaults = .initial
        }
    }
}

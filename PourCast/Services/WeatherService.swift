import Foundation
import WeatherKit
import CoreLocation

enum WeatherFetchError: Error, Equatable {
    /// No network — the cached forecast is all we have.
    case offline
    /// The active provider is unreachable or refused the request.
    case serviceUnavailable
    /// OpenWeatherMap selected but no API key configured yet.
    case missingKey
    /// OpenWeatherMap rejected the configured key (401).
    case invalidKey

    /// Key problems are fixed in Settings, not by retrying.
    var isKeyProblem: Bool {
        self == .missingKey || self == .invalidKey
    }
}

protocol WeatherProviding {
    func hourly(lat: Double, lon: Double) async throws -> [HourF]
}

/// The only shipped provider — WeatherKit, per pipeline network rules.
/// On failure the app degrades to the designed cache/error states; no fake data.
struct WeatherKitProvider: WeatherProviding {
    func hourly(lat: Double, lon: Double) async throws -> [HourF] {
        do {
            let forecast = try await WeatherService.shared.weather(
                for: CLLocation(latitude: lat, longitude: lon),
                including: .hourly
            )
            return forecast.forecast.map { hour in
                HourF(
                    date: hour.date,
                    tempC: hour.temperature.converted(to: .celsius).value,
                    precipProb: hour.precipitationChance * 100,
                    precipMM: hour.precipitationAmount.converted(to: .millimeters).value,
                    windKMH: hour.wind.speed.converted(to: .kilometersPerHour).value,
                    humidity: hour.humidity * 100
                )
            }
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: ns.code) {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                     .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                    throw WeatherFetchError.offline
                default:
                    throw WeatherFetchError.serviceUnavailable
                }
            }
            throw WeatherFetchError.serviceUnavailable
        }
    }
}

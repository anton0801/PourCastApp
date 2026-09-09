import Foundation

/// THE key slot — paste your own OpenWeatherMap key here before shipping.
/// Users never see or manage keys; this free-tier key ships in the binary
/// (pipeline rule: acceptable, extractable, never a paid secret). While it's
/// empty the app shows the designed "not configured" state — never a crash.
enum OWMConfig {
    static let builtInKey = "2255aeb9e4f7e3edc0195b0627ba2ff6"
}

/// The default provider: OpenWeatherMap "5 day / 3 hour" forecast over plain
/// HTTPS + Codable (free tier, API key required). 3-hour steps are expanded
/// to the hourly grid the engine expects, interpolating temperature between
/// samples. Horizon is ~5 days — the engine's horizon cap and the DayRow
/// "No data" chip handle the shorter reach honestly.
struct OpenWeatherMapProvider: WeatherProviding {
    let apiKey: String

    func hourly(lat: Double, lon: Double) async throws -> [HourF] {
        guard !apiKey.isEmpty else { throw WeatherFetchError.missingKey }

        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/forecast")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: apiKey),
        ]
        guard let url = components.url else { throw WeatherFetchError.serviceUnavailable }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 { throw WeatherFetchError.invalidKey }
                guard (200..<300).contains(http.statusCode) else {
                    throw WeatherFetchError.serviceUnavailable
                }
            }
            let payload = try JSONDecoder().decode(ForecastResponse.self, from: data)
            return Self.hourlyGrid(from: payload.list)
        } catch let error as WeatherFetchError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                throw WeatherFetchError.offline
            default:
                throw WeatherFetchError.serviceUnavailable
            }
        } catch {
            throw WeatherFetchError.serviceUnavailable
        }
    }

    // MARK: - Response shape (documented fields only)

    struct ForecastResponse: Decodable {
        let list: [Entry]
    }

    struct Entry: Decodable {
        let dt: TimeInterval
        let main: Main
        let wind: Wind?
        let pop: Double?
        let rain: Volume?
        let snow: Volume?

        struct Main: Decodable {
            let temp: Double
            let humidity: Double
        }

        struct Wind: Decodable {
            let speed: Double
        }

        struct Volume: Decodable {
            let threeHours: Double?

            enum CodingKeys: String, CodingKey {
                case threeHours = "3h"
            }
        }
    }

    // MARK: - 3-hour steps → hourly grid

    static func hourlyGrid(from entries: [Entry]) -> [HourF] {
        let sorted = entries.sorted { $0.dt < $1.dt }
        var hours: [HourF] = []

        for (index, entry) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1] : nil
            let liquid = (entry.rain?.threeHours ?? 0) + (entry.snow?.threeHours ?? 0)
            let perHourMM = liquid / 3
            let probability = (entry.pop ?? 0) * 100
            let windKMH = (entry.wind?.speed ?? 0) * 3.6

            for step in 0..<3 {
                let fraction = Double(step) / 3
                let temp: Double
                if let next {
                    temp = entry.main.temp + (next.main.temp - entry.main.temp) * fraction
                } else {
                    temp = entry.main.temp
                }
                hours.append(HourF(
                    date: Date(timeIntervalSince1970: entry.dt + Double(step) * 3600),
                    tempC: temp,
                    precipProb: probability,
                    precipMM: perHourMM,
                    windKMH: windKMH,
                    humidity: entry.main.humidity
                ))
            }
        }
        return hours
    }
}

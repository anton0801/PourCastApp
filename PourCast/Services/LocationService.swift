import Foundation
import CoreLocation

struct GeocodedPlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let lat: Double
    let lon: Double
}

/// WhenInUse one-shot location + city search. Location is never a gate:
/// every caller has a manual (search) path when this is denied.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    enum LocationError: Error {
        case denied, unavailable
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// One-shot fix; requests permission if not determined.
    func currentLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // The delegate callback resumes the request once the user decides.
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    /// Names a coordinate for a site created from the current location.
    func placeName(for location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let mark = placemarks?.first
        return mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea ?? "My site"
    }

    /// City search for the manual path.
    func search(city query: String) async -> [GeocodedPlace] {
        guard let placemarks = try? await CLGeocoder().geocodeAddressString(query) else { return [] }
        return placemarks.compactMap { mark in
            guard let location = mark.location else { return nil }
            let name = [mark.locality ?? mark.name, mark.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            return GeocodedPlace(
                name: name.isEmpty ? query : name,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude
            )
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            guard self.locationContinuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.locationContinuation?.resume(throwing: LocationError.denied)
                self.locationContinuation = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.first else { return }
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: LocationError.unavailable)
            self.locationContinuation = nil
        }
    }
}

import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationAccessStore: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onDisabled: (() -> Void)?

    private let manager = CLLocationManager()
    private let preferenceKey = "docklet.permission.location"
    private var enableRequested = false

    override init() {
        super.init()
        manager.delegate = self
        if UserDefaults.standard.bool(forKey: preferenceKey) {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                enableLocation()
            case .notDetermined:
                enableRequested = true
                manager.requestWhenInUseAuthorization()
            default:
                UserDefaults.standard.set(false, forKey: preferenceKey)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || enableRequested else { return }
        message = nil
        if !enabled {
            enableRequested = false
            isEnabled = false
            UserDefaults.standard.set(false, forKey: preferenceKey)
            onDisabled?()
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            enableLocation()
        case .notDetermined:
            enableRequested = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            message = "Allow location access for Docklet in System Settings → Privacy & Security → Location Services."
        @unknown default:
            message = "Location access is unavailable on this Mac."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard enableRequested else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            enableLocation()
        case .denied, .restricted:
            enableRequested = false
            isEnabled = false
            UserDefaults.standard.set(false, forKey: preferenceKey)
            message = "Location access was not allowed. You can still search for a city in the weather tile."
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isEnabled, let coordinate = locations.last?.coordinate else { return }
        onLocation?(coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "Could not read your location. You can still search for a city in the weather tile."
    }

    private func enableLocation() {
        enableRequested = false
        isEnabled = true
        UserDefaults.standard.set(true, forKey: preferenceKey)
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
    }
}

extension LocationAccessStore: @preconcurrency CLLocationManagerDelegate {}

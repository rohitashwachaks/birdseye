import Foundation
import CoreLocation

/// Thin CoreLocation wrapper: publishes the latest fix and compass heading.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var lastFix: CLLocation?
    @Published private(set) var compassDeg: Double?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        #if os(iOS)
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        #endif
    }

    func stop() {
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }

    var fixIsFresh: Bool {
        guard let fix = lastFix else { return false }
        return Date().timeIntervalSince(fix.timestamp) < 120 && fix.horizontalAccuracy >= 0
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last { lastFix = loc }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last fix; the engine falls back to dead reckoning.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    #if os(iOS)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        compassDeg = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    #endif
}

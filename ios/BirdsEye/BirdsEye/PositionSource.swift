import Foundation
import CoreLocation

/// The one mode-specific seam in the app: where `Observer` values come from.
/// Drive mode uses `GPSPositionSource`; a future flight mode plugs in a dead-reckoning
/// source without touching anything downstream.
protocol PositionSource: AnyObject {
    var onUpdate: ((Observer) -> Void)? { get set }
    func start()
    func stop()
}

/// Live GPS. Heading comes from GPS course while moving and the compass when stopped —
/// course is meaningless at a standstill.
final class GPSPositionSource: NSObject, PositionSource, CLLocationManagerDelegate {
    var onUpdate: ((Observer) -> Void)?
    /// Surfaced so the UI can explain itself when permission is missing.
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private let eyeHeightM: Double
    private var lastHeadingDeg: Double = 0
    private var compassDeg: Double?

    /// Speed below which GPS course is unreliable and the compass takes over (km/h).
    private let compassTakeoverKmh: Double = 4

    init(eyeHeightM: Double) {
        self.eyeHeightM = eyeHeightM
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        #if os(iOS)
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        #endif
    }

    func stop() {
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        let speedKmh = max(fix.speed, 0) * 3.6

        if fix.course >= 0, speedKmh > compassTakeoverKmh {
            lastHeadingDeg = fix.course
        } else if let compassDeg {
            lastHeadingDeg = compassDeg
        }

        onUpdate?(Observer(
            lat: fix.coordinate.latitude,
            lon: fix.coordinate.longitude,
            // Eye height above the road, not altitude above sea level: the visibility
            // maths works in height-above-ground.
            altitudeM: eyeHeightM,
            headingDeg: lastHeadingDeg,
            speedKmh: speedKmh,
            accuracyM: fix.horizontalAccuracy,
            timestamp: fix.timestamp,
            isLive: true
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures are normal (tunnels, cold start); keep the last observer.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        onAuthorizationChange?(authorization)
    }

    #if os(iOS)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        compassDeg = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    #endif
}

/// Replays a fixed track. Used by tests and for demoing at a desk without driving.
final class SimulatedPositionSource: PositionSource {
    var onUpdate: ((Observer) -> Void)?

    private let track: [(lat: Double, lon: Double)]
    private let speedKmh: Double
    private let altitudeM: Double
    private let interval: TimeInterval
    private var index = 0
    private var timer: Timer?

    init(track: [(lat: Double, lon: Double)], speedKmh: Double = 80,
         altitudeM: Double = 1.5, interval: TimeInterval = 1) {
        self.track = track
        self.speedKmh = speedKmh
        self.altitudeM = altitudeM
        self.interval = interval
    }

    func start() {
        guard !track.isEmpty else { return }
        emit()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.index = (self.index + 1) % self.track.count
            self.emit()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emit() {
        let here = track[index]
        let next = track[(index + 1) % track.count]
        let heading = track.count > 1
            ? Geo.bearingDeg(here.lat, here.lon, next.lat, next.lon)
            : 0
        onUpdate?(Observer(
            lat: here.lat, lon: here.lon, altitudeM: altitudeM,
            headingDeg: heading, speedKmh: speedKmh, accuracyM: 5,
            timestamp: Date(), isLive: false
        ))
    }
}

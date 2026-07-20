import Foundation
import CoreLocation

enum AppMode: Equatable {
    case flight(FlightRoute)
    case drive
}

struct Snapshot {
    var lat: Double = 0
    var lon: Double = 0
    var altM: Double = 0
    var kmh: Double = 0
    var headingDeg: Double = 0
    var hasFix = false
    var usingGPS = false        // true when position comes from a live fix
    var progress: Double = 0    // flight mode only, 0...1
    var rangeKm: Double = 0     // visibility range (horizon or discovery radius)
}

struct VisibleLandmark: Identifiable {
    let landmark: Landmark
    let distKm: Double
    let bearing: Double
    let rel: Double             // relative bearing [-180, 180)
    var id: Int { landmark.id }
    var clock: Int { Geo.clockPosition(rel) }
}

/// Central state machine: fuses dead reckoning (flight schedule) with GPS,
/// and answers "what's visible right now?"
final class FlightEngine: ObservableObject {
    @Published var mode: AppMode?
    @Published var seatSide: SeatSide = .left
    @Published var wheelsUp: Date?               // nil = still at the gate
    @Published var driveRadiusKm: Double = 100
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var visible: [VisibleLandmark] = []

    let location = LocationService()
    private var timer: Timer?
    private var scrubbedProgress: Double?        // manual re-anchor ("we just passed Denver")
    private var scrubbedAt: Date?

    // MARK: - Lifecycle

    func begin(mode: AppMode) {
        self.mode = mode
        wheelsUp = nil
        scrubbedProgress = nil
        scrubbedAt = nil
        location.start()          // in flight mode GPS is a bonus; in drive mode it's the source
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func endSession() {
        timer?.invalidate()
        timer = nil
        location.stop()
        mode = nil
        snapshot = Snapshot()
        visible = []
    }

    func markWheelsUp(minutesAgo: Double = 0) {
        wheelsUp = Date().addingTimeInterval(-minutesAgo * 60)
        scrubbedProgress = nil
        scrubbedAt = nil
        tick()
    }

    /// Manual progress re-anchor from the HUD scrubber.
    func scrub(to progress: Double) {
        scrubbedProgress = min(max(progress, 0), 1)
        scrubbedAt = Date()
        if wheelsUp == nil { wheelsUp = Date() }  // scrubbing implies we're flying
        tick()
    }

    // MARK: - Tick

    func tick() {
        guard let mode else { return }
        var s = Snapshot()
        switch mode {
        case .flight(let route):
            s = flightSnapshot(route: route)
        case .drive:
            s = driveSnapshot()
        }
        snapshot = s
        visible = s.hasFix ? computeVisible(snapshot: s, mode: mode) : []
    }

    private func flightSnapshot(route: FlightRoute) -> Snapshot {
        var s = Snapshot()
        s.progress = currentProgress(route: route)
        let pos = route.position(progress: s.progress)
        s.lat = pos.lat
        s.lon = pos.lon
        s.headingDeg = route.track(progress: s.progress)
        s.altM = route.altitude(progress: s.progress)
        s.kmh = (wheelsUp != nil && s.progress < 1) ? route.cruiseKmh : 0
        s.hasFix = true

        // A fresh, plausible GPS fix beats dead reckoning.
        if location.fixIsFresh, let fix = location.lastFix, fix.horizontalAccuracy < 200 {
            s.lat = fix.coordinate.latitude
            s.lon = fix.coordinate.longitude
            if fix.verticalAccuracy >= 0, fix.altitude > 0 { s.altM = fix.altitude }
            if fix.speed >= 0 { s.kmh = fix.speed * 3.6 }
            if fix.course >= 0, fix.speed > 30 { s.headingDeg = fix.course }
            s.usingGPS = true
        }
        s.rangeKm = min(Geo.horizonKm(elevM: s.altM), 500)
        return s
    }

    private func driveSnapshot() -> Snapshot {
        var s = Snapshot()
        s.rangeKm = driveRadiusKm
        guard let fix = location.lastFix, fix.horizontalAccuracy >= 0 else { return s }
        s.lat = fix.coordinate.latitude
        s.lon = fix.coordinate.longitude
        s.altM = max(fix.altitude, 0)
        s.kmh = max(fix.speed, 0) * 3.6
        // Heading: GPS course when moving, compass when stopped.
        if fix.course >= 0, s.kmh > 4 {
            s.headingDeg = fix.course
        } else if let compass = location.compassDeg {
            s.headingDeg = compass
        } else {
            s.headingDeg = snapshot.headingDeg   // hold last known
        }
        s.hasFix = true
        s.usingGPS = true
        return s
    }

    private func currentProgress(route: FlightRoute) -> Double {
        guard let wheelsUp else { return 0 }
        let anchorProgress: Double
        let anchorTime: Date
        if let sp = scrubbedProgress, let sa = scrubbedAt {
            anchorProgress = sp
            anchorTime = sa
        } else {
            anchorProgress = 0
            anchorTime = wheelsUp
        }
        let flownKm = anchorProgress * route.totalKm
            + route.cruiseKmh / 3600 * Date().timeIntervalSince(anchorTime)
        return min(max(flownKm / route.totalKm, 0), 1)
    }

    // MARK: - Visibility

    private func computeVisible(snapshot s: Snapshot, mode: AppMode) -> [VisibleLandmark] {
        var out: [VisibleLandmark] = []
        let horizonSelf = Geo.horizonKm(elevM: s.altM)
        let isDrive = (mode == .drive)
        for lm in landmarkDB {
            let d = Geo.distanceKm(s.lat, s.lon, lm.lat, lm.lon)
            let maxD: Double
            if isDrive {
                maxD = driveRadiusKm
            } else {
                maxD = min(horizonSelf + Geo.horizonKm(elevM: lm.elevM), 500)
                if lm.tier == 3 && d > 150 { continue }
            }
            guard d <= maxD, d > 0.05 else { continue }
            let brg = Geo.bearingDeg(s.lat, s.lon, lm.lat, lm.lon)
            out.append(VisibleLandmark(
                landmark: lm, distKm: d, bearing: brg,
                rel: Geo.relativeBearing(brg, heading: s.headingDeg)
            ))
        }
        out.sort { a, b in
            a.landmark.tier != b.landmark.tier
                ? a.landmark.tier < b.landmark.tier
                : a.distKm < b.distKm
        }
        return out
    }
}

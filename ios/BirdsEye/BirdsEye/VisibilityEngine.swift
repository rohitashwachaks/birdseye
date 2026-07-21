import Foundation

/// A landmark resolved against the observer's current position.
struct VisibleLandmark: Identifiable, Equatable {
    let landmark: Landmark
    let distanceKm: Double
    let bearingDeg: Double
    /// Signed bearing relative to where the observer is heading, in [-180, 180).
    let relativeBearingDeg: Double
    /// True when spherical-earth geometry says it's above the horizon. A hint, not a
    /// promise — there is no terrain or building occlusion in this model.
    let isLineOfSight: Bool

    var id: Int { landmark.id }
    var clock: Int { Geo.clockPosition(relativeBearingDeg) }
    /// Roughly behind the observer.
    var isBehind: Bool { abs(relativeBearingDeg) > 100 }

    /// Minutes until abeam, if the observer keeps this course and speed.
    func minutesUntilAbeam(speedKmh: Double) -> Double? {
        guard speedKmh > 5, abs(relativeBearingDeg) < 80 else { return nil }
        let alongTrackKm = distanceKm * cos(Geo.rad(relativeBearingDeg))
        guard alongTrackKm > 0 else { return nil }
        return alongTrackKm / speedKmh * 60
    }
}

/// Pure geometry: given where you are and how high, what's around you?
///
/// Deliberately free of CoreLocation, SwiftUI and mode branching so it can be unit tested
/// directly, and so a change of mode is only ever a change of inputs.
enum VisibilityEngine {

    static func resolve(observer: Observer,
                        mode: ObservationMode,
                        radiusKm: Double,
                        landmarks: [Landmark]) -> [VisibleLandmark] {
        let effectiveRadius = min(radiusKm, mode.maxRangeKm)
        let observerHeightM = mode.observerHeightM(for: observer)
        // Constant for the observer, so hoist it out of the loop.
        let observerHorizonKm = Geo.horizonKm(elevM: observerHeightM)

        var out: [VisibleLandmark] = []
        out.reserveCapacity(64)

        for landmark in landmarks {
            let distance = Geo.distanceKm(observer.lat, observer.lon, landmark.lat, landmark.lon)
            guard distance <= effectiveRadius else { continue }
            // Suppress hyper-local clutter once it's far enough to be irrelevant.
            if landmark.tier >= 3 && distance > mode.localTierCutoffKm { continue }

            let bearing = Geo.bearingDeg(observer.lat, observer.lon, landmark.lat, landmark.lon)
            let lineOfSightKm = observerHorizonKm + Geo.horizonKm(elevM: landmark.heightM)

            out.append(VisibleLandmark(
                landmark: landmark,
                distanceKm: distance,
                bearingDeg: bearing,
                relativeBearingDeg: Geo.relativeBearing(bearing, heading: observer.headingDeg),
                isLineOfSight: distance <= lineOfSightKm
            ))
        }

        // Most notable first, then nearest — the order the feed and the dial's label
        // budget both want.
        out.sort { a, b in
            if a.landmark.tier != b.landmark.tier { return a.landmark.tier < b.landmark.tier }
            return a.distanceKm < b.distanceKm
        }
        return out
    }
}

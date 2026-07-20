import Foundation

/// Spherical-earth geodesy. Angles in degrees, distances in km, elevations in meters.
enum Geo {
    static let earthRadiusKm = 6371.0

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dPhi = rad(lat2 - lat1)
        let dLam = rad(lon2 - lon1)
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLam / 2) * sin(dLam / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
    }

    static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let phi1 = rad(lat1), phi2 = rad(lat2), dLam = rad(lon2 - lon1)
        let y = sin(dLam) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLam)
        return (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Great-circle interpolation (slerp) between two points, fraction in [0, 1].
    static func interpolate(lat1: Double, lon1: Double, lat2: Double, lon2: Double, fraction: Double) -> (lat: Double, lon: Double) {
        let f = min(max(fraction, 0), 1)
        let delta = distanceKm(lat1, lon1, lat2, lon2) / earthRadiusKm
        if delta < 1e-9 { return (lat1, lon1) }
        let a = sin((1 - f) * delta) / sin(delta)
        let b = sin(f * delta) / sin(delta)
        let phi1 = rad(lat1), lam1 = rad(lon1), phi2 = rad(lat2), lam2 = rad(lon2)
        let x = a * cos(phi1) * cos(lam1) + b * cos(phi2) * cos(lam2)
        let y = a * cos(phi1) * sin(lam1) + b * cos(phi2) * sin(lam2)
        let z = a * sin(phi1) + b * sin(phi2)
        return (deg(atan2(z, sqrt(x * x + y * y))), deg(atan2(y, x)))
    }

    /// Distance to the optical horizon from an eye/target elevation in meters.
    static func horizonKm(elevM: Double) -> Double { 3.57 * sqrt(max(elevM, 0)) }

    /// Signed relative bearing in [-180, 180).
    static func relativeBearing(_ bearing: Double, heading: Double) -> Double {
        ((bearing - heading + 540).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180
    }

    /// Aviation clock position (12 = dead ahead) from a relative bearing.
    static func clockPosition(_ rel: Double) -> Int {
        let norm = (rel + 360).truncatingRemainder(dividingBy: 360)
        let h = Int((norm / 30).rounded()) % 12
        return h == 0 ? 12 : h
    }
}

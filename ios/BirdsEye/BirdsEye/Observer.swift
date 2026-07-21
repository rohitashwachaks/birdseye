import Foundation

/// Where you are and which way you're looking — the single value the whole app is
/// written against. Nothing downstream of this knows whether you're in a car, a plane,
/// or on a ship: those differ only in how an `Observer` is produced and how high it sits
/// (see `ObservationMode`).
struct Observer: Equatable {
    var lat: Double = 0
    var lon: Double = 0
    /// Height of the observer above local ground level, in metres.
    /// Drive: the constant eye height. Flight/cruise: comes from the position source.
    var altitudeM: Double = 0
    /// True course when moving, compass heading when stationary. Degrees, 0 = north.
    var headingDeg: Double = 0
    var speedKmh: Double = 0
    /// Horizontal accuracy in metres; negative means unknown.
    var accuracyM: Double = -1
    var timestamp: Date = .distantPast
    /// True when this came from a real sensor fix rather than a simulation.
    var isLive: Bool = false

    var hasFix: Bool { accuracyM >= 0 }
}

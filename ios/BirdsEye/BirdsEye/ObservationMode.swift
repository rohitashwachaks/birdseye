import Foundation

/// A mode is *data, not behaviour*. Nothing in the engine or the views branches on which
/// mode is active — they read these parameters. Adding cruise or flight mode is a new
/// constant below plus a `PositionSource`, with no changes to the visibility maths, the
/// dial, or the feed.
struct ObservationMode: Equatable, Identifiable {
    let id: String
    let title: String
    /// SF Symbol shown at the centre of the dial.
    let glyph: String
    /// Whether the glyph points along the direction of travel (dial is heading-up, so the
    /// glyph is drawn nose-up and needs no rotation for a car).
    let glyphRotationDeg: Double

    /// Height of the observer's eye above whatever they're travelling on, in metres.
    let eyeHeightM: Double
    /// When true, the source's own altitude is added to `eyeHeightM` — that is the entire
    /// difference between standing in a car park and cruising at 11 km.
    let usesSourceAltitude: Bool

    /// "What's around me" radius: the primary gate on what gets shown.
    let defaultRadiusKm: Double
    let radiusChoices: [Double]
    /// Hard cap so a huge radius can't drag the whole planet into the feed.
    let maxRangeKm: Double

    /// Tier-3 (local) landmarks are noise beyond this distance.
    let localTierCutoffKm: Double

    /// Observer height above ground for the line-of-sight calculation.
    func observerHeightM(for observer: Observer) -> Double {
        usesSourceAltitude ? eyeHeightM + max(observer.altitudeM, 0) : eyeHeightM
    }
}

extension ObservationMode {
    /// Sitting in a car: ~1.5 m of eye height, interested in a few km around you.
    static let drive = ObservationMode(
        id: "drive",
        title: "Drive",
        glyph: "car.fill",
        glyphRotationDeg: 0,
        eyeHeightM: 1.5,
        usesSourceAltitude: false,
        defaultRadiusKm: 15,
        radiusChoices: [5, 15, 40, 100],
        maxRangeKm: 150,
        localTierCutoffKm: 25
    )

    // Kept as executable documentation of the seam: re-adding flight mode is this
    // constant plus a dead-reckoning PositionSource — the maths below it never changes.
    //
    // static let flight = ObservationMode(
    //     id: "flight", title: "Flight", glyph: "airplane", glyphRotationDeg: -90,
    //     eyeHeightM: 0, usesSourceAltitude: true,
    //     defaultRadiusKm: 400, radiusChoices: [200, 400, 500], maxRangeKm: 500,
    //     localTierCutoffKm: 150)
}

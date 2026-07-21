import XCTest
@testable import BirdsEye

/// `VisibilityEngine` is pure geometry, so it can be tested directly — no simulator,
/// no CoreLocation, no clock.
final class VisibilityEngineTests: XCTestCase {

    // Downtown Dallas, outside the Sixth Floor Museum, heading due north.
    private let dealeyPlaza = Observer(
        lat: 32.7797, lon: -96.8084, altitudeM: 1.5,
        headingDeg: 0, speedKmh: 50, accuracyM: 5, timestamp: Date(), isLive: true
    )

    private func landmark(_ name: String, lat: Double, lon: Double,
                          heightM: Double, tier: Int = 1, id: Int = 0) -> Landmark {
        Landmark(id: id, name: name, type: .icon, tier: tier,
                 lat: lat, lon: lon, heightM: heightM, elevM: 130)
    }

    private var reunionTower: Landmark {
        landmark("Reunion Tower", lat: 32.7755, lon: -96.8089, heightM: 171, id: 1)
    }

    // MARK: - Range

    func testNearbyLandmarkIsInRangeAndVisible() {
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 15, landmarks: [reunionTower]
        )
        XCTAssertEqual(result.count, 1)
        let tower = try! XCTUnwrap(result.first)
        XCTAssertLessThan(tower.distanceKm, 1.0, "Reunion Tower is a few hundred metres away")
        XCTAssertTrue(tower.isLineOfSight)
    }

    func testLandmarkBeyondRadiusIsExcluded() {
        // Fort Worth is ~50 km west — outside a 15 km radius.
        let fortWorth = landmark("Fort Worth", lat: 32.7513, lon: -97.3300, heightM: 160, id: 2)
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 15, landmarks: [fortWorth]
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// The core of the "radius + visibility hint" model: in range, but the earth's
    /// curvature is in the way.
    func testGroundLevelLandmarkInRangeButOverTheHorizon() {
        // A flat, ground-level feature ~30 km north. At 1.5 m eye height the horizon is
        // only ~4.4 km, so it is listed but not marked as visible.
        let flatThing = landmark("Flat Lake", lat: 33.0500, lon: -96.8084, heightM: 0, tier: 2, id: 3)
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 40, landmarks: [flatThing]
        )
        let item = try! XCTUnwrap(result.first)
        XCTAssertGreaterThan(item.distanceKm, 25)
        XCTAssertFalse(item.isLineOfSight, "ground-level feature 30 km away is below the horizon")
    }

    func testTallLandmarkStaysVisibleFarBeyondTheGroundHorizon() {
        // Same 30 km, but 171 m tall: 3.57*(√1.5 + √171) ≈ 51 km of line of sight.
        let tallThing = landmark("Tall Tower", lat: 33.0500, lon: -96.8084, heightM: 171, id: 4)
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 40, landmarks: [tallThing]
        )
        XCTAssertTrue(try XCTUnwrap(result.first).isLineOfSight)
    }

    // MARK: - Bearings

    func testBearingsAndClockPositions() {
        let due_north = landmark("North", lat: 32.8697, lon: -96.8084, heightM: 200, id: 5)
        let due_east = landmark("East", lat: 32.7797, lon: -96.7000, heightM: 200, id: 6)
        let behind = landmark("South", lat: 32.6897, lon: -96.8084, heightM: 200, id: 7)

        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 40,
            landmarks: [due_north, due_east, behind]
        )
        let byName = Dictionary(uniqueKeysWithValues: result.map { ($0.landmark.name, $0) })

        // Heading is due north, so a landmark to the north is dead ahead: 12 o'clock.
        XCTAssertEqual(byName["North"]?.clock, 12)
        XCTAssertEqual(byName["East"]?.clock, 3)
        XCTAssertEqual(byName["South"]?.clock, 6)
        XCTAssertEqual(byName["South"]?.isBehind, true)
        XCTAssertEqual(byName["North"]?.isBehind, false)
    }

    func testResultsAreSortedByTierThenDistance() {
        let farFamous = landmark("Far Famous", lat: 32.9000, lon: -96.8084, heightM: 200, tier: 1, id: 8)
        let nearLocal = landmark("Near Local", lat: 32.7810, lon: -96.8084, heightM: 20, tier: 3, id: 9)
        let nearRegional = landmark("Near Regional", lat: 32.7820, lon: -96.8084, heightM: 20, tier: 2, id: 10)

        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 40,
            landmarks: [nearLocal, nearRegional, farFamous]
        )
        XCTAssertEqual(result.map(\.landmark.name), ["Far Famous", "Near Regional", "Near Local"])
    }

    func testDistantLocalTierIsSuppressed() {
        // Tier 3 beyond the mode's local cutoff (25 km for drive) is clutter.
        let farLocal = landmark("Far Local", lat: 33.1000, lon: -96.8084, heightM: 200, tier: 3, id: 11)
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 100, landmarks: [farLocal]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - The mode seam

    /// The point of the whole architecture: altitude is the only thing that changes
    /// between modes. Same observer, same landmark, same engine — only the height
    /// differs, and the horizon opens up.
    func testAltitudeIsTheOnlyDifferenceBetweenModes() {
        let distantPeak = landmark("Distant Thing", lat: 34.0000, lon: -96.8084,
                                   heightM: 100, tier: 1, id: 12)

        let cruiseAltitude = ObservationMode(
            id: "test-flight", title: "Flight", glyph: "airplane", glyphRotationDeg: -90,
            eyeHeightM: 0, usesSourceAltitude: true,
            defaultRadiusKm: 400, radiusChoices: [400], maxRangeKm: 500,
            localTierCutoffKm: 150
        )
        var atAltitude = dealeyPlaza
        atAltitude.altitudeM = 10_700

        let fromCar = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 150, landmarks: [distantPeak]
        )
        let fromPlane = VisibilityEngine.resolve(
            observer: atAltitude, mode: cruiseAltitude, radiusKm: 400, landmarks: [distantPeak]
        )

        XCTAssertEqual(fromCar.first?.isLineOfSight, false, "~135 km is far over the car's horizon")
        XCTAssertEqual(fromPlane.first?.isLineOfSight, true, "at 10.7 km the horizon is ~370 km")
    }

    func testObserverHeightCombinesEyeHeightAndSourceAltitude() {
        XCTAssertEqual(ObservationMode.drive.observerHeightM(for: dealeyPlaza), 1.5,
                       "drive mode ignores source altitude — eye height is constant")

        let cruise = ObservationMode(
            id: "cruise", title: "Cruise", glyph: "ferry.fill", glyphRotationDeg: 0,
            eyeHeightM: 20, usesSourceAltitude: true,
            defaultRadiusKm: 50, radiusChoices: [50], maxRangeKm: 100, localTierCutoffKm: 30
        )
        var observer = dealeyPlaza
        observer.altitudeM = 5
        XCTAssertEqual(cruise.observerHeightM(for: observer), 25)
    }

    // MARK: - ETA

    func testMinutesUntilAbeam() {
        let ahead = landmark("Ahead", lat: 32.8697, lon: -96.8084, heightM: 200, id: 13)
        let result = VisibilityEngine.resolve(
            observer: dealeyPlaza, mode: .drive, radiusKm: 40, landmarks: [ahead]
        )
        let item = try! XCTUnwrap(result.first)
        // ~10 km dead ahead at 50 km/h ≈ 12 minutes.
        let minutes = try! XCTUnwrap(item.minutesUntilAbeam(speedKmh: 50))
        XCTAssertEqual(minutes, 12, accuracy: 2)

        XCTAssertNil(item.minutesUntilAbeam(speedKmh: 0), "stationary has no ETA")
    }
}

/// Guards the shipped DFW pack, so a bad import can't silently ship.
final class LandmarkPackTests: XCTestCase {

    private var pack: [Landmark] {
        LandmarkStore.loadPack(named: "landmarks-dfw", bundle: Bundle(for: LandmarkPackTests.self))
    }

    func testPackLoadsAndIsSubstantial() {
        XCTAssertGreaterThan(pack.count, 100, "DFW pack should cover the metroplex")
    }

    func testMarqueeLandmarksArePresent() {
        let names = Set(pack.map(\.name))
        for expected in ["Reunion Tower", "AT&T Stadium", "White Rock Lake",
                         "Six Flags Over Texas", "Perot Museum of Nature and Science"] {
            XCTAssertTrue(names.contains(expected), "missing marquee landmark: \(expected)")
        }
    }

    func testHeightsAndTiersAreSane() {
        for landmark in pack {
            XCTAssertTrue((1...3).contains(landmark.tier), "\(landmark.name) has tier \(landmark.tier)")
            // Tallest building in the metroplex is Bank of America Plaza at 281 m.
            XCTAssertLessThanOrEqual(landmark.heightM, 300, "\(landmark.name) is implausibly tall")
            XCTAssertGreaterThanOrEqual(landmark.heightM, 0)
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(pack.map(\.id)).count, pack.count)
    }

    func testEverythingIsInsideTheDFWBoundingBox() {
        for landmark in pack {
            XCTAssertTrue((32.5...33.3).contains(landmark.lat), "\(landmark.name) lat out of region")
            XCTAssertTrue((-97.6 ... -96.5).contains(landmark.lon), "\(landmark.name) lon out of region")
        }
    }
}

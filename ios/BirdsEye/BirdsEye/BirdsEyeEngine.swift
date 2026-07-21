import Foundation
import CoreLocation

/// Owns the active mode and its position source, and republishes what's around you.
///
/// Note what isn't here: no mode switches, no route maths, no altitude special-casing.
/// Swapping in a different `ObservationMode` + `PositionSource` is the whole story of
/// adding flight or cruise mode.
final class BirdsEyeEngine: ObservableObject {
    @Published private(set) var mode: ObservationMode?
    @Published private(set) var observer = Observer()
    @Published private(set) var visible: [VisibleLandmark] = []
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published var radiusKm: Double = ObservationMode.drive.defaultRadiusKm {
        didSet { recompute() }
    }

    private(set) var source: PositionSource?
    private let landmarks: [Landmark]

    /// Seconds after which a fix is treated as stale rather than current.
    private let fixStaleAfter: TimeInterval = 60

    init(landmarks: [Landmark] = LandmarkStore.all) {
        self.landmarks = landmarks
    }

    var isRunning: Bool { mode != nil }

    var hasFreshFix: Bool {
        observer.hasFix && Date().timeIntervalSince(observer.timestamp) < fixStaleAfter
    }

    /// Start a session. `source` defaults to live GPS at the mode's eye height; tests and
    /// demos pass a `SimulatedPositionSource` instead.
    func start(mode: ObservationMode, source: PositionSource? = nil) {
        stop()
        self.mode = mode
        radiusKm = mode.defaultRadiusKm

        let resolved = source ?? GPSPositionSource(eyeHeightM: mode.eyeHeightM)
        if let gps = resolved as? GPSPositionSource {
            authorization = gps.authorization
            gps.onAuthorizationChange = { [weak self] status in
                Task { @MainActor in self?.authorization = status }
            }
        }
        resolved.onUpdate = { [weak self] observer in
            Task { @MainActor in self?.ingest(observer) }
        }
        self.source = resolved
        resolved.start()
    }

    func stop() {
        source?.stop()
        source = nil
        mode = nil
        observer = Observer()
        visible = []
    }

    private func ingest(_ observer: Observer) {
        self.observer = observer
        recompute()
    }

    private func recompute() {
        guard let mode, observer.hasFix else {
            visible = []
            return
        }
        visible = VisibilityEngine.resolve(
            observer: observer, mode: mode, radiusKm: radiusKm, landmarks: landmarks
        )
    }
}

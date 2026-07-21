import Foundation

enum LandmarkType: String, Codable, CaseIterable {
    case city, town, peak, park, water, icon, wonder, border, museum, stadium, tower, airport, campus

    var glyph: String {
        switch self {
        case .city, .town: return "building.2.fill"
        case .peak: return "mountain.2.fill"
        case .park: return "tree.fill"
        case .water: return "water.waves"
        case .icon: return "star.circle.fill"
        case .wonder: return "sparkles"
        case .border: return "flag.2.crossed.fill"
        case .museum: return "building.columns.fill"
        case .stadium: return "sportscourt.fill"
        case .tower: return "antenna.radiowaves.left.and.right"
        case .airport: return "airplane"
        case .campus: return "graduationcap.fill"
        }
    }
}

struct Landmark: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let type: LandmarkType
    /// 1 = famous, 2 = regional, 3 = local.
    let tier: Int
    let lat: Double
    let lon: Double
    /// Height above the surrounding ground, in metres. Drives line-of-sight: a 171 m tower
    /// is visible from ~50 km, a park from a few hundred metres.
    let heightM: Double
    /// Ground elevation above sea level, in metres. Unused in drive mode; kept for the
    /// future flight mode, where it is what matters.
    let elevM: Double
}

/// Loads landmark packs bundled with the app. Packs are per-region JSON so the set can
/// grow past what a compiled Swift array can hold, and so route/region packs can be
/// downloaded later (see docs/SPEC.md).
enum LandmarkStore {
    /// Region packs to load at launch. Add a filename here when a new pack ships.
    static let bundledPacks = ["landmarks-dfw"]

    static let all: [Landmark] = load(packs: bundledPacks)

    static func load(packs: [String], bundle: Bundle = .main) -> [Landmark] {
        var seen = Set<Int>()
        var out: [Landmark] = []
        for pack in packs {
            for landmark in loadPack(named: pack, bundle: bundle) where !seen.contains(landmark.id) {
                seen.insert(landmark.id)
                out.append(landmark)
            }
        }
        return out
    }

    static func loadPack(named name: String, bundle: Bundle = .main) -> [Landmark] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            assertionFailure("Missing landmark pack '\(name).json' — is Resources/ in the target?")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LandmarkPack.self, from: data).landmarks
        } catch {
            assertionFailure("Landmark pack '\(name)' failed to decode: \(error)")
            return []
        }
    }
}

struct LandmarkPack: Codable {
    let region: String
    let generated: String
    let landmarks: [Landmark]
}

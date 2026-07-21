import Foundation

/// Flight number → route lookup using the free adsbdb.com API
/// (GET https://api.adsbdb.com/v0/callsign/{CALLSIGN}).
/// Airlines file flight plans under ICAO callsigns ("UAL123"), while passengers
/// know IATA flight numbers ("UA123") — we try the input as typed, then retry
/// with the IATA→ICAO airline prefix swapped in.
///
/// IMPORTANT: this database stores ONE historical city pair per callsign, not a
/// dated schedule. Airlines recycle flight numbers across routes and seasons, so
/// a hit can be confidently wrong (e.g. AA296 returns PHX→DFW while today it flies
/// OGG→DFW). Treat every result as a *guess* the user must be able to override —
/// see FlightReadyStep's "Not your route? Fix it".
enum FlightLookup {

    enum LookupError: LocalizedError {
        case notFound
        case network(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No route on file for that flight number. Enter your route directly below."
            case .network(let msg):
                return "Network problem: \(msg). Enter your route directly below."
            }
        }
    }

    static let iataToIcao: [String: String] = [
        "UA": "UAL", "AA": "AAL", "DL": "DAL", "WN": "SWA", "AS": "ASA",
        "B6": "JBU", "NK": "NKS", "F9": "FFT", "HA": "HAL", "G4": "AAY",
        "AC": "ACA", "WS": "WJA", "AM": "AMX", "BA": "BAW", "VS": "VIR",
        "LH": "DLH", "AF": "AFR", "KL": "KLM", "IB": "IBE", "LX": "SWR",
        "TK": "THY", "EK": "UAE", "QR": "QTR", "EY": "ETD", "AI": "AIC",
        "6E": "IGO", "SQ": "SIA", "CX": "CPA", "JL": "JAL", "NH": "ANA",
        "KE": "KAL", "OZ": "AAR", "QF": "QFA", "NZ": "ANZ", "LA": "LAN",
    ]

    static func candidates(for input: String) -> [String] {
        let cleaned = input.uppercased().replacingOccurrences(of: " ", with: "")
        var list = [cleaned]
        // "UA123" → also try "UAL123"
        if cleaned.count >= 3 {
            let prefix2 = String(cleaned.prefix(2))
            let rest = String(cleaned.dropFirst(2))
            if !rest.isEmpty, rest.allSatisfy(\.isNumber), let icao = iataToIcao[prefix2] {
                list.append(icao + rest)
            }
        }
        return list
    }

    static func lookup(_ flightNumber: String) async throws -> FlightRoute {
        var sawNetworkError: String?
        for callsign in candidates(for: flightNumber) {
            guard let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(callsign)") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let route = parse(data: data, label: flightNumber.uppercased()) {
                    return route
                }
            } catch {
                sawNetworkError = error.localizedDescription
            }
        }
        if let msg = sawNetworkError { throw LookupError.network(msg) }
        throw LookupError.notFound
    }

    // MARK: - adsbdb JSON

    private struct APIResponse: Decodable {
        struct Payload: Decodable { let flightroute: Flightroute? }
        struct Flightroute: Decodable {
            let callsign: String?
            let origin: Apt
            let destination: Apt
        }
        struct Apt: Decodable {
            let iata_code: String?
            let icao_code: String?
            let name: String?
            let municipality: String?
            let latitude: Double
            let longitude: Double
        }
        let response: Payload
    }

    private static func parse(data: Data, label: String) -> FlightRoute? {
        // On unknown callsigns the API returns {"response": "unknown callsign"},
        // which fails to decode as Payload — that's our "not found" signal.
        guard let decoded = try? JSONDecoder().decode(APIResponse.self, from: data),
              let fr = decoded.response.flightroute else { return nil }
        func end(_ a: APIResponse.Apt) -> RouteEnd {
            RouteEnd(
                code: a.iata_code ?? a.icao_code ?? "???",
                name: a.name ?? a.municipality ?? "Unknown",
                city: a.municipality ?? a.name ?? "Unknown",
                lat: a.latitude,
                lon: a.longitude
            )
        }
        return FlightRoute(label: label, from: end(fr.origin), to: end(fr.destination))
    }
}

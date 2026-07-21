import Foundation

struct RouteEnd: Hashable {
    let code: String     // IATA where known, e.g. "SFO"
    let name: String     // "San Francisco International"
    let city: String
    let lat: Double
    let lon: Double
}

enum SeatSide: String, CaseIterable, Identifiable {
    case left = "Left window"
    case right = "Right window"
    var id: String { rawValue }
    /// Offset from track to the window's outward bearing.
    var bearingOffset: Double { self == .left ? -90 : 90 }
}

struct FlightRoute: Hashable {
    let label: String            // "UA123" or "SFO → JFK"
    let from: RouteEnd
    let to: RouteEnd
    var cruiseAltM: Double = 10700
    var cruiseKmh: Double = 870

    var totalKm: Double { Geo.distanceKm(from.lat, from.lon, to.lat, to.lon) }
    var cruiseHours: Double { totalKm / cruiseKmh }

    func position(progress: Double) -> (lat: Double, lon: Double) {
        Geo.interpolate(lat1: from.lat, lon1: from.lon, lat2: to.lat, lon2: to.lon, fraction: progress)
    }

    /// Track (course over ground) at a given progress along the great circle.
    func track(progress: Double) -> Double {
        let here = position(progress: progress)
        let ahead = position(progress: min(progress + 0.0005, 1))
        if progress >= 0.9995 {
            let behind = position(progress: max(progress - 0.0005, 0))
            return Geo.bearingDeg(behind.lat, behind.lon, here.lat, here.lon)
        }
        return Geo.bearingDeg(here.lat, here.lon, ahead.lat, ahead.lon)
    }

    /// Climb/descent ramp over the first/last 8% of the route.
    func altitude(progress: Double) -> Double {
        let ramp = min(1, progress / 0.08, (1 - progress) / 0.08)
        return max(60, cruiseAltM * max(ramp, 0))
    }

    /// Which window side sees a given landmark for most of the flight is decided
    /// by the sign of its cross-track position; here we just answer it for one point.
    func side(ofLat lat: Double, lon: Double, atProgress p: Double) -> SeatSide {
        let here = position(progress: p)
        let rel = Geo.relativeBearing(Geo.bearingDeg(here.lat, here.lon, lat, lon), heading: track(progress: p))
        return rel < 0 ? .left : .right
    }
}

// MARK: - Offline airport list (manual-route fallback when the lookup API is unreachable)

struct Airport: Identifiable, Hashable {
    let iata: String
    let name: String
    let lat: Double
    let lon: Double
    var id: String { iata }
    var routeEnd: RouteEnd { RouteEnd(code: iata, name: name, city: name, lat: lat, lon: lon) }
}

let airportDB: [Airport] = [
    // US West
    Airport(iata: "SFO", name: "San Francisco", lat: 37.6213, lon: -122.3790),
    Airport(iata: "OAK", name: "Oakland", lat: 37.7126, lon: -122.2197),
    Airport(iata: "SJC", name: "San Jose", lat: 37.3639, lon: -121.9289),
    Airport(iata: "SMF", name: "Sacramento", lat: 38.6954, lon: -121.5908),
    Airport(iata: "LAX", name: "Los Angeles", lat: 33.9416, lon: -118.4085),
    Airport(iata: "BUR", name: "Burbank", lat: 34.2007, lon: -118.3590),
    Airport(iata: "SNA", name: "Orange County / Santa Ana", lat: 33.6757, lon: -117.8683),
    Airport(iata: "SAN", name: "San Diego", lat: 32.7338, lon: -117.1933),
    Airport(iata: "PSP", name: "Palm Springs", lat: 33.8297, lon: -116.5067),
    Airport(iata: "SEA", name: "Seattle", lat: 47.4502, lon: -122.3088),
    Airport(iata: "PDX", name: "Portland", lat: 45.5898, lon: -122.5951),
    Airport(iata: "BOI", name: "Boise", lat: 43.5644, lon: -116.2228),
    Airport(iata: "GEG", name: "Spokane", lat: 47.6199, lon: -117.5338),
    Airport(iata: "RNO", name: "Reno–Tahoe", lat: 39.4991, lon: -119.7681),
    Airport(iata: "LAS", name: "Las Vegas", lat: 36.0840, lon: -115.1537),
    Airport(iata: "PHX", name: "Phoenix", lat: 33.4342, lon: -112.0116),
    Airport(iata: "TUS", name: "Tucson", lat: 32.1161, lon: -110.9410),
    Airport(iata: "ABQ", name: "Albuquerque", lat: 35.0402, lon: -106.6091),
    Airport(iata: "DEN", name: "Denver", lat: 39.8561, lon: -104.6737),
    Airport(iata: "SLC", name: "Salt Lake City", lat: 40.7899, lon: -111.9791),
    Airport(iata: "JAC", name: "Jackson Hole", lat: 43.6073, lon: -110.7377),
    Airport(iata: "BZN", name: "Bozeman", lat: 45.7776, lon: -111.1530),
    // US Central / South
    Airport(iata: "DFW", name: "Dallas–Fort Worth", lat: 32.8998, lon: -97.0403),
    Airport(iata: "DAL", name: "Dallas Love Field", lat: 32.8471, lon: -96.8518),
    Airport(iata: "AUS", name: "Austin", lat: 30.1975, lon: -97.6664),
    Airport(iata: "IAH", name: "Houston Intercontinental", lat: 29.9902, lon: -95.3368),
    Airport(iata: "HOU", name: "Houston Hobby", lat: 29.6454, lon: -95.2789),
    Airport(iata: "SAT", name: "San Antonio", lat: 29.5337, lon: -98.4698),
    Airport(iata: "OKC", name: "Oklahoma City", lat: 35.3931, lon: -97.6007),
    Airport(iata: "MSY", name: "New Orleans", lat: 29.9934, lon: -90.2581),
    Airport(iata: "BNA", name: "Nashville", lat: 36.1263, lon: -86.6774),
    Airport(iata: "MEM", name: "Memphis", lat: 35.0424, lon: -89.9767),
    Airport(iata: "MSP", name: "Minneapolis", lat: 44.8848, lon: -93.2223),
    Airport(iata: "ORD", name: "Chicago O'Hare", lat: 41.9742, lon: -87.9073),
    Airport(iata: "MDW", name: "Chicago Midway", lat: 41.7868, lon: -87.7522),
    Airport(iata: "STL", name: "St Louis", lat: 38.7500, lon: -90.3700),
    Airport(iata: "MCI", name: "Kansas City", lat: 39.2976, lon: -94.7139),
    Airport(iata: "OMA", name: "Omaha", lat: 41.3032, lon: -95.8941),
    Airport(iata: "IND", name: "Indianapolis", lat: 39.7173, lon: -86.2944),
    Airport(iata: "CLE", name: "Cleveland", lat: 41.4117, lon: -81.8498),
    Airport(iata: "CMH", name: "Columbus", lat: 39.9980, lon: -82.8919),
    Airport(iata: "DTW", name: "Detroit", lat: 42.2162, lon: -83.3554),
    Airport(iata: "PIT", name: "Pittsburgh", lat: 40.4915, lon: -80.2329),
    // US East
    Airport(iata: "ATL", name: "Atlanta", lat: 33.6407, lon: -84.4277),
    Airport(iata: "MIA", name: "Miami", lat: 25.7959, lon: -80.2870),
    Airport(iata: "FLL", name: "Fort Lauderdale", lat: 26.0742, lon: -80.1506),
    Airport(iata: "MCO", name: "Orlando", lat: 28.4312, lon: -81.3081),
    Airport(iata: "TPA", name: "Tampa", lat: 27.9755, lon: -82.5332),
    Airport(iata: "CLT", name: "Charlotte", lat: 35.2144, lon: -80.9473),
    Airport(iata: "RDU", name: "Raleigh–Durham", lat: 35.8801, lon: -78.7880),
    Airport(iata: "JFK", name: "New York JFK", lat: 40.6413, lon: -73.7781),
    Airport(iata: "EWR", name: "Newark", lat: 40.6895, lon: -74.1745),
    Airport(iata: "LGA", name: "New York LaGuardia", lat: 40.7769, lon: -73.8740),
    Airport(iata: "BOS", name: "Boston", lat: 42.3656, lon: -71.0096),
    Airport(iata: "PHL", name: "Philadelphia", lat: 39.8729, lon: -75.2437),
    Airport(iata: "BWI", name: "Baltimore", lat: 39.1774, lon: -76.6684),
    Airport(iata: "DCA", name: "Washington National", lat: 38.8512, lon: -77.0402),
    Airport(iata: "IAD", name: "Washington Dulles", lat: 38.9531, lon: -77.4565),
    // Hawaii & Alaska
    Airport(iata: "HNL", name: "Honolulu, Oahu", lat: 21.3245, lon: -157.9251),
    Airport(iata: "OGG", name: "Kahului, Maui", lat: 20.8986, lon: -156.4305),
    Airport(iata: "KOA", name: "Kona, Big Island", lat: 19.7388, lon: -156.0456),
    Airport(iata: "ITO", name: "Hilo, Big Island", lat: 19.7203, lon: -155.0485),
    Airport(iata: "LIH", name: "Lihue, Kauai", lat: 21.9760, lon: -159.3390),
    Airport(iata: "ANC", name: "Anchorage", lat: 61.1743, lon: -149.9982),
    Airport(iata: "FAI", name: "Fairbanks", lat: 64.8151, lon: -147.8560),
    // Canada / Mexico / Caribbean
    Airport(iata: "YVR", name: "Vancouver", lat: 49.1947, lon: -123.1792),
    Airport(iata: "YYC", name: "Calgary", lat: 51.1315, lon: -114.0106),
    Airport(iata: "YYZ", name: "Toronto", lat: 43.6777, lon: -79.6248),
    Airport(iata: "YUL", name: "Montreal", lat: 45.4657, lon: -73.7455),
    Airport(iata: "MEX", name: "Mexico City", lat: 19.4363, lon: -99.0721),
    Airport(iata: "CUN", name: "Cancún", lat: 21.0365, lon: -86.8771),
    Airport(iata: "SJD", name: "Los Cabos", lat: 23.1518, lon: -109.7211),
    Airport(iata: "SJU", name: "San Juan, Puerto Rico", lat: 18.4394, lon: -66.0018),
    Airport(iata: "HAV", name: "Havana", lat: 22.9892, lon: -82.4091),
    // Latin America
    Airport(iata: "PTY", name: "Panama City", lat: 9.0714, lon: -79.3835),
    Airport(iata: "BOG", name: "Bogotá", lat: 4.7016, lon: -74.1469),
    Airport(iata: "UIO", name: "Quito", lat: -0.1292, lon: -78.3575),
    Airport(iata: "LIM", name: "Lima", lat: -12.0219, lon: -77.1143),
    Airport(iata: "CUZ", name: "Cusco", lat: -13.5357, lon: -71.9388),
    Airport(iata: "SCL", name: "Santiago", lat: -33.3930, lon: -70.7858),
    Airport(iata: "GRU", name: "São Paulo", lat: -23.4356, lon: -46.4731),
    Airport(iata: "GIG", name: "Rio de Janeiro", lat: -22.8100, lon: -43.2506),
    Airport(iata: "EZE", name: "Buenos Aires", lat: -34.8222, lon: -58.5358),
    // Europe
    Airport(iata: "KEF", name: "Reykjavik", lat: 63.9850, lon: -22.6056),
    Airport(iata: "LHR", name: "London Heathrow", lat: 51.4700, lon: -0.4543),
    Airport(iata: "LGW", name: "London Gatwick", lat: 51.1537, lon: -0.1821),
    Airport(iata: "DUB", name: "Dublin", lat: 53.4213, lon: -6.2701),
    Airport(iata: "CDG", name: "Paris CDG", lat: 49.0097, lon: 2.5479),
    Airport(iata: "AMS", name: "Amsterdam", lat: 52.3105, lon: 4.7683),
    Airport(iata: "BRU", name: "Brussels", lat: 50.9014, lon: 4.4844),
    Airport(iata: "FRA", name: "Frankfurt", lat: 50.0379, lon: 8.5622),
    Airport(iata: "MUC", name: "Munich", lat: 48.3537, lon: 11.7750),
    Airport(iata: "BER", name: "Berlin", lat: 52.3667, lon: 13.5033),
    Airport(iata: "CPH", name: "Copenhagen", lat: 55.6180, lon: 12.6508),
    Airport(iata: "ARN", name: "Stockholm", lat: 59.6519, lon: 17.9186),
    Airport(iata: "OSL", name: "Oslo", lat: 60.1939, lon: 11.1004),
    Airport(iata: "MAD", name: "Madrid", lat: 40.4983, lon: -3.5676),
    Airport(iata: "BCN", name: "Barcelona", lat: 41.2974, lon: 2.0833),
    Airport(iata: "LIS", name: "Lisbon", lat: 38.7742, lon: -9.1342),
    Airport(iata: "FCO", name: "Rome Fiumicino", lat: 41.8003, lon: 12.2389),
    Airport(iata: "MXP", name: "Milan Malpensa", lat: 45.6306, lon: 8.7281),
    Airport(iata: "VCE", name: "Venice", lat: 45.5053, lon: 12.3519),
    Airport(iata: "ATH", name: "Athens", lat: 37.9364, lon: 23.9445),
    Airport(iata: "ZRH", name: "Zurich", lat: 47.4582, lon: 8.5555),
    Airport(iata: "VIE", name: "Vienna", lat: 48.1103, lon: 16.5697),
    Airport(iata: "PRG", name: "Prague", lat: 50.1008, lon: 14.2600),
    Airport(iata: "WAW", name: "Warsaw", lat: 52.1657, lon: 20.9671),
    Airport(iata: "IST", name: "Istanbul", lat: 41.2753, lon: 28.7519),
    // Middle East / Africa
    Airport(iata: "DXB", name: "Dubai", lat: 25.2532, lon: 55.3657),
    Airport(iata: "AUH", name: "Abu Dhabi", lat: 24.4330, lon: 54.6511),
    Airport(iata: "DOH", name: "Doha", lat: 25.2731, lon: 51.6081),
    Airport(iata: "TLV", name: "Tel Aviv", lat: 32.0114, lon: 34.8867),
    Airport(iata: "CAI", name: "Cairo", lat: 30.1219, lon: 31.4056),
    Airport(iata: "JNB", name: "Johannesburg", lat: -26.1367, lon: 28.2411),
    Airport(iata: "CPT", name: "Cape Town", lat: -33.9649, lon: 18.6017),
    Airport(iata: "NBO", name: "Nairobi", lat: -1.3192, lon: 36.9278),
    Airport(iata: "ADD", name: "Addis Ababa", lat: 8.9779, lon: 38.7993),
    // Asia / Oceania
    Airport(iata: "DEL", name: "Delhi", lat: 28.5562, lon: 77.1000),
    Airport(iata: "BOM", name: "Mumbai", lat: 19.0896, lon: 72.8656),
    Airport(iata: "BLR", name: "Bengaluru", lat: 13.1986, lon: 77.7066),
    Airport(iata: "HYD", name: "Hyderabad", lat: 17.2403, lon: 78.4294),
    Airport(iata: "MAA", name: "Chennai", lat: 12.9941, lon: 80.1709),
    Airport(iata: "CCU", name: "Kolkata", lat: 22.6547, lon: 88.4467),
    Airport(iata: "COK", name: "Kochi", lat: 10.1520, lon: 76.4019),
    Airport(iata: "KTM", name: "Kathmandu", lat: 27.6966, lon: 85.3591),
    Airport(iata: "BKK", name: "Bangkok", lat: 13.6900, lon: 100.7501),
    Airport(iata: "SIN", name: "Singapore", lat: 1.3644, lon: 103.9915),
    Airport(iata: "KUL", name: "Kuala Lumpur", lat: 2.7456, lon: 101.7099),
    Airport(iata: "CGK", name: "Jakarta", lat: -6.1256, lon: 106.6559),
    Airport(iata: "DPS", name: "Bali (Denpasar)", lat: -8.7482, lon: 115.1672),
    Airport(iata: "MNL", name: "Manila", lat: 14.5086, lon: 121.0194),
    Airport(iata: "HKG", name: "Hong Kong", lat: 22.3080, lon: 113.9185),
    Airport(iata: "TPE", name: "Taipei", lat: 25.0777, lon: 121.2328),
    Airport(iata: "NRT", name: "Tokyo Narita", lat: 35.7720, lon: 140.3929),
    Airport(iata: "HND", name: "Tokyo Haneda", lat: 35.5494, lon: 139.7798),
    Airport(iata: "KIX", name: "Osaka Kansai", lat: 34.4273, lon: 135.2440),
    Airport(iata: "ICN", name: "Seoul Incheon", lat: 37.4602, lon: 126.4407),
    Airport(iata: "PEK", name: "Beijing Capital", lat: 40.0799, lon: 116.6031),
    Airport(iata: "PVG", name: "Shanghai Pudong", lat: 31.1443, lon: 121.8083),
    Airport(iata: "CAN", name: "Guangzhou", lat: 23.3924, lon: 113.2988),
    Airport(iata: "SYD", name: "Sydney", lat: -33.9399, lon: 151.1753),
    Airport(iata: "MEL", name: "Melbourne", lat: -37.6690, lon: 144.8410),
    Airport(iata: "BNE", name: "Brisbane", lat: -27.3842, lon: 153.1175),
    Airport(iata: "PER", name: "Perth", lat: -31.9385, lon: 115.9672),
    Airport(iata: "AKL", name: "Auckland", lat: -37.0082, lon: 174.7850),
    Airport(iata: "CHC", name: "Christchurch", lat: -43.4894, lon: 172.5320),
    Airport(iata: "NAN", name: "Nadi, Fiji", lat: -17.7554, lon: 177.4434),
].sorted { $0.iata < $1.iata }

extension Airport {
    /// Fuzzy match for the airport search field: IATA code or city/airport name.
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return false }
        return iata.hasPrefix(q) || name.uppercased().contains(q)
    }
}

func airport(forIATA code: String) -> Airport? {
    airportDB.first { $0.iata == code.uppercased() }
}

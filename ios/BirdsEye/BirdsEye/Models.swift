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
    Airport(iata: "SFO", name: "San Francisco", lat: 37.6213, lon: -122.3790),
    Airport(iata: "OAK", name: "Oakland", lat: 37.7126, lon: -122.2197),
    Airport(iata: "SJC", name: "San Jose", lat: 37.3639, lon: -121.9289),
    Airport(iata: "LAX", name: "Los Angeles", lat: 33.9416, lon: -118.4085),
    Airport(iata: "SAN", name: "San Diego", lat: 32.7338, lon: -117.1933),
    Airport(iata: "SEA", name: "Seattle", lat: 47.4502, lon: -122.3088),
    Airport(iata: "PDX", name: "Portland", lat: 45.5898, lon: -122.5951),
    Airport(iata: "LAS", name: "Las Vegas", lat: 36.0840, lon: -115.1537),
    Airport(iata: "PHX", name: "Phoenix", lat: 33.4342, lon: -112.0116),
    Airport(iata: "DEN", name: "Denver", lat: 39.8561, lon: -104.6737),
    Airport(iata: "SLC", name: "Salt Lake City", lat: 40.7899, lon: -111.9791),
    Airport(iata: "DFW", name: "Dallas–Fort Worth", lat: 32.8998, lon: -97.0403),
    Airport(iata: "AUS", name: "Austin", lat: 30.1975, lon: -97.6664),
    Airport(iata: "IAH", name: "Houston", lat: 29.9902, lon: -95.3368),
    Airport(iata: "MSP", name: "Minneapolis", lat: 44.8848, lon: -93.2223),
    Airport(iata: "ORD", name: "Chicago O'Hare", lat: 41.9742, lon: -87.9073),
    Airport(iata: "STL", name: "St Louis", lat: 38.7500, lon: -90.3700),
    Airport(iata: "MCI", name: "Kansas City", lat: 39.2976, lon: -94.7139),
    Airport(iata: "DTW", name: "Detroit", lat: 42.2162, lon: -83.3554),
    Airport(iata: "ATL", name: "Atlanta", lat: 33.6407, lon: -84.4277),
    Airport(iata: "MIA", name: "Miami", lat: 25.7959, lon: -80.2870),
    Airport(iata: "MCO", name: "Orlando", lat: 28.4312, lon: -81.3081),
    Airport(iata: "CLT", name: "Charlotte", lat: 35.2144, lon: -80.9473),
    Airport(iata: "JFK", name: "New York JFK", lat: 40.6413, lon: -73.7781),
    Airport(iata: "EWR", name: "Newark", lat: 40.6895, lon: -74.1745),
    Airport(iata: "LGA", name: "New York LaGuardia", lat: 40.7769, lon: -73.8740),
    Airport(iata: "BOS", name: "Boston", lat: 42.3656, lon: -71.0096),
    Airport(iata: "PHL", name: "Philadelphia", lat: 39.8729, lon: -75.2437),
    Airport(iata: "DCA", name: "Washington National", lat: 38.8512, lon: -77.0402),
    Airport(iata: "IAD", name: "Washington Dulles", lat: 38.9531, lon: -77.4565),
    Airport(iata: "HNL", name: "Honolulu", lat: 21.3245, lon: -157.9251),
    Airport(iata: "ANC", name: "Anchorage", lat: 61.1743, lon: -149.9982),
    Airport(iata: "YVR", name: "Vancouver", lat: 49.1947, lon: -123.1792),
    Airport(iata: "YYZ", name: "Toronto", lat: 43.6777, lon: -79.6248),
    Airport(iata: "MEX", name: "Mexico City", lat: 19.4363, lon: -99.0721),
    Airport(iata: "CUN", name: "Cancún", lat: 21.0365, lon: -86.8771),
    Airport(iata: "LIM", name: "Lima", lat: -12.0219, lon: -77.1143),
    Airport(iata: "SCL", name: "Santiago", lat: -33.3930, lon: -70.7858),
    Airport(iata: "GRU", name: "São Paulo", lat: -23.4356, lon: -46.4731),
    Airport(iata: "EZE", name: "Buenos Aires", lat: -34.8222, lon: -58.5358),
    Airport(iata: "LHR", name: "London Heathrow", lat: 51.4700, lon: -0.4543),
    Airport(iata: "CDG", name: "Paris CDG", lat: 49.0097, lon: 2.5479),
    Airport(iata: "AMS", name: "Amsterdam", lat: 52.3105, lon: 4.7683),
    Airport(iata: "FRA", name: "Frankfurt", lat: 50.0379, lon: 8.5622),
    Airport(iata: "MAD", name: "Madrid", lat: 40.4983, lon: -3.5676),
    Airport(iata: "BCN", name: "Barcelona", lat: 41.2974, lon: 2.0833),
    Airport(iata: "FCO", name: "Rome Fiumicino", lat: 41.8003, lon: 12.2389),
    Airport(iata: "ZRH", name: "Zurich", lat: 47.4582, lon: 8.5555),
    Airport(iata: "IST", name: "Istanbul", lat: 41.2753, lon: 28.7519),
    Airport(iata: "DXB", name: "Dubai", lat: 25.2532, lon: 55.3657),
    Airport(iata: "DOH", name: "Doha", lat: 25.2731, lon: 51.6081),
    Airport(iata: "DEL", name: "Delhi", lat: 28.5562, lon: 77.1000),
    Airport(iata: "BOM", name: "Mumbai", lat: 19.0896, lon: 72.8656),
    Airport(iata: "BLR", name: "Bengaluru", lat: 13.1986, lon: 77.7066),
    Airport(iata: "HYD", name: "Hyderabad", lat: 17.2403, lon: 78.4294),
    Airport(iata: "MAA", name: "Chennai", lat: 12.9941, lon: 80.1709),
    Airport(iata: "SIN", name: "Singapore", lat: 1.3644, lon: 103.9915),
    Airport(iata: "HKG", name: "Hong Kong", lat: 22.3080, lon: 113.9185),
    Airport(iata: "NRT", name: "Tokyo Narita", lat: 35.7720, lon: 140.3929),
    Airport(iata: "HND", name: "Tokyo Haneda", lat: 35.5494, lon: 139.7798),
    Airport(iata: "ICN", name: "Seoul Incheon", lat: 37.4602, lon: 126.4407),
    Airport(iata: "PEK", name: "Beijing", lat: 40.0799, lon: 116.6031),
    Airport(iata: "PVG", name: "Shanghai Pudong", lat: 31.1443, lon: 121.8083),
    Airport(iata: "SYD", name: "Sydney", lat: -33.9399, lon: 151.1753),
    Airport(iata: "MEL", name: "Melbourne", lat: -37.6690, lon: 144.8410),
    Airport(iata: "AKL", name: "Auckland", lat: -37.0082, lon: 174.7850),
].sorted { $0.iata < $1.iata }

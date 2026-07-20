# Birds Eye — Product & Technical Spec

> *"What's that below me?"* — Turn the airplane window (and the phone held up to it) into a
> head-up display that names the mountains, cities, borders, and wonders sliding past below.

**Status:** v0 scoping doc + working web prototype (see `app/`).
**Positioning:** Free novelty app at launch; paid tiers only if there's real traction.

---

## 1. The core insight

At cruise altitude (~11 km) the horizon is **~370 km away**. You can *see* an enormous amount
of the planet from a window seat — you just can't *name* any of it. The in-flight map shows a
tiny airplane on a Mercator projection; it answers "where is the plane?" but never "what is
that thing out my window, 40° to my left?"

Birds Eye answers the second question. Given **(lat, lon, altitude, heading)** + a landmark
database, identifying what's visible is straightforward geometry. The hard parts are
(a) getting position/heading reliably inside a metal tube, and (b) an interface that feels
like discovery, not like a GIS tool.

### The three questions the app must answer
1. **"What's that?"** — point the phone/strip at something, get a name + distance.
2. **"Am I over X yet?"** — passive awareness: notify/highlight when notable things approach.
3. **"Where would Y be?"** — search a landmark, get its direction + distance ("Machu Picchu:
   2 o'clock, 210 km — visible in ~14 min").

---

## 2. Positioning stack (the hard technical problem)

No single source works all the time. Use a **layered estimator** — each layer feeds a simple
fused state `(lat, lon, alt, ground-track, ground-speed, confidence)`:

| Priority | Source | Notes |
|---|---|---|
| 1 | **GPS via window** | Works surprisingly often if the phone is near the window (GNSS needs ~4 sats; window seats frequently get a fix, especially on the sun-side). Free, exact. Detect degradation via HDOP/stale fixes. |
| 2 | **Dead reckoning from flight schedule** | User enters flight number pre-flight. We pre-download the **planned route** (origin/dest, typical route polyline, scheduled times, cruise alt) from FlightAware/FR24/OpenSky/ADS-B Exchange historical data for that flight number. In-flight: `position = route(t)` using departure time + elapsed time. Error ~tens of km — good enough at 370 km horizon scale. |
| 3 | **Barometric altimeter** | Phone barometer reads *cabin* pressure (pressurized to ~2,400 m equiv) — NOT usable for altitude directly, but the cabin-pressure *profile* (climb/descent curves) is a great phase detector: taxi/climb/cruise/descent. Use it to time-warp the dead-reckoning clock (e.g., late departure). |
| 4 | **Manual nudge** | "We just passed Denver" → tap the map to re-anchor dead reckoning. Also: takeoff-detected timestamp (accelerometer) anchors t=0. |

**Heading / orientation:**
- Magnetometer is unreliable in the cabin (airframe, electronics). Treat compass as low-trust.
- **Ground-track from route** is high-trust: the plane's course *is* the direction of travel.
- The user tells us **which side they're sitting** (left/right window) — one tap. Then
  "out my window" = track ± 90°. This collapses the AR orientation problem to a 1-bit input.
- In AR mode, gyro (relative rotation) is reliable; only the initial absolute bearing needs
  anchoring → anchor with: window direction (track ± 90°), sun position (computable from time
  + position; the brightest spot in camera = azimuth check), or user aligning one known landmark.
- **Drive mode** (testing): GPS course-over-ground when moving; compass fallback when stopped.

**Which side will things be on?** Pre-flight, we know the route → we can compute *before
boarding* which seat side gets the Grand Canyon. Killer feature: **"Sit on the LEFT for this
flight"** at booking/check-in time. Great shareable moment, zero sensors needed.

---

## 3. Visibility math

- Horizon distance from altitude *h* (meters): `d ≈ 3.57 × √h` km.
  - Cruise 11,000 m → **374 km**. Car at sea level → ~5 km (hence drive mode uses a fixed
    "discovery radius" instead — you can't see far, but you still want to know what's around).
- A landmark with its own elevation *e* is visible up to `3.57(√h + √e)` km — Denali
  (6,190 m) is theoretically visible from ~650 km at cruise.
- v1 refinement: terrain occlusion (does a ridge block the line of sight?) via coarse DEM
  raycast. Skip for v0 — at cruise altitude, occlusion rarely matters for notable landmarks.
- Atmospheric reality: haze usually limits practical visibility to 100–250 km. Expose a
  user-tunable "visibility" slider rather than modeling weather.
- Relative bearing → **clock position** ("Rockies at 2 o'clock") — aviation-native, instantly
  understood, works in the compass strip *and* in speech/notifications.

## 4. Data: what's "below me"?

**Layered landmark database** (all offline-friendly, all open):

| Layer | Source | Size (global) |
|---|---|---|
| Cities/towns (pop-ranked) | GeoNames (CC-BY) | ~10 MB filtered |
| Peaks, ranges, volcanoes | OSM `natural=peak` + Wikidata prominence | ~20 MB |
| Parks, deserts, lakes, rivers | OSM + Natural Earth polygons | ~50 MB |
| Country/state **borders** | Natural Earth (lines!) — render as crossable events: "US–Mexico border in 6 min" | ~5 MB |
| "Wonders" (hand-curated) | Our own list w/ 1-paragraph stories (Machu Picchu, Nazca, Uyuni…) | ~1 MB |
| Coarse terrain (hillshade base map) | Mapzen/AWS terrain tiles, z0–z8 | ~60 MB |

- **Pre-flight download = a route corridor**, not the planet: great-circle ± 400 km buffer at
  the needed zooms. Typical long-haul corridor ≈ **30–80 MB**. Acceptable friction (stated).
- Online mode (v2): same engine, tiles streamed; not scoped yet.
- Every landmark gets: name, type, importance tier (1=world-famous, 2=regional, 3=local),
  elevation, and (tier-1 only) a 2-sentence story. The *story* is what turns "label" into
  "discovery" — this is the content moat, and later the paid tier (narrated "flyover tours").

## 5. Experience / UX

**Design language:** night-flight HUD. Near-black cabin-friendly UI (won't annoy seatmates),
cyan/amber avionics accents, big mono numerals, everything glanceable at arm's length.

### Mode ladder (also the build ladder)
1. **Compass Strip (v0, no camera)** — the smallest testable thing. A horizontal strip = the
   view out the window. Center = your heading (or window direction). Landmarks appear as
   chips positioned by relative bearing, with distance + clock position. Below: "Coming up"
   feed ("Lake Tahoe — 1 o'clock, 95 km, ~7 min"). Works face-down in your lap. **This is
   the prototype in `app/`.**
2. **Window mode (v1)** — phone held in landscape against the window: full-bleed horizon
   line, strip becomes the actual view. Pinch = visibility range. Tap chip = story card.
3. **AR mode (v1.5)** — camera passthrough + overlaid labels (ARKit/ARCore world tracking,
   gyro-stabilized, absolute bearing anchored per §2). The wow-demo, but *not* required for
   the core value — ship after the strip proves retention.
4. **Search & notify (v1)** — "Where's Machu Picchu?" → arrow + ETA-to-visible. Opt-in haptic
   when a tier-1 wonder or a border enters view. (Aside: notifications while phone is locked
   = the "don't miss the Grand Canyon while napping" feature.)

### Flight setup flow (offline-first)
Pre-flight (online): enter flight number → we fetch route + schedule → download corridor pack
→ "Sit on the LEFT" tip. Onboard (offline): open app → "Flight UA123 · departed 10:42 ·
tracking by schedule" → optionally hold phone to window for GPS lock → pick your window side.

## 6. Architecture

**Prototype (this repo):** vanilla JS single-page app — zero build, runs anywhere, phone
browser included. Simulation mode (great-circle flight replay) + Live GPS mode (drive mode).

**Product:** iOS-first, Swift/SwiftUI. CoreLocation (GPS), CoreMotion (gyro/baro), ARKit for
mode 3, MapKit-free (own lightweight renderer over MBTiles/PMTiles corridor packs). Android
later (Kotlin, same PMTiles packs). Backend: nearly none — a static tile/pack server + a tiny
route-lookup API (flight number → route polyline + schedule), cacheable/CDN-able. No accounts
in v0/v1.

**Testing without flying (cheap and crucial):**
- **Simulate mode** — replay great-circle routes at 60×–600× (in the prototype today).
- **Drive mode** — live GPS + discovery radius; validates the whole pipeline end-to-end from
  a car seat: fix acquisition, heading, chip layout, "coming up" pacing.
- **GPX replay** — record real flights (ask friends to log w/ phone at window), replay sensor
  traces in CI.

## 7. 0 → 1 launch plan

1. **Week 0–1:** this prototype → validate the strip UX in drive mode + simulated flights.
2. **Week 2–5:** iOS TestFlight: strip mode + flight-number dead reckoning + corridor packs
   for ~20 popular US routes. Hand-curate tier-1 wonders along those corridors.
3. **Beta seeding:** r/aviation, r/flying, FlightRadar24 community, avgeek Twitter/YouTube.
   The **seat-side tip** ("sit LEFT for the Grand Canyon") is the shareable hook — it works
   as a screenshot before anyone installs anything.
4. **Launch:** free, App Store. Success metric: % of sessions >10 min in airplane mode, and
   organic shares of the seat-tip card.
5. **If traction → paid ("Birds Eye Pro"):** narrated flyover tours, global offline packs,
   AR mode, live online mode. Never paywall the basic strip.

**Risks:** GPS fix rates in-cabin unknown at scale (mitigate: dead reckoning is the default,
GPS is a bonus); route data licensing (FlightAware API costs — start with OpenSky/ADS-B
Exchange + static schedule data); AR compass anchoring may frustrate (mitigate: strip mode is
the primary UX, AR is a bonus mode).

**Open questions:** iPad window-mount market? Airline IFE partnership (they have position
data on a socket — some expose it on cabin wifi as `flightdata` JSON — worth sniffing)?
Star-map style "point up" night mode (moon/planets/ISS passes)?

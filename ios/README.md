# Birds Eye — iOS app

Native SwiftUI app: onboarding (flight number → offline route download, or Drive mode →
live GPS) and a **circular compass dial** HUD — heading-up, you at the center, landmarks
plotted by relative bearing and distance so you know exactly where to look out the window.

## Run it on your iPhone

1. **Install Xcode** from the Mac App Store (the full app — Command Line Tools alone can't
   build iOS apps). First launch: let it install the iOS platform.
2. Open `ios/BirdsEye/BirdsEye.xcodeproj`.
3. Xcode ▸ Settings ▸ Accounts → add your Apple ID (a free account is fine).
4. Select the **BirdsEye** target ▸ *Signing & Capabilities* → choose your Personal Team.
   If signing complains about the bundle ID, change it to something unique
   (e.g. `com.<yourname>.birdseye`).
5. On your iPhone: Settings ▸ Privacy & Security ▸ **Developer Mode** → on (reboots).
6. Plug the phone in (or same-Wi-Fi), pick it in Xcode's device menu, hit **Run**.
   First run: on the phone, trust the developer cert under
   Settings ▸ General ▸ VPN & Device Management.
   > Free-account builds expire after 7 days — just hit Run again to refresh.

## Testing without leaving your desk

- **Flight mode** works anywhere: enter a flight number (needs internet once, at lookup
  time), pick a seat side, then either tap **WHEELS UP** and watch it dead-reckon in real
  time, or drag the flight bar to scrub anywhere along the route.
- **Drive mode in the Simulator**: Features ▸ Location ▸ *Freeway Drive* gives you a moving
  GPS track around Cupertino.
- **Drive mode for real**: phone in the car, riding shotgun.

## Architecture (one file each)

| File | Role |
|---|---|
| `Geo.swift` | spherical geodesy: haversine, bearings, great-circle slerp, horizon math |
| `Models.swift` | `FlightRoute` (position/track/altitude at progress), seat sides, offline airport list |
| `FlightLookup.swift` | flight number → route via api.adsbdb.com, IATA→ICAO retry, manual fallback |
| `LocationService.swift` | CoreLocation wrapper (fix + compass heading) |
| `FlightEngine.swift` | 1 Hz state machine: dead reckoning ⊕ GPS fusion, visibility computation |
| `LandmarkDB.swift` | generated from `app/landmarks.js` — 200 curated landmarks |
| `DialView.swift` | the circular dial (Canvas): ticks, cardinals, range rings, window sector, landmarks |
| `OnboardingView.swift` | welcome → flight number / drive → flight briefing + seat side |
| `HUDView.swift` | dial + readouts + wheels-up/scrub/radius controls + Coming Up feed |

Sources are platform-guarded so `swiftc -typecheck` passes on macOS too — CI-checkable
without an iOS SDK. Next up (per docs/SPEC.md): AR mode, route corridor packs, notifications.

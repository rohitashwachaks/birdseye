# Birds Eye 🦅

*"What's that below me?"* — an app that turns the airplane window into a head-up display:
point your phone (or just glance at a compass strip) and see the mountains, cities, borders,
and wonders around you, named, with distance and clock position. Works offline via
GPS-at-the-window plus flight-schedule dead reckoning.

- **[docs/SPEC.md](docs/SPEC.md)** — full product + technical scope (positioning stack,
  visibility math, offline data strategy, UX modes, 0→1 launch plan).
- **[ios/](ios/)** — **the iOS app** (SwiftUI): onboarding (flight number or drive mode) +
  circular compass dial HUD. See [ios/README.md](ios/README.md) to run it on your iPhone.
- **[app/](app/)** — v0 web prototype: the no-camera **compass strip** HUD, in plain HTML/JS.

## Run the prototype

```sh
cd app && python3 -m http.server 4173
# open http://localhost:4173
```

(Any static file server works; there is no build step and no dependency.)

### Modes
- **SIMULATE** — replay a great-circle flight (SFO→JFK, LAX→SCL down the Andes, …) at
  1×/60×/600×, scrub anywhere, and switch between *left window / ahead / right window*
  views. Also includes a 🚗 Palo Alto→SF drive simulation.
- **LIVE GPS (drive mode)** — uses your real position + GPS course while you're driving;
  landmarks within a "discovery radius" appear on the strip and in the Coming Up feed.
  Note: browser geolocation requires `localhost` or HTTPS — for phone-in-car testing,
  serve the `app/` folder from any HTTPS static host (e.g. GitHub Pages) and open it in
  the phone browser.

Landmark data is a curated ~170-entry starter set in `app/landmarks.js` — swap in the
full offline pack pipeline per the spec when this graduates from prototype.

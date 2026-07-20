/* Birds Eye v0 — compass-strip HUD prototype.
   Two modes: SIMULATE (great-circle flight replay) and LIVE GPS (drive mode). */

"use strict";

// ---------- geodesy ----------
const R_KM = 6371;
const rad = d => d * Math.PI / 180;
const deg = r => r * 180 / Math.PI;

function distKm(lat1, lon1, lat2, lon2) {
  const dφ = rad(lat2 - lat1), dλ = rad(lon2 - lon1);
  const a = Math.sin(dφ / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dλ / 2) ** 2;
  return 2 * R_KM * Math.asin(Math.sqrt(a));
}

function bearingDeg(lat1, lon1, lat2, lon2) {
  const φ1 = rad(lat1), φ2 = rad(lat2), dλ = rad(lon2 - lon1);
  const y = Math.sin(dλ) * Math.cos(φ2);
  const x = Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(dλ);
  return (deg(Math.atan2(y, x)) + 360) % 360;
}

// great-circle interpolation (slerp) between two points, f in [0,1]
function gcInterp(a, b, f) {
  const φ1 = rad(a.lat), λ1 = rad(a.lon), φ2 = rad(b.lat), λ2 = rad(b.lon);
  const δ = distKm(a.lat, a.lon, b.lat, b.lon) / R_KM;
  if (δ < 1e-9) return { lat: a.lat, lon: a.lon };
  const A = Math.sin((1 - f) * δ) / Math.sin(δ);
  const B = Math.sin(f * δ) / Math.sin(δ);
  const x = A * Math.cos(φ1) * Math.cos(λ1) + B * Math.cos(φ2) * Math.cos(λ2);
  const y = A * Math.cos(φ1) * Math.sin(λ1) + B * Math.cos(φ2) * Math.sin(λ2);
  const z = A * Math.sin(φ1) + B * Math.sin(φ2);
  return { lat: deg(Math.atan2(z, Math.sqrt(x * x + y * y))), lon: deg(Math.atan2(y, x)) };
}

// horizon distance (km) from an eye/target elevation in meters
const horizonKm = elevM => 3.57 * Math.sqrt(Math.max(elevM, 0));
// signed relative bearing in [-180, 180)
const relBearing = (brg, ref) => ((brg - ref + 540) % 360) - 180;

function clockPos(rel) {
  const h = Math.round(((rel + 360) % 360) / 30) % 12;
  return h === 0 ? 12 : h;
}

const GLYPH = { city: "🏙️", peak: "🏔️", park: "🏞️", water: "🌊", icon: "🗽", wonder: "✨", border: "🛂" };

// ---------- routes ----------
const ROUTES = [
  { id: "sfo-jfk", name: "SFO → JFK · over the Rockies", pts: [{ lat: 37.6213, lon: -122.379 }, { lat: 40.6413, lon: -73.7781 }], altM: 10700, kmh: 870 },
  { id: "sea-mia", name: "SEA → MIA · corner to corner", pts: [{ lat: 47.4502, lon: -122.3088 }, { lat: 25.7959, lon: -80.287 }], altM: 11300, kmh: 870 },
  { id: "lax-scl", name: "LAX → SCL · down the Andes", pts: [{ lat: 33.9416, lon: -118.4085 }, { lat: -33.393, lon: -70.7858 }], altM: 11600, kmh: 890 },
  { id: "lhr-dxb", name: "LHR → DXB · Alps & deserts", pts: [{ lat: 51.47, lon: -0.4543 }, { lat: 25.2532, lon: 55.3657 }], altM: 11000, kmh: 880 },
  { id: "bay-drive", name: "🚗 Palo Alto → SF · drive-mode sim", pts: [{ lat: 37.4419, lon: -122.143 }, { lat: 37.5585, lon: -122.2711 }, { lat: 37.6213, lon: -122.379 }, { lat: 37.7749, lon: -122.4194 }], altM: 20, kmh: 95, drive: true },
];

// precompute leg lengths for multi-point routes
for (const r of ROUTES) {
  r.legs = [];
  r.totalKm = 0;
  for (let i = 0; i < r.pts.length - 1; i++) {
    const d = distKm(r.pts[i].lat, r.pts[i].lon, r.pts[i + 1].lat, r.pts[i + 1].lon);
    r.legs.push(d);
    r.totalKm += d;
  }
}

function routePoint(route, f) {
  f = Math.min(Math.max(f, 0), 1);
  let remaining = f * route.totalKm;
  for (let i = 0; i < route.legs.length; i++) {
    if (remaining <= route.legs[i] || i === route.legs.length - 1) {
      return gcInterp(route.pts[i], route.pts[i + 1], route.legs[i] ? remaining / route.legs[i] : 0);
    }
    remaining -= route.legs[i];
  }
}

// climb/descend ramp over first/last 8% of the route
function routeAlt(route, f) {
  if (route.drive) return route.altM;
  const ramp = Math.min(1, f / 0.08, (1 - f) / 0.08);
  return Math.max(60, route.altM * Math.max(ramp, 0));
}

// ---------- state ----------
const state = {
  mode: "sim",           // sim | live
  lookOffset: 0,         // -90 left window / 0 ahead / +90 right window
  lat: null, lon: null, altM: 0, kmh: 0, heading: 0,
  hasFix: false,
  // sim
  route: ROUTES[0], prog: 0, playing: false, mult: 60, lastTick: null,
  // live
  watchId: null, radiusKm: 100, compassDeg: null,
};

// ---------- landmark selection ----------
function visibleLandmarks() {
  if (!state.hasFix) return [];
  const out = [];
  const horizonSelf = horizonKm(state.altM);
  for (const lm of LANDMARKS) {
    const d = distKm(state.lat, state.lon, lm.lat, lm.lon);
    let maxD;
    if (state.mode === "live" || state.route?.drive) {
      maxD = state.mode === "live" ? state.radiusKm : 100; // discovery radius on the ground
    } else {
      maxD = Math.min(horizonSelf + horizonKm(lm.e), 500);       // line-of-sight, haze-capped
      if (lm.i === 3 && d > 150) continue;                        // local stuff only when close
    }
    if (d > maxD || d < 0.05) continue;
    const brg = bearingDeg(state.lat, state.lon, lm.lat, lm.lon);
    out.push({ lm, d, brg, rel: relBearing(brg, state.heading) });
  }
  out.sort((a, b) => (a.lm.i - b.lm.i) || (a.d - b.d)); // famous first, then near
  return out;
}

// ---------- DOM ----------
const $ = id => document.getElementById(id);
const els = {
  tape: $("tape"), chips: $("chips"), strip: $("strip"), stripEmpty: $("stripEmpty"),
  roAlt: $("roAlt"), roSpd: $("roSpd"), roHdg: $("roHdg"), roHor: $("roHor"), roPos: $("roPos"),
  feedList: $("feedList"), feedEmpty: $("feedEmpty"),
  routeSel: $("routeSel"), playBtn: $("playBtn"), scrub: $("scrub"), progLabel: $("progLabel"),
  simPanel: $("simPanel"), livePanel: $("livePanel"), gpsBtn: $("gpsBtn"), gpsStatus: $("gpsStatus"),
};

const FOV = 90; // strip shows ±90° around look direction

function renderTape(centerBrg, w) {
  let html = "";
  for (let t = 0; t < 360; t += 15) {
    const rel = relBearing(t, centerBrg);
    if (Math.abs(rel) > FOV) continue;
    const x = w / 2 + (rel / FOV) * (w / 2 - 8);
    const major = t % 45 === 0;
    html += `<div class="tick${major ? " major" : ""}" style="left:${x.toFixed(1)}px"></div>`;
    if (major) {
      const names = { 0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW" };
      const label = names[t] ?? String(t).padStart(3, "0");
      html += `<div class="tick-label${names[t] ? " cardinal" : ""}" style="left:${x.toFixed(1)}px">${label}</div>`;
    }
  }
  els.tape.innerHTML = html;
}

function renderChips(items, centerBrg, w) {
  const inView = items
    .map(it => ({ ...it, look: relBearing(it.brg, centerBrg) }))
    .filter(it => Math.abs(it.look) <= FOV);
  // lane layout: famous-first order, 3 lanes, skip when crowded
  const lanes = [[], [], []];
  const placed = [];
  for (const it of inView) {
    const x = w / 2 + (it.look / FOV) * (w / 2 - 12);
    const lane = lanes.findIndex(l => l.every(px => Math.abs(px - x) > 110));
    if (lane === -1) continue;
    lanes[lane].push(x);
    placed.push({ ...it, x, lane });
    if (placed.length >= 9) break;
  }
  els.chips.innerHTML = placed.map(p => `
    <div class="chip${p.lm.i === 1 ? " tier1" : ""}" style="left:${p.x.toFixed(1)}px;top:${p.lane * 42}px">
      <div class="pin"></div>
      <div class="tag">${GLYPH[p.lm.t] ?? "•"} ${p.lm.n}</div>
      <div class="sub">${fmtDist(p.d)}</div>
    </div>`).join("");
  els.stripEmpty.classList.toggle("hidden", placed.length > 0 || !state.hasFix);
}

function fmtDist(km) { return km < 10 ? km.toFixed(1) + " km" : Math.round(km) + " km"; }

function renderFeed(items) {
  const rows = items.slice(0, 12).map(it => {
    const side = Math.abs(it.rel) < 15 ? "▲" : it.rel < 0 ? "◀" : "▶";
    const behind = Math.abs(it.rel) > 100;
    // ETA until the landmark is abeam (along-track closure)
    let eta = "";
    if (state.kmh > 40 && Math.abs(it.rel) < 80) {
      const min = (it.d * Math.cos(rad(it.rel))) / state.kmh * 60;
      if (min >= 1) eta = `~${Math.round(min)} min`;
      else eta = "now";
    }
    return `<li class="feed-item${it.lm.i === 1 ? " tier1" : ""}${behind ? " behind" : ""}">
      <div class="glyph">${GLYPH[it.lm.t] ?? "•"}</div>
      <div class="body">
        <div class="name">${it.lm.n}</div>
        <div class="meta">${fmtDist(it.d)}${it.lm.e >= 1000 ? ` · elev ${it.lm.e} m` : ""}${eta ? ` · ${eta}` : ""}</div>
      </div>
      <div class="clock">${side} ${clockPos(it.rel)} o’clock${behind ? "<small>behind you</small>" : "<small>&nbsp;</small>"}</div>
    </li>`;
  });
  els.feedList.innerHTML = rows.join("");
  els.feedEmpty.classList.toggle("hidden", rows.length > 0);
}

function render() {
  const w = els.strip.clientWidth;
  const centerBrg = (state.heading + state.lookOffset + 360) % 360;
  renderTape(centerBrg, w);
  const items = visibleLandmarks();
  renderChips(items, centerBrg, w);
  renderFeed(items);

  els.roAlt.textContent = state.hasFix ? `${Math.round(state.altM).toLocaleString()} m` : "—";
  els.roSpd.textContent = state.hasFix ? `${Math.round(state.kmh)} km/h` : "—";
  els.roHdg.textContent = state.hasFix ? `${String(Math.round(state.heading)).padStart(3, "0")}°` : "—";
  els.roHor.textContent = !state.hasFix ? "—"
    : state.mode === "live" ? `${state.radiusKm} km`
    : state.route?.drive ? "100 km"
    : `${Math.round(Math.min(horizonKm(state.altM), 500))} km`;
  els.roPos.textContent = state.hasFix ? `${state.lat.toFixed(3)}, ${state.lon.toFixed(3)}` : "—";
}

// ---------- sim engine ----------
function setSimProgress(f) {
  const r = state.route;
  state.prog = Math.min(Math.max(f, 0), 1);
  const p = routePoint(r, state.prog);
  const ahead = routePoint(r, Math.min(state.prog + 0.0005, 1));
  state.lat = p.lat; state.lon = p.lon;
  state.heading = state.prog >= 1 ? state.heading : bearingDeg(p.lat, p.lon, ahead.lat, ahead.lon);
  state.altM = routeAlt(r, state.prog);
  state.kmh = state.playing ? r.kmh : 0;
  state.hasFix = true;
  els.scrub.value = String(Math.round(state.prog * 1000));
  const flownKm = state.prog * r.totalKm;
  const leftMin = state.kmh ? (r.totalKm - flownKm) / r.kmh * 60 : null;
  els.progLabel.textContent =
    `${Math.round(flownKm)} / ${Math.round(r.totalKm)} km` +
    (leftMin != null ? ` · ${Math.round(leftMin)} min to go (at ${state.mult}× time)` : "") +
    (state.prog >= 1 ? " · arrived ✈" : "");
}

function tick(now) {
  if (state.mode === "sim" && state.playing) {
    const dt = state.lastTick ? (now - state.lastTick) / 1000 : 0;
    state.lastTick = now;
    const dKm = state.route.kmh / 3600 * dt * state.mult;
    setSimProgress(state.prog + dKm / state.route.totalKm);
    if (state.prog >= 1) { state.playing = false; els.playBtn.textContent = "▶ FLY"; state.kmh = 0; }
  }
  render();
  requestAnimationFrame(tick);
}

// ---------- live GPS (drive mode) ----------
function startGPS() {
  if (!navigator.geolocation) { els.gpsStatus.textContent = "Geolocation unavailable in this browser."; return; }
  els.gpsStatus.textContent = "Acquiring fix…";
  // iOS compass needs an explicit permission request from a user gesture
  if (window.DeviceOrientationEvent?.requestPermission) {
    DeviceOrientationEvent.requestPermission().catch(() => {});
  }
  window.addEventListener("deviceorientationabsolute", onOrientation);
  window.addEventListener("deviceorientation", onOrientation);
  state.watchId = navigator.geolocation.watchPosition(pos => {
    const c = pos.coords;
    state.lat = c.latitude; state.lon = c.longitude;
    state.altM = c.altitude ?? 0;
    state.kmh = (c.speed ?? 0) * 3.6;
    // heading: GPS course when moving, compass when stopped
    if (c.heading != null && !Number.isNaN(c.heading) && state.kmh > 4) state.heading = c.heading;
    else if (state.compassDeg != null) state.heading = state.compassDeg;
    state.hasFix = true;
    els.gpsStatus.textContent = `Fix ±${Math.round(c.accuracy)} m · ${state.kmh > 4 ? "heading from GPS course" : "stopped — heading from compass"}`;
  }, err => {
    els.gpsStatus.textContent = `GPS error: ${err.message} (needs HTTPS or localhost + location permission)`;
  }, { enableHighAccuracy: true, maximumAge: 1000, timeout: 15000 });
  els.gpsBtn.textContent = "◉ STOP GPS";
}

function stopGPS() {
  if (state.watchId != null) navigator.geolocation.clearWatch(state.watchId);
  state.watchId = null;
  window.removeEventListener("deviceorientationabsolute", onOrientation);
  window.removeEventListener("deviceorientation", onOrientation);
  els.gpsBtn.textContent = "◉ START GPS";
  els.gpsStatus.textContent = "GPS stopped.";
}

function onOrientation(e) {
  if (typeof e.webkitCompassHeading === "number") state.compassDeg = e.webkitCompassHeading;
  else if (e.absolute && e.alpha != null) state.compassDeg = (360 - e.alpha) % 360;
}

// ---------- wiring ----------
function setMode(mode) {
  state.mode = mode;
  $("modeSim").classList.toggle("active", mode === "sim");
  $("modeLive").classList.toggle("active", mode === "live");
  els.simPanel.classList.toggle("hidden", mode !== "sim");
  els.livePanel.classList.toggle("hidden", mode !== "live");
  if (mode === "sim") { stopGPS(); setSimProgress(state.prog); }
  else { state.playing = false; els.playBtn.textContent = "▶ FLY"; state.hasFix = false; state.kmh = 0; }
}

for (const r of ROUTES) {
  const o = document.createElement("option");
  o.value = r.id; o.textContent = r.name;
  els.routeSel.appendChild(o);
}
els.routeSel.addEventListener("change", () => {
  state.route = ROUTES.find(r => r.id === els.routeSel.value);
  state.playing = false; els.playBtn.textContent = "▶ FLY";
  if (state.mode === "sim") setSimProgress(0);
});
els.playBtn.addEventListener("click", () => {
  if (state.prog >= 1) setSimProgress(0);
  state.playing = !state.playing;
  state.lastTick = null;
  els.playBtn.textContent = state.playing ? "❚❚ PAUSE" : "▶ FLY";
  if (!state.playing) state.kmh = 0;
});
els.scrub.addEventListener("input", () => setSimProgress(Number(els.scrub.value) / 1000));
document.querySelectorAll(".spd").forEach(b => b.addEventListener("click", () => {
  document.querySelectorAll(".spd").forEach(x => x.classList.remove("active"));
  b.classList.add("active");
  state.mult = Number(b.dataset.mult);
}));
document.querySelectorAll(".look-btn").forEach(b => b.addEventListener("click", () => {
  document.querySelectorAll(".look-btn").forEach(x => x.classList.remove("active"));
  b.classList.add("active");
  state.lookOffset = Number(b.dataset.look);
}));
$("modeSim").addEventListener("click", () => setMode("sim"));
$("modeLive").addEventListener("click", () => setMode("live"));
els.gpsBtn.addEventListener("click", () => state.watchId == null ? startGPS() : stopGPS());
$("radiusSel").addEventListener("change", e => { state.radiusKm = Number(e.target.value); });

// boot: cue up the first route at its start, paused
setSimProgress(0);
requestAnimationFrame(tick);

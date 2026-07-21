#!/usr/bin/env python3
"""Build a Birds Eye landmark pack from OpenStreetMap.

    python3 scripts/import_landmarks.py --region dfw

Raw OSM cannot be shipped as-is. Measured on real Overpass responses for DFW:
  * man_made=tower is dominated by radio masts (KSKY-AM, KDBN-AM, ...).
  * leisure=stadium without a wikidata tag is high-school football fields.
  * Name matching pulls in sub-features: "White Rock Lake Dog Park",
    "Bank of America Plaza Parking", "Cotton Bowl Circle" (a street).
  * A wikidata tag is a good notability signal but not sufficient — every
    individual Six Flags roller coaster has one.
  * `height` is almost never tagged, so heights come from the region spec.

So this pipeline is: query -> classify -> filter -> dedupe -> curate -> emit.
The region file (scripts/regions/<name>.json) holds all the curation.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
# Overpass rejects a plain body POST with HTTP 406; it wants form-encoded `data=`
# plus a real User-Agent.
USER_AGENT = "BirdsEye/0.1 (landmark pack importer; github.com/rohitashwachaks/birdseye)"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "ios/BirdsEye/BirdsEye/Resources"


# --- Overpass -----------------------------------------------------------------

def build_query(bbox) -> str:
    """One query, several categories. bbox is (south, west, north, east)."""
    b = "{:.4f},{:.4f},{:.4f},{:.4f}".format(*bbox)
    return f"""
[out:json][timeout:180];
(
  nwr["place"~"^(city|town)$"]["name"]["population"]({b});
  nwr["tourism"~"^(attraction|museum|theme_park|zoo|aquarium|viewpoint|gallery)$"]["name"]({b});
  nwr["historic"~"^(monument|memorial|castle|fort|district|building|ruins)$"]["name"]({b});
  nwr["leisure"~"^(stadium|park)$"]["name"]["wikidata"]({b});
  nwr["man_made"~"^(tower|bridge|obelisk|lighthouse)$"]["name"]["wikidata"]({b});
  nwr["building"]["name"]["height"]({b});
  nwr["aeroway"="aerodrome"]["name"]["iata"]({b});
  nwr["natural"="water"]["name"]["wikidata"]({b});
  nwr["amenity"~"^(university|theatre|arts_centre)$"]["name"]["wikidata"]({b});
)
;out center tags;
""".strip()


def _ssl_context():
    """python.org builds on macOS often ship without a usable CA bundle."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def _fetch_urllib(url: str, body: bytes) -> list[dict]:
    req = urllib.request.Request(
        url, data=body,
        headers={"User-Agent": USER_AGENT,
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=200, context=_ssl_context()) as resp:
        return json.loads(resp.read()).get("elements", [])


def _fetch_curl(url: str, query: str) -> list[dict]:
    """Fallback transport: curl uses the system trust store, which always works here."""
    proc = subprocess.run(
        ["curl", "-s", "--max-time", "200", "-A", USER_AGENT,
         "--data-urlencode", f"data={query}", url],
        capture_output=True, check=True,
    )
    return json.loads(proc.stdout).get("elements", [])


def overpass(query: str, retries: int = 2) -> list[dict]:
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for url in OVERPASS_URLS:
        for attempt in range(retries):
            for fetch in (lambda: _fetch_urllib(url, body), lambda: _fetch_curl(url, query)):
                try:
                    return fetch()
                except Exception as exc:  # noqa: BLE001 - try next transport/mirror
                    last_error = exc
            wait = 5 * (attempt + 1)
            print(f"  ! {url} attempt {attempt + 1} failed: {last_error}; retrying in {wait}s",
                  file=sys.stderr)
            time.sleep(wait)
    raise SystemExit(f"All Overpass endpoints failed. Last error: {last_error}")


# --- classification -----------------------------------------------------------

def classify(tags: dict) -> str | None:
    """Map OSM tags onto a Birds Eye LandmarkType, or None to drop."""
    place = tags.get("place")
    if place == "city":
        return "city"
    if place == "town":
        return "town"

    if tags.get("aeroway") == "aerodrome":
        return "airport"
    if tags.get("natural") == "water":
        return "water"
    if tags.get("amenity") == "university":
        return "campus"

    tourism = tags.get("tourism")
    if tourism in ("museum", "gallery"):
        return "museum"
    if tourism in ("attraction", "theme_park", "zoo", "aquarium"):
        return "wonder"
    if tourism == "viewpoint":
        return "icon"

    if tags.get("leisure") == "stadium":
        return "stadium"
    if tags.get("leisure") == "park":
        return "park"

    man_made = tags.get("man_made")
    if man_made == "tower":
        # Radio/TV masts are not landmarks you look for out a car window.
        if tags.get("tower:type") in ("communication", "radio", "lighting", "monitoring"):
            return None
        return "tower"
    if man_made in ("bridge", "obelisk", "lighthouse"):
        return "icon"

    if tags.get("historic"):
        return "icon"
    if tags.get("amenity") in ("theatre", "arts_centre"):
        return "icon"
    if tags.get("building") and tags.get("height"):
        return "icon"
    return None


def parse_height(raw) -> float | None:
    if raw is None:
        return None
    try:
        return float(re.sub(r"[^\d.]", "", str(raw)) or 0) or None
    except ValueError:
        return None


def score_tier(tags: dict, kind: str, height: float | None) -> int:
    """1 = famous, 2 = regional, 3 = local."""
    notable = bool(tags.get("wikidata") or tags.get("wikipedia"))

    if kind in ("city", "town"):
        try:
            pop = int(re.sub(r"[^\d]", "", tags.get("population", "0")) or 0)
        except ValueError:
            pop = 0
        if pop >= 400_000:
            return 1
        if pop >= 90_000:
            return 2
        return 3

    if kind == "airport":
        # Every little airfield has an IATA code; only the big ones are landmarks.
        name = tags.get("name", "")
        if tags.get("iata") and re.search(r"(?i)\binternational\b", name):
            return 1
        return 3

    if kind == "stadium":
        # A wikidata entry says "documented", not "famous" — DFW high-school fields
        # (Cowboys Field, Herman Clark Stadium) all have one. Capacity is objective.
        try:
            capacity = int(re.sub(r"[^\d]", "", tags.get("capacity", "0")) or 0)
        except ValueError:
            capacity = 0
        if capacity >= 40_000:
            return 1
        if capacity >= 12_000 or notable:
            return 2
        return 3

    # A genuine skyscraper: tall *and* written about. Height alone lets mis-tagged
    # OSM data masquerade as a landmark.
    if height and height >= 180 and notable:
        return 1

    # Everything else tops out at 2 from OSM alone. Tier 1 means "you'd point at it from
    # the highway", which is a human judgement — promote via tierOverrides in the region
    # spec rather than trusting tags.
    return 2 if notable else 3


# --- pipeline -----------------------------------------------------------------

def coords(el: dict):
    if "lat" in el and "lon" in el:
        return el["lat"], el["lon"]
    center = el.get("center") or {}
    if "lat" in center:
        return center["lat"], center["lon"]
    return None, None


def normalise(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


# Words too common to distinguish one place from another.
STOP_TOKENS = {
    "the", "of", "at", "and", "de", "el", "la", "a", "an",
    "airport", "international", "field", "park", "lake", "center", "centre",
    "museum", "stadium", "tower", "plaza", "building", "district", "national",
    "historic", "city", "north", "south", "east", "west", "new", "old", "fort",
}


def significant_tokens(name: str) -> set[str]:
    """Distinctive words in a name, for fuzzy duplicate detection."""
    words = re.findall(r"[a-z0-9]+", name.lower())
    return {w for w in words if w not in STOP_TOKENS and len(w) > 2}


def haversine_km(a_lat, a_lon, b_lat, b_lon) -> float:
    r = 6371.0
    dphi = math.radians(b_lat - a_lat)
    dlam = math.radians(b_lon - a_lon)
    x = (math.sin(dphi / 2) ** 2
         + math.cos(math.radians(a_lat)) * math.cos(math.radians(b_lat)) * math.sin(dlam / 2) ** 2)
    return 2 * r * math.asin(min(1, math.sqrt(x)))


def run(spec: dict, out_dir: Path, dry_run: bool) -> int:
    bbox = spec["bbox"]
    blocks = [re.compile(p) for p in spec.get("blockPatterns", [])]
    cat_heights = spec.get("categoryHeights", {})
    height_over = spec.get("heightOverrides", {})
    tier_over = spec.get("tierOverrides", {})
    max_height = float(spec.get("maxPlausibleHeightM", 350))

    print(f"→ querying Overpass for {spec['title']} …")
    elements = overpass(build_query(bbox))
    print(f"  {len(elements)} raw elements")

    candidates, dropped = [], {"unnamed": 0, "unclassified": 0, "blocked": 0, "nocoord": 0}
    for el in elements:
        tags = el.get("tags") or {}
        name = (tags.get("name") or "").strip()
        if not name:
            dropped["unnamed"] += 1
            continue
        if any(b.search(name) for b in blocks):
            dropped["blocked"] += 1
            continue
        kind = classify(tags)
        if kind is None:
            dropped["unclassified"] += 1
            continue
        lat, lon = coords(el)
        if lat is None:
            dropped["nocoord"] += 1
            continue

        # Curated height wins; otherwise trust OSM only within plausible bounds.
        # Real mis-tags seen in DFW: "Dental Care of Texas" at 510 m, "Elora" at 425 m,
        # against a genuine metroplex maximum of 281 m (Bank of America Plaza).
        height = parse_height(height_over.get(name))
        if height is None:
            osm_height = parse_height(tags.get("height"))
            if osm_height is not None and 3 <= osm_height <= max_height:
                height = osm_height
        tier = tier_over.get(name) or score_tier(tags, kind, height)
        if height is None:
            height = float(cat_heights.get(kind, 10))
        elev = parse_height(tags.get("ele")) or 160.0  # DFW plateau default

        candidates.append({
            "name": name, "type": kind, "tier": int(tier),
            "lat": round(lat, 5), "lon": round(lon, 5),
            "heightM": float(height), "elevM": float(elev),
        })

    print(f"  kept {len(candidates)}; dropped {dropped}")

    # Curated extras win over anything OSM returned with the same name.
    extras = spec.get("extra", [])
    extra_names = {normalise(e["name"]) for e in extras}
    candidates = [c for c in candidates if normalise(c["name"]) not in extra_names]
    for e in extras:
        candidates.append({**e, "tier": int(e["tier"]),
                           "heightM": float(e["heightM"]), "elevM": float(e["elevM"])})

    # Dedupe, best tier first so the survivor is the most notable spelling.
    # Three ways two rows can be the same place:
    #   1. identical normalised name
    #   2. nearby (<300 m) and one name contains the other
    #   3. nearby (<3 km) and sharing distinctive word tokens — catches
    #      "DFW International Airport" vs "Dallas/Fort Worth International Airport"
    candidates.sort(key=lambda c: (c["tier"], -c["heightM"]))
    kept: list[dict] = []
    for cand in candidates:
        key = normalise(cand["name"])
        tokens = significant_tokens(cand["name"])
        clash = False
        for k in kept:
            k_key = normalise(k["name"])
            if k_key == key:
                clash = True
                break
            gap = haversine_km(cand["lat"], cand["lon"], k["lat"], k["lon"])
            if gap < 0.3 and (key in k_key or k_key in key):
                clash = True
                break
            # There is only ever one airport/city/town at a given spot, however many
            # ways OSM spells it ("DFW International" vs "Dallas/Fort Worth International").
            if gap < 1.5 and cand["type"] == k["type"] and cand["type"] in ("airport", "city", "town"):
                clash = True
                break
            if gap < 3.0 and cand["type"] == k["type"]:
                shared = tokens & significant_tokens(k["name"])
                if shared and len(shared) >= min(len(tokens), len(significant_tokens(k["name"]))):
                    clash = True
                    break
        if not clash:
            kept.append(cand)

    kept.sort(key=lambda c: (c["tier"], c["name"]))
    for i, landmark in enumerate(kept):
        landmark["id"] = i

    pack = {
        "region": spec["region"],
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "landmarks": kept,
    }

    tiers = {t: sum(1 for k in kept if k["tier"] == t) for t in (1, 2, 3)}
    print(f"  → {len(kept)} landmarks (tier1={tiers[1]} tier2={tiers[2]} tier3={tiers[3]})")

    if dry_run:
        print("  (dry run — nothing written)")
        for landmark in [k for k in kept if k["tier"] == 1][:25]:
            print(f"    T{landmark['tier']} {landmark['name'][:44]:46} "
                  f"{landmark['type']:8} h={landmark['heightM']:.0f}m")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"landmarks-{spec['region']}.json"
    out_path.write_text(json.dumps(pack, indent=1, ensure_ascii=False) + "\n")
    print(f"  wrote {out_path.relative_to(REPO_ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", default="dfw", help="region spec in scripts/regions/")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--dry-run", action="store_true", help="print instead of writing")
    args = ap.parse_args()

    spec_path = REPO_ROOT / "scripts/regions" / f"{args.region}.json"
    if not spec_path.exists():
        raise SystemExit(f"No region spec at {spec_path}")
    return run(json.loads(spec_path.read_text()), args.out, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())

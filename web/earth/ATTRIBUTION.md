# Earth base-map outline data

These vector files are the **base-map cartography** for the Simple Outline
Globe (clean dark globe + light-grey coastline/admin-0 outlines). They are
benign, standard base cartography — NOT the sensitive Countries-data /
protected-area boundary concern (no per-country attributes are surfaced; these
are coastline + admin-0 outline polylines only).

## Source / attribution

- **Natural Earth (public domain)** — https://www.naturalearthdata.com/
- Vector GeoJSON via the public-domain `nvkelso/natural-earth-vector` distribution.
- License: **Public domain** ("Natural Earth is free to use in any type of
  project" — no permission needed, no attribution legally required; we credit
  it as courtesy and good practice).

## Files (coarse 1:110m — mobile/default friendly)

- `ne_110m_coastline.json` — `ne_110m_coastline` (134 line features).
- `ne_110m_admin0_boundary_lines.json` — `ne_110m_admin_0_boundary_lines_land`
  (331 line features).
- `ne_110m_land.json` — `ne_110m_land` (127 land **polygons**). NOT drawn on the
  globe; it is the source geometry for the Layer Geo-Validity land/sea mask
  (Phase 0). Rasterized to two boolean land/sea masks (same public-domain
  source/license as the outlines above) so flow/scalar layers clip to their
  valid domain (wind=global, ocean-currents/SST=ocean, air-quality/forest=land):
  - `assets/earth/mask/land-sea-mask-72x37-v1.json` — legacy 5° grid
    (`tooling/earth/build-land-sea-mask.mjs`); kept for Dart geo-validity + as a
    renderer fallback.
  - `assets/earth/mask/land-sea-mask-720x360-v1.json` — fine 0.5° grid
    (`tooling/scripts/earth/build-land-sea-mask.py`, even-odd scanline) so the
    smooth draped overlays hug the coastline instead of reading as 5° blobs.
- `ne_110m_rivers_lake_centerlines.json` — `ne_110m_rivers_lake_centerlines`
  (13 major-river line centerlines). Drawn as thin water-tone polylines.
- `ne_110m_lakes.json` — `ne_110m_lakes` (24 major-lake outline rings; the source
  polygons are converted to ring **LineStrings** so lakes render through the
  same `addOutlines()` polyline path). Drawn as thin water-tone polylines.

Both water-feature files are produced by `tooling/earth/build-rivers-lakes.mjs`,
which fetches the same public-domain nvkelso distribution, strips properties to a
benign `{featurecla}`, rounds coordinates to 4dp, and converts lake polygons to
ring LineStrings. Vectors only — NOT the bundled `web/cesium` NaturalEarthII
raster (which stays unused; the outline globe is vector-only, no imagery).

Served from the web root (`web/earth/`) and loaded by the Cesium attach helper
(`web/index.html`) as light-grey polylines over a clean deep-ocean globe. No
satellite imagery or terrain tiles are streamed by default. (`ne_110m_land.json`
is a build input for the mask, not a globe overlay.)

A 1:50m desktop refinement is a future option (same loader, larger files);
1:110m is the default for performance on mobile.


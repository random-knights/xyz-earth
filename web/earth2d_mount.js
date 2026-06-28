/*
 * earth2d_mount.js — window.__earth2d shim: ties the standalone d3-geo + Canvas2D
 * renderers (earth2d_scalar/flow/points/projections.js) into a Flutter
 * HtmlElementView host. Mirrors window.__earthCesium's role for the Cesium path.
 *
 * The Dart bridge (earth2d_bridge_web.dart) registers a platform-view factory
 * whose <div id="earth2d-host-..."> this shim fills with a <canvas>, then drives
 * via attach / sync / setProjection / setSpin / setRegion / setLaser /
 * setMyLocation / suspend / resume / detach. A marker click emits a
 * CustomEvent('earth2d-pick') carrying the governed snapshot — exactly like the
 * Cesium 'earth-layer-pick'.
 *
 * COMPOSITE (slot parity with Cesium slice-3): every frame draws ALL THREE slots
 * in z-order — scalar heatmap base -> graticule + coastline -> flow particles
 * (trail-fade) -> point markers/annotations -> region laser -> my-location dot.
 * The scalar field is rasterised to an OFFSCREEN on sync and blitted as the base;
 * the flow trail-fade runs on its OWN offscreen layer (composited over the base,
 * so the fade never wipes the heatmap); points are rasterised to a third
 * offscreen rebuilt only when the geometry (projection/rotation/data) changes.
 *
 * Requires (loaded by index.html BEFORE this file): d3-geo, topojson-client,
 * earth2d_projections.js, earth2d_scalar.js, earth2d_flow.js, earth2d_points.js.
 * Fail-closed throughout: any missing dep / error leaves the host blank, never
 * throws into Flutter.
 */
(function (global) {
  'use strict';

  var DEG = Math.PI / 180;
  var HOSTS = {};
  // Reference vectors (Natural Earth): LAND = coastline polygons (fill + stroke);
  // BORDERS = interior country borders (mesh); RIVERS = 50m river + lake
  // centerlines (item 9, GeoJSON FeatureCollection). Loaded once, fail-soft.
  var LAND = null, BORDERS = null, RIVERS = null, VEC_TRIED = false;

  // ── Solid-globe palette (item 10b) — DEVICE-PASS TUNABLE. A solid dark globe
  // (nullschool benchmark): an opaque ocean fill over the whole sphere, land a
  // touch lighter so continents read, and crisp light coastline / faint country
  // borders. Kept neutral-dark (no blue cast) per the owner's base-colour note;
  // the sphere reads against the black space via the limb outline. The base is
  // OPAQUE and drawn fresh every frame so a rotate never shows transparency gaps
  // and an overlay's missing cells fall back to ocean/land tone, not a black hole.
  var OCEAN_FILL = '#14161b';
  var LAND_FILL = '#20232a';
  var COAST_LINE = 'rgba(200,212,230,0.72)';
  var BORDER_LINE = 'rgba(155,175,205,0.26)';
  // Item 9: rivers in a cool blue, distinct from coast/border greys, kept light
  // enough to read over any overlay yet not compete with the flow animation.
  var RIVER_LINE = 'rgba(120,180,225,0.5)';
  var GRATICULE_LINE = 'rgba(140,160,190,0.09)';
  var SPHERE_OUTLINE = 'rgba(120,150,190,0.5)';

  // SIZE/CENTER PARITY (item 1): the orthographic globe radius as a fraction of
  // the half-min-dimension. The Cesium default camera frames the globe with a
  // small margin; 1.0 == edge-to-edge (the old behaviour). Device-tune this one
  // constant to kill any 2D<->3D size jump. Applied to globe projections only.
  // The Cesium viewer uses its DEFAULT camera (no setView) — Cesium frames the
  // globe with DEFAULT_VIEW_FACTOR 0.5, i.e. it zooms out 1.5x, so the 3D globe
  // fills ~1/1.5 ≈ 0.66 of the viewport. Match that as the 2D default so toggling
  // 2D<->3D shows no size jump. Device-tune this one knob if needed.
  var GLOBE_FILL = 0.66;
  // TIME-BASED auto-spin (deg/SECOND), so the speed is independent of frame rate.
  // The Cesium idle-spin rotates the camera UNIT_Z by 0.001 rad per render frame
  // ≈ 0.06 rad/s ≈ 3.44 deg/s at 60fps; match that. Frame-based spinning looked
  // too slow on 2D because the per-frame scalar re-raster drops the fps (and the
  // old 0.06 deg/FRAME then advances fewer times per second).
  var SPIN_DEG_PER_SEC = 3.6;
  // Wheel-zoom clamp (multiplier on the default framing; 1.0 = the matched size).
  var ZOOM_MIN = 0.5, ZOOM_MAX = 9;
  // Item 1 (readiness gate): after a discrete geometry change — first paint, a
  // projection/zoom rebuild, or the end of an eased region fly-to — hold the
  // animated flow for SETTLE_SEC so the camera/projection is fully caught up
  // before any streamline is drawn (no streaks across a still-moving globe).
  // Then the field FADES IN over FLOW_FADE_SEC (nullschool's gentle reveal).
  var SETTLE_SEC = 0.45;
  var FLOW_FADE_SEC = 0.6;

  // Load the reference vectors. Prefer the BUNDLED countries-110m (carries BOTH
  // the land outline AND country borders) so coastlines/borders always render
  // with no CDN dependency; fall back to the bundled/CDN land-110m (land only)
  // and the countries CDN. Every step is fail-soft — a missing vector just means
  // fewer reference lines, never a throw into Flutter.
  function loadVectors() {
    if (VEC_TRIED) return; VEC_TRIED = true;
    var countryUrls = [
      'assets/assets/earth/vector/countries-110m.json',
      'https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json'
    ];
    var landUrls = [
      'assets/assets/earth/vector/land-110m.json',
      'https://cdn.jsdelivr.net/npm/world-atlas@2/land-110m.json'
    ];
    function applyCountries(w) {
      if (!w || !global.topojson || !w.objects) return false;
      try {
        if (w.objects.land) LAND = global.topojson.feature(w, w.objects.land);
        if (w.objects.countries) {
          BORDERS = global.topojson.mesh(w, w.objects.countries, function (a, b) { return a !== b; });
        }
      } catch (e) { return false; }
      if (LAND || BORDERS) { markAllDirty(); return true; }
      return false;
    }
    function applyLand(w) {
      if (!w || !global.topojson || !w.objects || !w.objects.land) return false;
      try { LAND = global.topojson.feature(w, w.objects.land); } catch (e) { return false; }
      markAllDirty(); return true;
    }
    function tryUrls(urls, i, apply, next) {
      if (i >= urls.length) { if (next) next(); return; }
      try {
        global.fetch(urls[i]).then(function (r) { return r && r.ok ? r.json() : null; })
          .then(function (w) { if (!apply(w)) tryUrls(urls, i + 1, apply, next); })
          .catch(function () { tryUrls(urls, i + 1, apply, next); });
      } catch (e) { tryUrls(urls, i + 1, apply, next); }
    }
    // Countries first (land + borders); if LAND still didn't resolve, fall back
    // to the land-only vector so the coastline renders even without borders.
    tryUrls(countryUrls, 0, applyCountries, function () {
      if (!LAND) tryUrls(landUrls, 0, applyLand, null);
    });
    // Item 9: rivers (Natural Earth 50m, GeoJSON FeatureCollection — already a
    // d3-renderable feature set, no topojson decode). Fail-soft + independent of
    // the land/border load so a missing rivers asset never blocks coastlines.
    var riverUrls = ['assets/assets/earth/vector/rivers-50m-v1.json'];
    tryUrls(riverUrls, 0, function (w) {
      if (!w || !w.features) return false;
      RIVERS = w; markAllDirty(); return true;
    }, null);
  }

  // A late-arriving land vector / scalar mask must repaint even idle hosts.
  function markAllDirty() {
    for (var id in HOSTS) { if (HOSTS.hasOwnProperty(id)) markGeoDirty(HOSTS[id]); }
  }

  // Geometry changed (projection / rotation / new data): the scalar base + the
  // point layer must be re-rasterised, and a repaint scheduled. The scalar's
  // inverse-projection lattice (fieldCache) is now KEYED on the projection /
  // rotation / scale state inside renderField, so it self-invalidates when the
  // rotation changes — no need to null it here. (Nulling forced a full lattice
  // rebuild on EVERY geo tick, even rebuilds where the projection was unchanged;
  // the key lets a settle-rebuild at an unchanged projection skip the inverts.)
  function markGeoDirty(h) {
    h.dirty = true; h.scalarDirty = true; h.pointDirty = true;
  }

  function sizeCanvas(h) {
    var el = h.el;
    var w = Math.max(1, el.clientWidth | 0), ht = Math.max(1, el.clientHeight | 0);
    // PERF (mobile): the flow field is fill-rate bound across 4 stacked canvas
    // layers, so a 2x backing store on a dense phone screen quadruples per-frame
    // pixel work into jank (slow rotate/zoom). Cap the DPR to 1.5 on narrow /
    // phone canvases — still crisp, ~44% fewer backing pixels per layer.
    var dprCap = (w < 600) ? 1.5 : 2;
    var dpr = Math.min(global.devicePixelRatio || 1, dprCap);
    var bw = (w * dpr) | 0, bh = (ht * dpr) | 0;
    if (h.canvas.width !== bw || h.canvas.height !== bh) {
      h.canvas.width = bw; h.canvas.height = bh;
      h.canvas.style.width = w + 'px'; h.canvas.style.height = ht + 'px';
      h.W = bw; h.H = bh;
      h.field.width = bw; h.field.height = bh;
      h.flowLayer.width = bw; h.flowLayer.height = bh;
      h.pointLayer.width = bw; h.pointLayer.height = bh;
      // Scale particle density with canvas CSS area (nullschool-style) so the
      // flow field is richly dense on big globes and lighter on small embeds.
      // CSS px (not backing) so hi-dpr doesn't quadruple the count into jank.
      if (h.flow && h.flow.engine && h.flow.engine.setCount) {
        h.flow.engine.setCount((w * ht / 170) | 0);
      }
      rebuildProjection(h);
      return true;
    }
    return false;
  }

  function rebuildProjection(h) {
    try {
      h.projection = global.Earth2dProjections
        ? global.Earth2dProjections.byId(global.d3, h.projId, h.W, h.H)
        : global.d3.geoOrthographic().scale(Math.min(h.W, h.H) / 2 - 6).translate([h.W / 2, h.H / 2]).clipAngle(90);
      // Size/center parity: shrink globe (limb) projections by GLOBE_FILL so the
      // 2D globe frames like the Cesium default camera. Full-frame world
      // projections (equirectangular/mercator/...) are left at their fit.
      if (h.projection.clipAngle && h.projection.scale && GLOBE_FILL !== 1) {
        try {
          var ca = h.projection.clipAngle();
          if (ca != null && ca <= 150) h.projection.scale(h.projection.scale() * GLOBE_FILL);
        } catch (e) {/* ignore */}
      }
      // Wheel/pinch zoom: scale relative to the default framing (all projections).
      // h.zoom == 1.0 is the default 2D<->3D-matched size.
      if (h.projection.scale && h.zoom && h.zoom !== 1) {
        try { h.projection.scale(h.projection.scale() * h.zoom); } catch (e) {/* ignore */}
      }
      if (h.projection.rotate) h.projection.rotate(h.rotate);
      h.path = global.d3.geoPath(h.projection, h.ctx);
      h.fieldCache = null;
      // Stale screen-space flow trails after a projection change.
      try { h.flowCtx.clearRect(0, 0, h.W, h.H); } catch (e) {}
      for (var i = 0; i < h.flow.engine.ps.length; i++) { h.flow.engine.ps[i].px = null; }
      // Item 1: a projection/zoom rebuild restarts the settle hold + fade-in so
      // the flow doesn't streak across the just-changed geometry.
      h.settleUntil = nowSec() + SETTLE_SEC; h.flowFadeStart = 0;
      markGeoDirty(h);
    } catch (e) {}
  }

  // Angular-distance front-hemisphere test for limb (globe) projections; full-
  // frame projections always return true (their own clip handles visibility).
  function onFront(h, lon, lat) {
    var p = h.projection;
    var r = p && p.rotate ? p.rotate() : null;
    if (!r) return true;
    var clip = p.clipAngle ? p.clipAngle() : null;
    if (clip == null || clip >= 180) return true;
    var lon0 = -r[0], lat0 = -r[1];
    var cosc = Math.sin(lat0 * DEG) * Math.sin(lat * DEG) +
      Math.cos(lat0 * DEG) * Math.cos(lat * DEG) * Math.cos((lon - lon0) * DEG);
    return cosc >= Math.cos((clip || 90) * DEG);
  }

  // ── Offscreen builders ─────────────────────────────────────────────────────

  // Rasterise the scalar overlay into h.field (OPAQUE, domain-masked). Returns
  // false (and leaves scalarReady false) when off / blocked on the land mask.
  // Returns true when the scalar state is fully RESOLVED (rendered, or off), so
  // the caller can clear scalarDirty; false ONLY when blocked on the land mask
  // (caller leaves scalarDirty set so the next frame retries once it loads).
  // CRASH-ISOLATION (lockdown): a single layer's render must never blank the
  // globe. Each layer build/draw below is wrapped so a throw logs ONCE (per
  // layer) and that layer is skipped — the base globe + the other layers keep
  // rendering, and the RAF loop never dies.
  var WARNED = {};
  function layerWarn(layer, e) {
    if (WARNED[layer]) return;
    WARNED[layer] = true;
    try {
      global.console && global.console.warn &&
        global.console.warn('[earth2d] ' + layer + ' render skipped (isolated): ' +
          ((e && e.message) || e));
    } catch (x) {/* ignore */}
  }

  function buildScalarBase(h) {
    var s = h.scalar;
    if (!s.active || !s.grid || !global.Earth2dScalar) {
      // Wipe the offscreen so a turned-off overlay can never bleed stale pixels
      // through a later frame (item 10c — the offscreen-clear root cause).
      h.scalarReady = false;
      try { h.fctx.clearRect(0, 0, h.W, h.H); } catch (e) {}
      return true;
    }
    // Masked (ocean/land) overlays need the land/sea mask; fail-closed until it
    // loads (mirrors Cesium) — retry on the next frame when it arrives.
    var dom = s.domain || (s.grid && s.grid.domain) || 'global';
    if (dom !== 'global' && global.Earth2dScalar.maskReady && !global.Earth2dScalar.maskReady()) {
      h.scalarReady = false; h.maskWait = true; return false;
    }
    h.maskWait = false;
    // Crash-isolated: a throwing overlay render leaves a blank overlay, not a
    // blank globe.
    try {
      h.fctx.clearRect(0, 0, h.W, h.H);
      h.fieldCache = global.Earth2dScalar.renderField(h.fctx, h.W, h.H, h.projection, s.grid, {
        palette: s.palette, valueMin: s.grid.valueMin, valueMax: s.grid.valueMax,
        domain: dom, step: 4, cache: h.fieldCache
      });
      h.scalarReady = true;
    } catch (e) {
      layerWarn('overlay', e);
      h.scalarReady = false;
      try { h.fctx.clearRect(0, 0, h.W, h.H); } catch (x) {/* ignore */}
    }
    return true;
  }

  // Rasterise point markers / annotations into h.pointLayer and capture the hit
  // geometry for click picking. Cached: only rebuilt on geometry/data change.
  function buildPointLayer(h) {
    try { h.pointCtx.clearRect(0, 0, h.W, h.H); } catch (e) {}
    h.hits = [];
    if (h.point.active && h.point.ps && global.Earth2dPoints) {
      // Crash-isolated: a throwing annotation render (e.g. a malformed point set)
      // skips the annotation layer only — never blanks the globe.
      try {
        var rendered = global.Earth2dPoints.render(h.pointCtx, h.projection, h.point.ps, { baseRadius: 5 });
        // Ambient mobility layers (flights/boats) render their dots but expose NO
        // hit geometry — a click never selects a point; it falls through to the
        // lat/long flow probe. Non-trackable governance lock.
        h.hits = (h.point.ps.interactive === false) ? [] : rendered;
      } catch (e) {
        layerWarn('annotation', e);
        h.hits = [];
        try { h.pointCtx.clearRect(0, 0, h.W, h.H); } catch (x) {/* ignore */}
      }
    }
    h.pointReady = true;
  }

  // ── Composite (z-order: scalar -> graticule/coast -> flow -> points ->
  //    region laser -> my-location) ─────────────────────────────────────────
  function composite(h) {
    var ctx = h.ctx, W = h.W, H = h.H, path = h.path;
    if (!path) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, W, H);
    // OPAQUE solid globe (item 10b), drawn FRESH every frame so a rotate never
    // shows transparency gaps (item 10c). The ocean fill covers the whole sphere
    // and the land fill goes UNDER the overlay + boundaries — so an overlay's
    // missing/edge cells fall back to ocean/land tone instead of a black hole.
    ctx.beginPath(); path({ type: 'Sphere' }); ctx.fillStyle = OCEAN_FILL; ctx.fill();
    ctx.save(); ctx.beginPath(); path({ type: 'Sphere' }); ctx.clip();

    // 1) Land base fill (solid; the scalar/boundaries draw over it).
    if (LAND) { ctx.beginPath(); path(LAND); ctx.fillStyle = LAND_FILL; ctx.fill(); }

    // 2) Scalar heatmap overlay — masked to its own domain (ocean overlays paint
    //    only ocean, land/global overlays paint land), drawn over the solid base.
    if (h.scalar.active && h.scalarReady) { ctx.drawImage(h.field, 0, 0); }

    // 3) Graticule (faint).
    ctx.beginPath(); path(global.d3.geoGraticule10());
    ctx.strokeStyle = GRATICULE_LINE; ctx.lineWidth = 0.6; ctx.stroke();

    // 4) Crisp boundaries ON TOP of the overlay so coast + country borders + the
    //    rivers stay legible even under a dense overlay (e.g. BAA) — items 9+10b.
    if (BORDERS) {
      ctx.beginPath(); path(BORDERS);
      ctx.strokeStyle = BORDER_LINE; ctx.lineWidth = 0.55; ctx.stroke();
    }
    // Item 9: rivers ALWAYS on top of every overlay (a single batched path).
    if (RIVERS) {
      ctx.beginPath();
      for (var ri = 0; ri < RIVERS.features.length; ri++) {
        var rf = RIVERS.features[ri];
        if (rf && rf.geometry) path(rf.geometry);
      }
      ctx.strokeStyle = RIVER_LINE; ctx.lineWidth = 0.7; ctx.stroke();
    }
    if (LAND) {
      ctx.beginPath(); path(LAND);
      ctx.strokeStyle = COAST_LINE; ctx.lineWidth = 0.8; ctx.stroke();
    }

    // 5) Flow particles (trail-fade), composited from their own layer.
    if (h.flow.active && h.flowReady) { ctx.drawImage(h.flowLayer, 0, 0); }

    // 6) Point markers / annotations (cached offscreen).
    if (h.point.active && h.pointReady) { ctx.drawImage(h.pointLayer, 0, 0); }

    // 7) Region laser.
    drawRegionLaser(h, ctx, path);
    // 8) My-location dot.
    drawMyLocation(h, ctx);

    ctx.restore();
    // Sphere limb outline.
    ctx.beginPath(); path({ type: 'Sphere' });
    ctx.strokeStyle = SPHERE_OUTLINE; ctx.lineWidth = 1; ctx.stroke();
    // 9) Click-to-inspect ring + readout — UNCLIPPED (the readout box may sit
    //    off the sphere) so it's never cut by the globe clip above.
    drawInspect(h, ctx);
  }

  function nowSec() {
    return (global.performance && global.performance.now ? global.performance.now() : Date.now()) * 0.001;
  }

  // Region laser: trace the region border (animated neon dash) when the laser is
  // on for a non-global region; fall back to a pulsing ring at the centroid when
  // no border polygon was supplied. Border/centroid come from Dart (setRegion) —
  // never copied from the Cesium shim.
  function drawRegionLaser(h, ctx, path) {
    var rg = h.region;
    if (!h.laserOn || !rg || rg.global) return;
    var t = nowSec();
    var a = 0.55 + 0.35 * Math.sin(t * 3);
    if (rg.border && rg.border.length > 2) {
      ctx.save();
      ctx.beginPath(); path({ type: 'Polygon', coordinates: [rg.border] });
      ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(120,230,255,' + a.toFixed(3) + ')';
      try { ctx.setLineDash([8, 6]); ctx.lineDashOffset = -((t * 40) % 14); } catch (e) {}
      ctx.stroke();
      try { ctx.setLineDash([]); } catch (e) {}
      ctx.restore();
    } else if (rg.clat != null && rg.clon != null && onFront(h, rg.clon, rg.clat)) {
      var s = h.projection([rg.clon, rg.clat]);
      if (s && isFinite(s[0]) && isFinite(s[1])) {
        var r = 16 + 6 * Math.sin(t * 3);
        ctx.beginPath(); ctx.arc(s[0], s[1], r, 0, 6.2832);
        ctx.strokeStyle = 'rgba(120,230,255,' + a.toFixed(3) + ')'; ctx.lineWidth = 2; ctx.stroke();
      }
    }
  }

  // My-location neon marker: an expanding sonar pulse ring + a steady halo + a
  // bright centre dot at lat/lon (front hemisphere only). Sized in BACKING px so
  // it reads on hi-dpi.
  function drawMyLocation(h, ctx) {
    var m = h.myLoc;
    if (!m || !onFront(h, m.lon, m.lat)) return;
    var s = h.projection([m.lon, m.lat]);
    if (!s || !isFinite(s[0]) || !isFinite(s[1])) return;
    var dpr = Math.min(global.devicePixelRatio || 1, 2);
    var t = nowSec();
    var pulse = (t % 1.6) / 1.6; // 0..1 expanding ring
    // Expanding fading sonar ring.
    ctx.beginPath();
    ctx.arc(s[0], s[1], (6 + pulse * 22) * dpr, 0, 6.2832);
    ctx.strokeStyle = 'rgba(80,255,180,' + (0.55 * (1 - pulse)).toFixed(3) + ')';
    ctx.lineWidth = 2 * dpr; ctx.stroke();
    // Steady halo ring.
    ctx.beginPath(); ctx.arc(s[0], s[1], 9 * dpr, 0, 6.2832);
    ctx.strokeStyle = 'rgba(80,255,180,0.95)'; ctx.lineWidth = 2.5 * dpr; ctx.stroke();
    // Bright centre dot.
    ctx.beginPath(); ctx.arc(s[0], s[1], 4 * dpr, 0, 6.2832);
    ctx.fillStyle = 'rgba(180,255,225,0.98)'; ctx.fill();
  }

  // ── Click-to-inspect ────────────────────────────────────────────────────────
  // Click a globe point (not a marker) -> a lat/lon ring + an on-canvas readout
  // of the ACTIVE flow layer sampled there (wind / ocean current / waves). The
  // point is stored in lon/lat and re-projected each frame so it tracks rotation.
  var INS_CARD = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  function insCardinal(deg) { return INS_CARD[Math.round(((deg % 360) + 360) % 360 / 45) % 8]; }
  function insLatLon(lat, lon) {
    return Math.abs(lat).toFixed(1) + '°' + (lat >= 0 ? 'N' : 'S') + '  ' +
      Math.abs(lon).toFixed(1) + '°' + (lon >= 0 ? 'E' : 'W');
  }
  // Format one channel line from a flow grid sampled at (lon,lat), or null when
  // the grid is missing. Waves magnitude ≈ significant height (m); wind/current
  // ≈ speed (m/s).
  function insChannel(name, g, lon, lat, unit) {
    if (!g || !global.Earth2dFlow || !global.Earth2dFlow.sampleUV) return null;
    var uv = global.Earth2dFlow.sampleUV(g, lon, lat);
    if (!uv) return null;
    var sp = Math.sqrt(uv[0] * uv[0] + uv[1] * uv[1]);
    var dir = Math.atan2(uv[0], uv[1]) * 180 / Math.PI; // bearing flow moves toward
    return name + ' ' + sp.toFixed(1) + unit + ' ' + insCardinal(dir);
  }
  function inspectAt(h, sx, sy) {
    var ll = (h.projection && h.projection.invert) ? h.projection.invert([sx, sy]) : null;
    if (!ll || !isFinite(ll[0]) || !isFinite(ll[1])) { h.inspect = null; h.dirty = true; return; }
    var lon = ll[0], lat = ll[1];
    var ins = { lon: lon, lat: lat, lines: [] };
    // Item A — up to THREE channels: WIND always (land + ocean); CURRENT and
    // WAVE on OCEAN ONLY, each only if its grid is available. Probe grids are
    // loaded independent of the animate slot; fall back to the active flow grid
    // (legacy single-channel behaviour) when no probe grids are set yet.
    var probe = h.probe || {};
    var activeEng = h.flow.active ? h.flow.engine : null;
    var activeKind = activeEng ? (activeEng.flowKind || 'wind') : null;
    function activeGridFor(kind) {
      return (activeEng && activeKind === kind) ? activeEng.grid : null;
    }
    var windG = probe.wind || activeGridFor('wind');
    var oceanG = probe.ocean || activeGridFor('ocean');
    var wavesG = probe.waves || activeGridFor('waves');
    var onLand = false;
    if (global.Earth2dScalar && global.Earth2dScalar.landFractionAt) {
      try { onLand = global.Earth2dScalar.landFractionAt(lon, lat) > 0.5; } catch (e) {}
    }
    var windLine = insChannel('wind', windG, lon, lat, ' m/s');
    if (windLine) ins.lines.push(windLine);
    if (!onLand) {
      var curLine = insChannel('current', oceanG, lon, lat, ' m/s');
      if (curLine) ins.lines.push(curLine);
      var wavLine = insChannel('waves', wavesG, lon, lat, ' m');
      if (wavLine) ins.lines.push(wavLine);
    }
    h.inspect = ins; h.dirty = true;
  }
  function drawInspect(h, ctx) {
    var ins = h.inspect;
    if (!ins || !onFront(h, ins.lon, ins.lat)) return;
    var s = h.projection([ins.lon, ins.lat]);
    if (!s || !isFinite(s[0]) || !isFinite(s[1])) return;
    var dpr = Math.min(global.devicePixelRatio || 1, 2);
    var gold = 'rgba(255,210,90,';
    // Ring.
    ctx.beginPath(); ctx.arc(s[0], s[1], 9 * dpr, 0, 6.2832);
    ctx.strokeStyle = gold + '0.95)'; ctx.lineWidth = 2 * dpr; ctx.stroke();
    // Crosshair.
    ctx.beginPath();
    ctx.moveTo(s[0] - 15 * dpr, s[1]); ctx.lineTo(s[0] - 4 * dpr, s[1]);
    ctx.moveTo(s[0] + 4 * dpr, s[1]); ctx.lineTo(s[0] + 15 * dpr, s[1]);
    ctx.moveTo(s[0], s[1] - 15 * dpr); ctx.lineTo(s[0], s[1] - 4 * dpr);
    ctx.moveTo(s[0], s[1] + 4 * dpr); ctx.lineTo(s[0], s[1] + 15 * dpr);
    ctx.strokeStyle = gold + '0.9)'; ctx.lineWidth = 1.4 * dpr; ctx.stroke();
    // Readout box: lat/long then each available channel (wind / current / waves).
    var lines = [insLatLon(ins.lat, ins.lon)];
    if (ins.lines && ins.lines.length) lines = lines.concat(ins.lines);
    else if (ins.text) lines.push(ins.text); // legacy single-line fallback
    ctx.save();
    ctx.font = (11 * dpr) + 'px system-ui, -apple-system, sans-serif';
    var pad = 5 * dpr, lh = 14 * dpr, wmax = 0;
    for (var i = 0; i < lines.length; i++) { var m = ctx.measureText(lines[i]).width; if (m > wmax) wmax = m; }
    var bw = wmax + pad * 2, bh = lines.length * lh + pad;
    var x = s[0] + 13 * dpr, y = s[1] - 12 * dpr;
    if (x + bw > h.W) x = s[0] - 13 * dpr - bw;
    if (x < 2) x = 2;
    if (y + bh > h.H) y = h.H - bh - 2; if (y < 2) y = 2;
    ctx.fillStyle = 'rgba(8,12,20,0.82)'; ctx.fillRect(x, y, bw, bh);
    ctx.fillStyle = 'rgba(255,236,190,0.98)'; ctx.textBaseline = 'top';
    for (var j = 0; j < lines.length; j++) ctx.fillText(lines[j], x + pad, y + pad + j * lh);
    ctx.restore();
  }

  // Eased rotate toward h.rotTarget (region centroid / my-location), flyTo-like.
  // Returns true while still moving. Shortest-path in longitude.
  function easeRotate(h) {
    if (!h.rotTarget) return false;
    var cur = h.rotate, tgt = h.rotTarget;
    var dLon = (((tgt[0] - cur[0]) % 360) + 540) % 360 - 180;
    var dLat = tgt[1] - cur[1];
    if (Math.abs(dLon) < 0.25 && Math.abs(dLat) < 0.25) {
      cur[0] = ((tgt[0] + 180) % 360 + 360) % 360 - 180; cur[1] = tgt[1];
      h.rotTarget = null;
      if (h.projection.rotate) h.projection.rotate(cur);
      // Item 1: the fly-to just landed — hold + fade the flow back in so it
      // doesn't streak across the region it was still flying toward.
      h.settleUntil = nowSec() + SETTLE_SEC; h.flowFadeStart = 0;
      markGeoDirty(h); return false;
    }
    cur[0] += dLon * 0.14; cur[1] += dLat * 0.14;
    if (h.projection.rotate) h.projection.rotate(cur);
    markGeoDirty(h);
    return true;
  }

  // Continuous animation needed (vs paint-on-dirty)?
  function isAnimating(h, flowing, easing) {
    return flowing || easing || !!h.myLoc ||
      (h.laserOn && h.region && !h.region.global);
  }

  function frame(h) {
    if (!h.running) { h.raf = 0; return; }
    sizeCanvas(h);
    var easing = easeRotate(h);
    if (h.spin && !h.dragging && !easing) {
      // Spin the SAME visual direction as the Cesium idle-spin (camera UNIT_Z by a
      // negative angle) at a TIME-BASED rate (fps-independent). Drag stays
      // grab-drag (matches Cesium).
      var sNow = nowSec();
      var sDt = h.lastSpinTime ? Math.min(0.1, sNow - h.lastSpinTime) : 0.016;
      h.lastSpinTime = sNow;
      h.rotate[0] = (h.rotate[0] - SPIN_DEG_PER_SEC * sDt + 360) % 360;
      if (h.projection.rotate) h.projection.rotate(h.rotate);
      markGeoDirty(h);
    } else {
      h.lastSpinTime = 0; // reset so resuming spin doesn't jump by the idle gap
    }
    var flowing = h.flow.active && h.flow.grid && global.Earth2dFlow;
    // P2: pause + CLEAR the flow during rotate/zoom so the streamlines vanish
    // instantly (nullschool), then re-animate on release. The base globe (solid
    // sphere + coast) keeps rendering — only the animated layer drops out.
    // ROTATE PAUSE: while the earth+ Rotate toggle auto-spins the globe
    // (h.spin), hold the flow exactly as a drag does — the streamlines clear and
    // only re-fade in once Rotate is switched off (settled). Stops the flow from
    // smearing across the continuously-rotating globe and skips the flow budget
    // for the duration of the spin. Parity with the 3D path (viewer._earthIdleSpin).
    var interacting = h.dragging || h.spin || (nowSec() < h.interactUntil);
    // Item 1 (readiness gate): the flow is HELD until the camera/projection has
    // SETTLED (no in-flight ease, no recent interaction, past the settle hold)
    // AND — for sea-masked kinds (ocean/currents + waves) — until the land/sea
    // mask has loaded, so a streamline can never be drawn across land or a
    // still-moving globe. While held the trail layer is cleared and particle
    // screen-history reset; once cleared it FADES IN via alphaScale.
    var fKind = h.flow.engine.flowKind;
    var fMasked = (fKind === 'ocean' || fKind === 'waves');
    var fMaskOk = !fMasked ||
      !(global.Earth2dScalar && global.Earth2dScalar.maskReady) ||
      global.Earth2dScalar.maskReady();
    var settled = !easing && !interacting && nowSec() >= h.settleUntil;
    if (flowing && settled && fMaskOk) {
      if (!h.flowFadeStart) h.flowFadeStart = nowSec();
      var fadeAlpha = Math.min(1, (nowSec() - h.flowFadeStart) / FLOW_FADE_SEC);
      // Advance the flow trail layer OFF the main canvas (transparent trail-fade).
      // Crash-isolated: a throwing flow step skips the animation layer only.
      try {
        h.flow.engine.setProjection(h.projection);
        h.flow.engine.step(h.flowCtx, h.W, h.H,
          { reducedMotion: h.reducedMotion, alphaScale: fadeAlpha });
        h.flowReady = true;
      } catch (e) {
        layerWarn('animation', e);
        h.flowReady = false;
        try { h.flowCtx.clearRect(0, 0, h.W, h.H); } catch (x) {/* ignore */}
      }
      h.flowWasInteracting = false;
    } else if (flowing) {
      // Held (interacting / settling / mask not yet loaded): drop the field and
      // arm a fresh fade-in for when it resumes.
      if (!h.flowWasInteracting) {
        try { h.flowCtx.clearRect(0, 0, h.W, h.H); } catch (e) {}
        for (var fi = 0; fi < h.flow.engine.ps.length; fi++) { h.flow.engine.ps[fi].px = null; }
        h.flowWasInteracting = true;
      }
      h.flowReady = false; h.flowFadeStart = 0;
      h.dirty = true; // recomposite so the flow is dropped from the frame
    }
    // SCALAR PAUSE (parity with the flow layer above): rebuilding the heatmap
    // re-runs ~1000 inverse-projection samples — far too costly to run on every
    // rotation frame (this was the ~1s/frame spin). While motion is in flight
    // (easing / drag / spin / pre-settle hold) HIDE the scalar: clear its
    // offscreen + drop scalarReady so a stale, now-misaligned raster is never
    // composited. The base sphere + coastline + score ring keep rendering (cheap).
    // Rebuild the heatmap exactly ONCE when motion settles — scalarDirty is still
    // set from the last geo tick, so the settle frame picks it up. On a mask-wait
    // buildScalarBase returns false, leaving scalarDirty set to retry next frame.
    if (h.scalarDirty) {
      if (settled) {
        if (buildScalarBase(h)) { h.scalarDirty = false; h.dirty = true; }
      } else if (h.scalarReady) {
        try { h.fctx.clearRect(0, 0, h.W, h.H); } catch (e) {/* ignore */}
        h.scalarReady = false;
        h.dirty = true; // recomposite so the heatmap drops out of the moving frame
      }
    }
    if (h.pointDirty) { buildPointLayer(h); h.pointDirty = false; }
    if (isAnimating(h, flowing, easing) || h.dirty) {
      // Crash-isolated: a throwing composite (e.g. a bad projection path) must
      // never kill the RAF loop below — the globe stays live, the frame is just
      // skipped.
      try { composite(h); } catch (e) { layerWarn('composite', e); }
      h.dirty = false;
    }
    h.raf = global.requestAnimationFrame(function () { frame(h); });
  }

  function wireInput(h) {
    // down: active single-pointer drag { id, x, y }; null when no finger down.
    // pinch: two-pointer state { id1, x1, y1, id2, x2, y2, dist }; null otherwise.
    var down = null, moved = 0, pinch = null;

    h.canvas.addEventListener('pointerdown', function (e) {
      if (h.inputLocked) return; // overlay open -> globe input frozen (parity w/ Cesium)
      if (pinch) return; // third+ pointer: ignore
      if (down) {
        // Second pointer arrived: switch to pinch mode, cancel the drag.
        var pdx = e.clientX - down.x, pdy = e.clientY - down.y;
        pinch = { id1: down.id, x1: down.x, y1: down.y,
                  id2: e.pointerId, x2: e.clientX, y2: e.clientY,
                  dist: Math.sqrt(pdx * pdx + pdy * pdy) };
        h.dragging = false;
        try { h.canvas.setPointerCapture(e.pointerId); } catch (x) {}
        return;
      }
      down = { id: e.pointerId, x: e.clientX, y: e.clientY }; moved = 0; h.dragging = true;
      h.rotTarget = null; // manual drag cancels any in-flight eased rotate
      try { h.canvas.setPointerCapture(e.pointerId); } catch (x) {}
    });

    h.canvas.addEventListener('pointermove', function (e) {
      if (pinch) {
        // Update whichever finger moved, then scale zoom by the new distance ratio.
        var nx1 = pinch.x1, ny1 = pinch.y1, nx2 = pinch.x2, ny2 = pinch.y2;
        if (e.pointerId === pinch.id1) { nx1 = e.clientX; ny1 = e.clientY; }
        else if (e.pointerId === pinch.id2) { nx2 = e.clientX; ny2 = e.clientY; }
        else return;
        var dx = nx1 - nx2, dy = ny1 - ny2;
        var newDist = Math.sqrt(dx * dx + dy * dy);
        if (pinch.dist > 0 && newDist > 0) {
          var z = h.zoom * (newDist / pinch.dist);
          h.zoom = z < ZOOM_MIN ? ZOOM_MIN : (z > ZOOM_MAX ? ZOOM_MAX : z);
          rebuildProjection(h);
        }
        pinch.x1 = nx1; pinch.y1 = ny1; pinch.x2 = nx2; pinch.y2 = ny2;
        pinch.dist = newDist;
        return;
      }
      if (!down) return;
      var dx = e.clientX - down.x, dy = e.clientY - down.y; moved += Math.abs(dx) + Math.abs(dy);
      h.rotate[0] += dx * 0.4;
      var lat = h.rotate[1] - dy * 0.4; h.rotate[1] = lat > 90 ? 90 : (lat < -90 ? -90 : lat);
      if (h.projection.rotate) h.projection.rotate(h.rotate);
      down.x = e.clientX; down.y = e.clientY; markGeoDirty(h);
    });

    function up(e) {
      if (pinch) {
        if (e.pointerId === pinch.id1 || e.pointerId === pinch.id2) {
          // One finger lifted: keep the remaining pointer as a fresh drag start.
          var rid = e.pointerId === pinch.id1 ? pinch.id2 : pinch.id1;
          var rx  = e.pointerId === pinch.id1 ? pinch.x2  : pinch.x1;
          var ry  = e.pointerId === pinch.id1 ? pinch.y2  : pinch.y1;
          pinch = null;
          down = { id: rid, x: rx, y: ry }; moved = 0; h.dragging = true;
        }
        return;
      }
      if (down && down.id === e.pointerId && moved < 5) {
        var rect = h.canvas.getBoundingClientRect();
        var sx = (e.clientX - rect.left) * (h.W / rect.width);
        var sy = (e.clientY - rect.top) * (h.H / rect.height);
        var hit = (h.point.active && global.Earth2dPoints)
          ? global.Earth2dPoints.hitTest(h.hits, sx, sy) : null;
        if (hit) {
          // Marker pick -> the shared snapshot card (existing path).
          var snap = global.Earth2dPoints.snapshot(hit, h.point.ps);
          try {
            global.dispatchEvent(new global.CustomEvent('earth2d-pick', { detail: snap ? JSON.stringify(snap) : '' }));
          } catch (x) {}
        } else if (h.inspectEnabled !== false) {
          // Click-to-inspect (item A — Target Lat/Long gate): clear any open
          // card, then ring + readout at the point. Skipped when the toggle is
          // off (h.inspectEnabled === false).
          try { global.dispatchEvent(new global.CustomEvent('earth2d-pick', { detail: '' })); } catch (x) {}
          inspectAt(h, sx, sy);
        }
      }
      if (down && down.id === e.pointerId) { down = null; h.dragging = false; }
    }
    h.canvas.addEventListener('pointerup', up);
    h.canvas.addEventListener('pointercancel', function (e) {
      if (pinch && (e.pointerId === pinch.id1 || e.pointerId === pinch.id2)) pinch = null;
      if (down && down.id === e.pointerId) { down = null; h.dragging = false; }
    });
    // WHEEL ZOOM (parity with the Cesium dolly). Exponential toward the globe
    // centre, clamped to [ZOOM_MIN, ZOOM_MAX] of the default 2D<->3D-matched
    // framing. preventDefault so the page doesn't scroll under the globe.
    h.canvas.addEventListener('wheel', function (e) {
      // Overlay box open -> do NOT zoom (and do NOT preventDefault) so the wheel
      // falls through to the Flutter box's own scroll. The native-canvas wheel
      // otherwise bypasses the Flutter freeze barrier (parity w/ Cesium's
      // setCameraInputsEnabled(false)).
      if (h.inputLocked) return;
      try { e.preventDefault(); } catch (x) {}
      // P2: keep the flow paused/cleared through a continuous zoom (no pointerup
      // ends a wheel), resuming ~220ms after the last tick.
      h.interactUntil = nowSec() + 0.22;
      var f = Math.exp(-(e.deltaY || 0) * 0.0015);
      var z = h.zoom * f;
      h.zoom = z < ZOOM_MIN ? ZOOM_MIN : (z > ZOOM_MAX ? ZOOM_MAX : z);
      rebuildProjection(h);
    }, { passive: false });
  }

  global.__earth2d = {
    attach: function (hostId) {
      try {
        var el = global.document.getElementById(hostId);
        if (!el) return 'no-element';
        if (HOSTS[hostId]) return 'attached';
        if (!global.d3) return 'no-d3';
        var canvas = global.document.createElement('canvas');
        canvas.style.cssText = 'width:100%;height:100%;display:block;touch-action:none;cursor:grab';
        el.appendChild(canvas);
        var h = {
          el: el, canvas: canvas, ctx: canvas.getContext('2d'),
          field: global.document.createElement('canvas'), fctx: null,
          flowLayer: global.document.createElement('canvas'), flowCtx: null,
          pointLayer: global.document.createElement('canvas'), pointCtx: null,
          projId: 'orthographic', rotate: [0, -10], zoom: 1, projection: null, path: null,
          W: 1, H: 1, fieldCache: null,
          dirty: true, scalarDirty: true, pointDirty: true,
          scalarReady: false, flowReady: false, pointReady: false, maskWait: false,
          running: true, dragging: false, spin: false, reducedMotion: false, raf: 0,
          rotTarget: null, inputLocked: false,
          // P2: flow pauses + clears during rotate/zoom, resumes on release.
          // interactUntil debounces the wheel (no pointerup ends a zoom).
          interactUntil: 0, flowWasInteracting: false,
          // Item 1 (readiness gate): hold the flow until the geometry settles,
          // then fade it in. settleUntil seeded below after the first projection.
          settleUntil: 0, flowFadeStart: 0,
          scalar: { active: false, grid: null, palette: 'mag', domain: 'global' },
          flow: { active: false, grid: null, engine: global.Earth2dFlow ? global.Earth2dFlow.create({ count: 2600 }) : { ps: [], setProjection: function () {}, setGrid: function () {}, step: function () {} } },
          point: { active: false, ps: null },
          region: null, laserOn: false, myLoc: null,
          inspect: null, // click-to-inspect: {lon,lat,lines[]} at a clicked point
          inspectEnabled: true, // item A — Target Lat/Long gate (default ON)
          probe: null, // item A — {wind,ocean,waves} grids sampled by the readout
          hits: []
        };
        h.fctx = h.field.getContext('2d');
        h.flowCtx = h.flowLayer.getContext('2d');
        h.pointCtx = h.pointLayer.getContext('2d');
        HOSTS[hostId] = h;
        loadVectors();
        if (global.Earth2dScalar && global.Earth2dScalar.loadLandMask) {
          try { global.Earth2dScalar.loadLandMask(); } catch (e) {}
        }
        sizeCanvas(h);
        rebuildProjection(h);
        wireInput(h);
        frame(h);
        return 'attached';
      } catch (e) { return 'error'; }
    },
    sync: function (hostId, renderer, payloadJson) {
      try {
        var h = HOSTS[hostId]; if (!h) return;
        var p = typeof payloadJson === 'string' ? JSON.parse(payloadJson) : payloadJson;
        if (renderer === 'scalar') {
          h.scalar.active = !!(p && p.active && p.grid);
          h.scalar.grid = p && p.grid ? p.grid : null;
          h.scalar.palette = (p && p.palette) || (p && p.grid && p.grid.palette) || 'mag';
          h.scalar.domain = (p && p.domain) || (p && p.grid && p.grid.domain) || 'global';
          h.fieldCache = null; h.scalarDirty = true; h.dirty = true;
        } else if (renderer === 'flow') {
          var g = p && p.grid ? p.grid : null;
          var wasActive = h.flow.active;
          h.flow.active = !!(p && p.animate && g);
          h.flow.grid = g;
          if (g && h.flow.engine.setGrid) h.flow.engine.setGrid(g, (p && p.kind) || 'wind');
          // Clear stale trails when flow turns OFF (or the field changes) so a
          // re-enable doesn't flash the previous layer's frozen trails.
          if (!h.flow.active && wasActive) { try { h.flowCtx.clearRect(0, 0, h.W, h.H); } catch (e) {} h.flowReady = false; }
          h.dirty = true;
        } else if (renderer === 'point') {
          h.point.active = !!(p && p.active && p.points && p.points.length);
          h.point.ps = p || null;
          h.pointDirty = true; h.dirty = true;
        }
      } catch (e) {}
    },
    setProjection: function (hostId, projId) {
      var h = HOSTS[hostId]; if (!h) return;
      h.projId = projId || 'orthographic'; rebuildProjection(h);
    },
    setSpin: function (hostId, on) { var h = HOSTS[hostId]; if (h) { h.spin = !!on; h.dirty = true; } },
    // Item A — Target Lat/Long: gate the click-to-inspect readout. Clearing it
    // also drops any open readout so toggling OFF removes the ring immediately.
    setInspectEnabled: function (hostId, on) {
      var h = HOSTS[hostId];
      if (h) { h.inspectEnabled = on !== false; if (!h.inspectEnabled) h.inspect = null; h.dirty = true; }
    },
    // Item A — Target Lat/Long: the wind/current/wave probe grids the readout
    // samples (independent of the animate slot). payload = {wind,ocean,waves}.
    setProbeGrids: function (hostId, payloadJson) {
      var h = HOSTS[hostId]; if (!h) return;
      try {
        var p = typeof payloadJson === 'string' ? JSON.parse(payloadJson) : payloadJson;
        h.probe = {
          wind: (p && p.wind) || null,
          ocean: (p && p.ocean) || null,
          waves: (p && p.waves) || null
        };
        h.dirty = true;
      } catch (e) {}
    },
    // Freeze user camera input (wheel-zoom + drag) while an earth+ overlay box is
    // open — parity with Cesium setCameraInputsEnabled(false). Programmatic
    // rotate/spin/region focus continue; only user wheel/drag are gated.
    setInteractive: function (hostId, interactive) { var h = HOSTS[hostId]; if (h) { h.inputLocked = !interactive; } },
    // Region focus: {id, centroidLat, centroidLon, border:[[lon,lat],...]|null,
    // global:bool, rotate:bool}. Eased-rotates to the centroid when rotate!=false
    // and not global; the laser (setLaser) traces the border / pulses the
    // centroid. lat/lon come from Dart — never the Cesium REGION_BORDERS shim.
    setRegion: function (hostId, regionJson) {
      try {
        var h = HOSTS[hostId]; if (!h) return;
        var r = typeof regionJson === 'string' ? JSON.parse(regionJson) : regionJson;
        if (!r || r.global || r.id === 'global' || r.centroidLat == null || r.centroidLon == null) {
          h.region = r ? { global: true, id: r.id } : null;
          h.rotTarget = null; h.dirty = true; return;
        }
        h.region = {
          global: false, id: r.id, clat: r.centroidLat, clon: r.centroidLon,
          border: (r.border && r.border.length > 2) ? r.border : null
        };
        if (r.rotate !== false) h.rotTarget = [-r.centroidLon, -r.centroidLat];
        h.dirty = true;
      } catch (e) {}
    },
    setLaser: function (hostId, on) { var h = HOSTS[hostId]; if (h) { h.laserOn = !!on; h.dirty = true; } },
    // My-location: {lat, lon, rotate:bool} or null. Neon dot + optional rotate.
    setMyLocation: function (hostId, locJson) {
      try {
        var h = HOSTS[hostId]; if (!h) return;
        var m = typeof locJson === 'string' ? JSON.parse(locJson) : locJson;
        if (!m || m.lat == null || m.lon == null) { h.myLoc = null; h.dirty = true; return; }
        h.myLoc = { lat: m.lat, lon: m.lon };
        if (m.rotate) h.rotTarget = [-m.lon, -m.lat];
        h.dirty = true;
      } catch (e) {}
    },
    suspend: function (hostId) { var h = HOSTS[hostId]; if (h) { h.running = false; } },
    resume: function (hostId) {
      var h = HOSTS[hostId]; if (h && !h.running) { h.running = true; h.dirty = true; if (!h.raf) frame(h); }
    },
    detach: function (hostId) {
      var h = HOSTS[hostId]; if (!h) return;
      h.running = false; if (h.raf) { try { global.cancelAnimationFrame(h.raf); } catch (e) {} }
      try { if (h.canvas && h.canvas.parentNode) h.canvas.parentNode.removeChild(h.canvas); } catch (e) {}
      delete HOSTS[hostId];
    }
  };
})(typeof self !== 'undefined' ? self : this);

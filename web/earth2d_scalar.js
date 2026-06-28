/*
 * earth2d_scalar.js — 2D-canvas SCALAR/heatmap renderer (north-star track, thin proof).
 *
 * The ratified north-star: RETIRE CESIUM -> full 2D-canvas renderer (nullschool/
 * cambecc architecture). This module renders an `earth.scalarfield.v1` grid
 * per-pixel onto a 2D <canvas> under ANY injected d3-geo projection (orthographic
 * for the thin proof; the same code serves all 8 projections at build-out).
 *
 * It MIRRORS — byte-faithfully — the palette LUT + bilinear grid sample + alpha
 * curve of the LIVE web/earth_scalar_field.js (Agent A). It NEVER imports or edits
 * Cesium or any Agent-A file; it is a file-disjoint parallel port. A lock-step
 * golden test (build-out) guards palette drift.
 *
 * KEY DIFFERENCE FROM THE CESIUM PATH (and why this is NOT the "superseded raster"):
 * the Cesium renderer builds a projection-INDEPENDENT equirect texture and lets
 * the GPU project it onto the sphere. Here the CPU owns the projection: per output
 * pixel we projection.invert([x,y]) -> [lon,lat] -> sample. That is precisely the
 * ratified nullschool/cambecc design. The "do-not-reintroduce raster" lesson was
 * Cesium-limb-specific and does not apply to a CPU-projected 2D canvas.
 *
 * MAIN RISK = CPU per-pixel reprojection. Mitigation here: a DISTORTION-GRID cache
 * — invert is evaluated on a coarse lattice (every `step` px) and lon/lat are
 * bilerped between nodes; cells that touch the globe limb (a null corner) fall
 * back to exact per-pixel invert so the edge stays crisp. Pair with a Web Worker
 * (build-out) so rotate/zoom stays 60fps.
 */
(function (global) {
  'use strict';

  // ---- Palette ramps — byte-faithful with web/earth_scalar_field.js PALETTES
  //      and EarthRendererPalettes (Dart). t in 0..1 -> [r,g,b]. -------------
  var PALETTES = {
    aqi: [
      [0.0, [0, 228, 0]], [0.25, [255, 255, 0]], [0.5, [255, 126, 0]],
      [0.75, [255, 0, 0]], [1.0, [143, 63, 151]]
    ],
    thermal: [
      [0.0, [27, 12, 64]], [0.12, [32, 48, 192]], [0.27, [0, 180, 210]],
      [0.42, [40, 180, 90]], [0.56, [235, 220, 60]], [0.70, [240, 140, 30]],
      [0.82, [220, 40, 30]], [0.92, [200, 60, 140]], [1.0, [250, 240, 245]]
    ],
    fire: [
      [0.0, [255, 245, 150]], [0.4, [255, 150, 40]], [0.7, [225, 50, 20]],
      [1.0, [140, 12, 8]]
    ],
    veg: [
      [0.0, [90, 60, 16]], [0.3, [156, 122, 40]], [0.55, [200, 200, 75]],
      [0.78, [90, 170, 50]], [1.0, [10, 110, 30]]
    ],
    mag: [
      [0.0, [10, 10, 40]], [0.35, [40, 60, 140]], [0.6, [40, 120, 200]],
      [0.8, [50, 200, 210]], [1.0, [230, 250, 255]]
    ],
    violet: [
      [0.0, [22, 6, 48]], [0.35, [90, 30, 140]], [0.65, [170, 70, 200]],
      [0.85, [220, 150, 240]], [1.0, [245, 225, 255]]
    ],
    teal: [
      [0.0, [4, 32, 36]], [0.4, [16, 110, 110]], [0.7, [30, 180, 165]],
      [1.0, [150, 250, 225]]
    ],
    ember: [
      [0.0, [40, 18, 4]], [0.4, [160, 80, 18]], [0.7, [220, 140, 30]],
      [1.0, [255, 224, 140]]
    ],
    // A3 (cleanup): bright single-hue CYAN for datacenters — distinct from mag
    // (blue, biodiversity) and teal (green-teal, protected areas).
    cyan: [
      [0.0, [6, 28, 42]], [0.4, [12, 120, 150]], [0.7, [34, 196, 212]],
      [1.0, [150, 238, 246]]
    ],
    // CAPE convective-instability ramp (calm blue → green → amber → red → magenta).
    storm: [
      [0.0, [20, 40, 110]], [0.3, [30, 150, 140]], [0.5, [150, 200, 60]],
      [0.7, [240, 150, 30]], [0.85, [220, 40, 30]], [1.0, [180, 30, 140]]
    ],
    // Light-blue throughout — glacier point markers (T1 E).
    ice: [
      [0.0, [120, 180, 230]], [0.5, [160, 210, 240]], [1.0, [210, 238, 252]]
    ]
  };

  function paletteColor(id, t) {
    var stops = PALETTES[id] || PALETTES.mag;
    if (t <= stops[0][0]) return stops[0][1];
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i][0]) {
        var a = stops[i - 1], b = stops[i];
        var f = (t - a[0]) / (b[0] - a[0] || 1);
        return [
          Math.round(a[1][0] + (b[1][0] - a[1][0]) * f),
          Math.round(a[1][1] + (b[1][1] - a[1][1]) * f),
          Math.round(a[1][2] + (b[1][2] - a[1][2]) * f)
        ];
      }
    }
    return stops[stops.length - 1][1];
  }

  // 256-entry RGB lookup so the per-pixel build stays cheap.
  var _luts = {};
  function paletteLut(id) {
    if (_luts[id]) return _luts[id];
    var lut = new Uint8Array(256 * 3);
    for (var k = 0; k < 256; k++) {
      var rgb = paletteColor(id, k / 255);
      lut[k * 3] = rgb[0]; lut[k * 3 + 1] = rgb[1]; lut[k * 3 + 2] = rgb[2];
    }
    _luts[id] = lut;
    return lut;
  }

  // ---- Land/sea DOMAIN MASK — mirrors web/earth_scalar_field.js. ------------
  // The scalar grids are GLOBAL-filled (e.g. SST has values on land, AQI on
  // ocean), so the overlay must be masked to its valid medium (SST ocean, AQI/
  // forest land) or it bleeds across coastlines. Same 0.5deg mask the live
  // renderer uses, sampled bilinearly so the coast feathers.
  var LAND_MASK = null, MASK_TRIED = false;
  function loadLandMask() {
    if (MASK_TRIED) return; MASK_TRIED = true;
    var urls = [
      'assets/assets/earth/mask/land-sea-mask-720x360-v1.json',
      'earth/mask/land-sea-mask-720x360-v1.json',
      'assets/assets/earth/mask/land-sea-mask-72x37-v1.json',
      'earth/mask/land-sea-mask-72x37-v1.json'
    ];
    function attempt(k) {
      if (k >= urls.length || LAND_MASK) return;
      try {
        global.fetch(urls[k]).then(function (r) {
          if (!r || !r.ok) throw new Error('http'); return r.json();
        }).then(function (m) {
          if (m && m.land && m.nx && m.land.length === m.nx * m.ny) { LAND_MASK = m; }
          else { attempt(k + 1); }
        }).catch(function () { attempt(k + 1); });
      } catch (e) { attempt(k + 1); }
    }
    attempt(0);
  }

  function landFractionAt(lon, lat) {
    var m = LAND_MASK; if (!m) return -1;
    var fx = (lon - m.lon0) / m.dlon, fy = (lat - m.lat0) / m.dlat;
    var i0 = Math.floor(fx), j0 = Math.floor(fy);
    var tx = fx - i0, ty = fy - j0, i1 = i0 + 1, j1 = j0 + 1;
    i0 = ((i0 % m.nx) + m.nx) % m.nx; i1 = ((i1 % m.nx) + m.nx) % m.nx;
    if (j0 < 0) j0 = 0; else if (j0 > m.ny - 1) j0 = m.ny - 1;
    if (j1 < 0) j1 = 0; else if (j1 > m.ny - 1) j1 = m.ny - 1;
    var a = m.land[j0 * m.nx + i0], b = m.land[j0 * m.nx + i1];
    var c = m.land[j1 * m.nx + i0], d = m.land[j1 * m.nx + i1];
    var top = a + (b - a) * tx, bot = c + (d - c) * tx;
    return top + (bot - top) * ty;
  }
  function smoothstep(e0, e1, x) {
    var t = (x - e0) / (e1 - e0 || 1); if (t < 0) t = 0; else if (t > 1) t = 1;
    return t * t * (3 - 2 * t);
  }
  // Domain visibility 0..1 at (lon,lat): 1 in-domain, 0 out, feathered at coast.
  // 'global' is always 1; masked domains fail-closed (0) until the mask loads.
  function domainAlpha(domain, lon, lat) {
    if (!domain || domain === 'global') return 1;
    var lf = landFractionAt(lon, lat);
    if (lf < 0) return 0; // mask not loaded yet -> fail-closed (mirrors Cesium)
    var land = smoothstep(0.35, 0.65, lf);
    if (domain === 'ocean') return 1 - land;
    return land; // land + land-coastal
  }

  // ── PER-LAYER ALPHA POLICY (FIX-1) — byte-faithful with the Cesium renderer
  //    (web/earth_scalar_field.js): identical constants + gate + classifier. ────
  // NULLSCHOOL RULE: geography always shows through. CONTINUOUS fields (SST, air,
  // forest, …) fill at domainMask * CONT_ALPHA (< 0.85) so the base + the
  // coastline/border vectors (earth2d_mount.js draws them ON TOP) read through.
  // SPARSE / ALERT fields (NOAA Coral Reef Watch BLEACHING ALERT, 0-4; waves) are
  // VALUE-GATED: no-stress cells go transparent, only elevated values highlight.
  // Classification is DATA-DRIVEN (mostly-floor in-domain field — BAA is 89%, the
  // continuous fields <5%) OR honest alert label/units — so BAA (whose asset
  // carries no usable label/units/domain) can't fall through to "opaque blanket".
  var ALERT_GATE_LO = 0.12; // (1a) tightened: only clearly-elevated alert cells start to show
  var ALERT_GATE_HI = 0.50; // (1a) tightened: BAA level-1 "watch" fades; level-2+ highlights
  // Item 6 (nullschool parity): continuous overlays fill TRANSLUCENT so the
  // land/ocean base + the coastline / admin-0 border / graticule vectors (drawn
  // ON TOP) clearly read through — matching nullschool + the approved mock
  // (~0.42-0.55). Lower than the old 0.8 "no-bleed" fill, which buried geography.
  // Item 7 (nullschool BAA parity, lock-step with web/earth_scalar_field.js): cap
  // the SPARSE/ALERT fill so even a full-strength bleaching-alert cell stays
  // SEMI-TRANSPARENT (geography + borders read through).
  var ALERT_MAX_ALPHA = 0.72;
  var CONT_ALPHA = 0.55;    // masked continuous overlay (SST etc.) fill alpha
  // GLOBAL continuous fields (Particulates PM2.5, Chemistry NO2 — domain
  // 'global', no clear off-domain half like SST) fill even LIGHTER so the
  // full-sphere fill never blankets land/ocean or the geography vectors.
  var CONT_ALPHA_GLOBAL = 0.42;
  var SPARSE_MIN_FRACTION = 0.5; // in-domain at-floor fraction that flags a sparse field
  function isAlertSparseLayer(label, units) {
    var u = ('' + (units || '')).toLowerCase();
    var l = ('' + (label || '')).toLowerCase();
    return u.indexOf('alert') >= 0 || l.indexOf('alert') >= 0 ||
      l.indexOf('bleaching') >= 0;
  }
  function alertGate(t) { return smoothstep(ALERT_GATE_LO, ALERT_GATE_HI, t); }
  // Fraction of IN-DOMAIN finite cells at/near the value floor -> SPARSE when
  // high. One cheap pass over the coarse grid, memoized on the grid object.
  function isSparseField(grid, domain) {
    if (!grid || !grid.values) return false;
    if (grid.__r1sparse !== undefined) return grid.__r1sparse;
    var vmin = grid.valueMin, vmax = grid.valueMax;
    var eps = Math.abs((vmax - vmin) || 1) * 0.01;
    var nx = grid.nx, ny = grid.ny, vals = grid.values;
    var nIn = 0, nMin = 0;
    for (var j = 0; j < ny; j++) {
      var lat = grid.lat0 + j * grid.dlat;
      for (var i = 0; i < nx; i++) {
        var v = vals[j * nx + i];
        if (v == null || isNaN(v)) continue;
        if (domainAlpha(domain, grid.lon0 + i * grid.dlon, lat) < 0.5) continue;
        nIn++;
        if (Math.abs(v - vmin) <= eps) nMin++;
      }
    }
    grid.__r1sparse = nIn > 0 && (nMin / nIn) >= SPARSE_MIN_FRACTION;
    return grid.__r1sparse;
  }
  function maskReady() { return !!LAND_MASK; }
  try { loadLandMask(); } catch (e) {/* ignore */}

  // ---- Bilinear sample of an earth.scalarfield.v1 grid at (lon,lat). ---------
  //      lon wraps; lat clamps; NaN/null neighbours are dropped from the blend;
  //      all-missing -> null. Mirrors the live renderer's _sampleData exactly.
  function sampleGrid(grid, lon, lat) {
    var nx = grid.nx, ny = grid.ny, vals = grid.values;
    var fx = (lon - grid.lon0) / grid.dlon;
    var fy = (lat - grid.lat0) / grid.dlat;
    var i0 = Math.floor(fx), j0 = Math.floor(fy);
    var tx = fx - i0, ty = fy - j0;
    var i1 = i0 + 1, j1 = j0 + 1;
    i0 = ((i0 % nx) + nx) % nx;
    i1 = ((i1 % nx) + nx) % nx;
    if (j0 < 0) j0 = 0; else if (j0 > ny - 1) j0 = ny - 1;
    if (j1 < 0) j1 = 0; else if (j1 > ny - 1) j1 = ny - 1;
    var va = vals[j0 * nx + i0], vb = vals[j0 * nx + i1];
    var vc = vals[j1 * nx + i0], vd = vals[j1 * nx + i1];
    var wa = (va == null || isNaN(va)) ? 0 : (1 - tx) * (1 - ty);
    var wb = (vb == null || isNaN(vb)) ? 0 : tx * (1 - ty);
    var wc = (vc == null || isNaN(vc)) ? 0 : (1 - tx) * ty;
    var wd = (vd == null || isNaN(vd)) ? 0 : tx * ty;
    var wsum = wa + wb + wc + wd;
    if (wsum <= 0) return null;
    return (wa * va + wb * vb + wc * vc + wd * vd) / wsum;
  }

  // Item 8: NEAREST-cell sample (crisp choropleth edges, no bilinear blend).
  function sampleGridNearest(grid, lon, lat) {
    var nx = grid.nx, ny = grid.ny, vals = grid.values;
    var i = Math.round((lon - grid.lon0) / grid.dlon); i = ((i % nx) + nx) % nx;
    var j = Math.round((lat - grid.lat0) / grid.dlat);
    if (j < 0) j = 0; else if (j > ny - 1) j = ny - 1;
    var v = vals[j * nx + i];
    return (v == null || isNaN(v)) ? null : v;
  }
  // Item 8: snap a 0..1 value to one of `n` discrete choropleth classes.
  function quantize(t, n) {
    if (n < 2) return t;
    var k = Math.floor(t * n); if (k > n - 1) k = n - 1;
    return k / (n - 1);
  }

  function unwrapLon(l, base) {
    while (l - base > 180) l -= 360;
    while (l - base < -180) l += 360;
    return l;
  }

  // Identity key for the inverse lattice: it depends ONLY on the projection's
  // rotation / scale / translate plus the canvas size + step. Rounded so float
  // churn on an identical view doesn't defeat the cache. When this key is
  // unchanged the lattice can be reused verbatim — skipping the ~1000 invert()
  // calls — even though the heatmap data/palette may have changed.
  function inverseGridKey(projection, w, h, step) {
    var r = projection.rotate ? projection.rotate() : [0, 0, 0];
    var s = projection.scale ? projection.scale() : 1;
    var t = projection.translate ? projection.translate() : [0, 0];
    return r[0].toFixed(2) + ',' + r[1].toFixed(2) + ',' + ((r[2] || 0)).toFixed(2) +
      '|' + s.toFixed(2) + '|' + t[0].toFixed(1) + ',' + t[1].toFixed(1) +
      '|' + w + 'x' + h + '|' + step;
  }

  // Build the coarse inverse lattice for a projection over a w x h canvas.
  function buildInverseGrid(projection, w, h, step) {
    var cols = Math.ceil(w / step) + 1;
    var rows = Math.ceil(h / step) + 1;
    var lon = new Float64Array(cols * rows);
    var lat = new Float64Array(cols * rows);
    var ok = new Uint8Array(cols * rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        var idx = r * cols + c;
        var ll = projection.invert ? projection.invert([c * step, r * step]) : null;
        if (ll && isFinite(ll[0]) && isFinite(ll[1])) {
          lon[idx] = ll[0]; lat[idx] = ll[1]; ok[idx] = 1;
        } else { ok[idx] = 0; }
      }
    }
    return { cols: cols, rows: rows, step: step, lon: lon, lat: lat, ok: ok };
  }

  /**
   * Render `grid` into the 2D context `ctx` (w x h) under `projection`.
   * opts: { palette, valueMin, valueMax, step, alphaFloor, alphaGain, grid:cache }
   * Out-of-globe pixels are left transparent. Returns the inverse-grid cache so a
   * caller can reuse it across frames where the projection is unchanged.
   */
  function renderField(ctx, w, h, projection, grid, opts) {
    opts = opts || {};
    var palette = opts.palette || grid.palette || 'mag';
    var vmin = (opts.valueMin != null) ? opts.valueMin : grid.valueMin;
    var vmax = (opts.valueMax != null) ? opts.valueMax : grid.valueMax;
    var span = (vmax - vmin) || 1;
    var lut = paletteLut(palette);
    var step = opts.step || 4;
    // FIX-1 alpha policy (nullschool rule — geography always shows through).
    // CONTINUOUS overlays fill at domainMask * CONT_ALPHA (< 0.85) so the base +
    // the coastline/border vectors (earth2d_mount.js, ON TOP) read through.
    // Out-of-domain pixels (SST on land, AQI on ocean) are dropped via the mask.
    var domain = opts.domain || (grid && grid.domain) || 'global';
    // Item 8: density-style fields render as a CRISP choropleth — nearest cell
    // sampling (hard edges) + discrete colour classes — not a smooth blob.
    var choropleth = !!(opts.choropleth || (grid && grid.choropleth));
    var choroSteps = (grid && grid.choroplethSteps) || opts.choroplethSteps || 9;
    // SPARSE/ALERT layers value-gate so no-stress cells go transparent (no
    // blanket). opts.alert overrides; else DATA-DRIVEN sparse classifier (mostly-
    // floor field) OR honest alert label/units — never falls through to opaque.
    var sparse = (opts.alert != null)
      ? !!opts.alert
      : (isAlertSparseLayer(grid && grid.label, grid && grid.units) ||
         isSparseField(grid, domain));
    // (1a) domain-aware continuous alpha: masked fields keep CONT_ALPHA (their
    // clear off-domain half shows geography); GLOBAL fields use the lower
    // CONT_ALPHA_GLOBAL so the full-canvas fill doesn't blanket.
    var contAlpha = (domain === 'global') ? CONT_ALPHA_GLOBAL : CONT_ALPHA;

    // Reuse the passed lattice ONLY when its identity key matches the current
    // projection/rotation/scale + canvas + step; otherwise rebuild it (the single
    // ~1000-invert pass). After a rotation the key differs → rebuild once; a
    // rebuild at the SAME view (data/palette change) skips the inverts entirely.
    var key = inverseGridKey(projection, w, h, step);
    var cache = (opts.cache && opts.cache.key === key)
      ? opts.cache : buildInverseGrid(projection, w, h, step);
    cache.key = key;
    var cols = cache.cols, lon = cache.lon, lat = cache.lat, ok = cache.ok;

    var img = ctx.createImageData(w, h);
    var data = img.data;
    var p = 0;
    for (var y = 0; y < h; y++) {
      var r0 = (y / step) | 0; var fyc = (y - r0 * step) / step;
      for (var x = 0; x < w; x++, p += 4) {
        var c0 = (x / step) | 0; var fxc = (x - c0 * step) / step;
        var i00 = r0 * cols + c0, i10 = i00 + 1, i01 = i00 + cols, i11 = i01 + 1;
        var llo, lla;
        if (ok[i00] && ok[i10] && ok[i01] && ok[i11]) {
          var base = lon[i00];
          var l00 = lon[i00];
          var l10 = unwrapLon(lon[i10], base);
          var l01 = unwrapLon(lon[i01], base);
          var l11 = unwrapLon(lon[i11], base);
          var ltop = l00 + (l10 - l00) * fxc;
          var lbot = l01 + (l11 - l01) * fxc;
          llo = ltop + (lbot - ltop) * fyc;
          var atop = lat[i00] + (lat[i10] - lat[i00]) * fxc;
          var abot = lat[i01] + (lat[i11] - lat[i01]) * fxc;
          lla = atop + (abot - atop) * fyc;
        } else {
          var ll = projection.invert ? projection.invert([x, y]) : null;
          if (!ll || !isFinite(ll[0]) || !isFinite(ll[1])) { data[p + 3] = 0; continue; }
          llo = ll[0]; lla = ll[1];
        }
        var da = domainAlpha(domain, llo, lla);
        if (da <= 0.004) { data[p + 3] = 0; continue; }
        var v = choropleth ? sampleGridNearest(grid, llo, lla)
                           : sampleGrid(grid, llo, lla);
        if (v == null) { data[p + 3] = 0; continue; }
        var t = (v - vmin) / span; if (t < 0) t = 0; else if (t > 1) t = 1;
        if (choropleth) t = quantize(t, choroSteps);
        var li = ((t * 255) | 0) * 3;
        data[p] = lut[li]; data[p + 1] = lut[li + 1]; data[p + 2] = lut[li + 2];
        // Continuous: semi-transparent fill (CONT_ALPHA, feathered coast) so
        // geography reads. Alert/sparse: value gate -> no-stress cells transparent,
        // capped at ALERT_MAX_ALPHA so elevated cells stay translucent (item 7).
        var af = sparse ? alertGate(t) * ALERT_MAX_ALPHA : contAlpha;
        data[p + 3] = (da * af * 255) | 0;
      }
    }
    ctx.putImageData(img, 0, 0);
    return cache;
  }

  global.Earth2dScalar = {
    PALETTES: PALETTES,
    paletteColor: paletteColor,
    paletteLut: paletteLut,
    sampleGrid: sampleGrid,
    sampleGridNearest: sampleGridNearest,
    quantize: quantize,
    buildInverseGrid: buildInverseGrid,
    renderField: renderField,
    domainAlpha: domainAlpha,
    loadLandMask: loadLandMask,
    landFractionAt: landFractionAt,
    maskReady: maskReady,
    version: '0.2.1-slot-parity'
  };
})(typeof self !== 'undefined' ? self : this);

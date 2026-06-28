/*
 * earth2d_points.js — 2D-canvas POINT-MARKER renderer + hit-test (build-out #7).
 *
 * Consumes the LIVE point contract READ-ONLY: an EarthPointSet bridge payload
 * { palette, domain, valueMin, valueMax, units, label, caption, isLive,
 *   points:[ {lat, lon, value, label?, count?} ] }.
 * Markers are sized/coloured by value, horizon-culled on globe projections, and
 * clusters (count>1) draw larger with a ring + a "browse in Data View" snapshot
 * path — mirroring the live point renderer + EarthScalarPoint.markerScale curve
 * (0.4 + 0.6*sqrt(normalize(value))).
 *
 * render() returns the on-screen marker geometry so the host can hit-test a
 * click and emit the governed snapshot (no new data, just the clicked record).
 * File-disjoint port: never imports/edits web/earth_point_field.js or Cesium.
 */
(function (global) {
  'use strict';

  var DEG = Math.PI / 180;

  // Fallback fire ramp if Earth2dScalar (shared palettes) is not loaded.
  var FIRE = [[0, [255, 245, 150]], [0.4, [255, 150, 40]], [0.7, [225, 50, 20]], [1, [140, 12, 8]]];
  function lerpRamp(stops, t) {
    if (t <= 0) return stops[0][1];
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i][0]) {
        var a = stops[i - 1], b = stops[i], f = (t - a[0]) / ((b[0] - a[0]) || 1);
        return [Math.round(a[1][0] + (b[1][0] - a[1][0]) * f),
                Math.round(a[1][1] + (b[1][1] - a[1][1]) * f),
                Math.round(a[1][2] + (b[1][2] - a[1][2]) * f)];
      }
    }
    return stops[stops.length - 1][1];
  }
  function paletteColor(id, t) {
    if (global.Earth2dScalar && global.Earth2dScalar.paletteColor) return global.Earth2dScalar.paletteColor(id, t);
    return lerpRamp(FIRE, t);
  }

  function normalize(v, lo, hi) { var s = hi - lo; if (s <= 0) return 0; var t = (v - lo) / s; return t < 0 ? 0 : (t > 1 ? 1 : t); }
  function markerScale(t) { return 0.4 + 0.6 * Math.sqrt(t < 0 ? 0 : (t > 1 ? 1 : t)); }
  // A1 (cleanup): mirror web/earth_point_field.js EXACTLY. Pixel DIAMETER on a
  // base of 9 (single = 9*scale); clusters share that value curve + a small
  // capped count nudge, cap 11px. The 2D renderer draws RADIUS = diameter/2, so
  // a single max reads ~9px and a dense cluster ~11px — identical to Cesium.
  function markerDiameter(t) { return 9 * markerScale(t); }
  function clusterDiameter(t, count) {
    return Math.min(11, markerDiameter(t) + Math.min(2.2, 0.7 * Math.log(count) / Math.LN2));
  }
  // Back-compat alias (older callers/tests) — radius multiplier on a base-5 marker.
  function clusterScale(count) { return clusterDiameter(1, count) / 2 / 5; }

  function onFront(projection, lon, lat) {
    var r = projection.rotate ? projection.rotate() : null;
    if (!r) return true;
    var clip = projection.clipAngle ? projection.clipAngle() : null;
    if (clip == null || clip >= 180) return true;
    var lon0 = -r[0], lat0 = -r[1];
    var cosc = Math.sin(lat0 * DEG) * Math.sin(lat * DEG) +
      Math.cos(lat0 * DEG) * Math.cos(lat * DEG) * Math.cos((lon - lon0) * DEG);
    return cosc >= Math.cos((clip || 90) * DEG);
  }

  // Draw the point set; return [{x,y,r,point}] for hit-testing (nearest-first by
  // larger markers last so clicks favour the visually-topmost).
  // Trace a marker path centred at (x,y) with "radius" r (half-extent). Default
  // is a circle; 'diamond' (boats) is a 4-point rhombus of the SAME extent so the
  // marker size is unchanged. Unknown shapes fall back to a circle.
  function markerPath(ctx, shape, x, y, r) {
    if (shape === 'diamond') {
      ctx.beginPath();
      ctx.moveTo(x, y - r); ctx.lineTo(x + r, y);
      ctx.lineTo(x, y + r); ctx.lineTo(x - r, y);
      ctx.closePath();
    } else if (shape === 'triangle' || shape === 'arrow') {
      // Flights — an upward triangle/arrow of the SAME half-extent r (size
      // unchanged vs the dot). Heading encoding is a future enhancement.
      ctx.beginPath();
      ctx.moveTo(x, y - r); ctx.lineTo(x + r, y + r); ctx.lineTo(x - r, y + r);
      ctx.closePath();
    } else {
      ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832);
    }
  }

  // ── Schematic orbit-ring bands (2D) ─────────────────────────────────────────
  // The bridge sends the SHARED ring spec (lib/models/earth/earth_orbit_ring_spec
  // .dart) in ps.rings; this is the fail-soft fallback when it is absent. KEEP
  // LOCK-STEP with that model + web/earth_point_field.js (the radius factors are
  // asserted by earth_orbit_ring_test.dart). Radii are SCHEMATIC fractions of the
  // disc radius (NOT true km) so all three rings float just outside the globe —
  // true GEO at ~6.6 Earth radii would be off-screen.
  var DEFAULT_ORBIT_RINGS = [
    { id: 'leo', label: 'LEO', rgb: [90, 200, 250], radiusFactor: 1.15, tilt: 0.34, inclinationDeg: 55, altLowKm: 0, altHighKm: 2000 },
    { id: 'meo', label: 'MEO', rgb: [240, 190, 70], radiusFactor: 1.4, tilt: 0.3, inclinationDeg: 42, altLowKm: 2000, altHighKm: 30000 },
    { id: 'geo', label: 'GEO', rgb: [180, 130, 240], radiusFactor: 1.7, tilt: 0.22, inclinationDeg: 18, altLowKm: 30000, altHighKm: 1e12 }
  ];

  // Colour by orbital BAND — LEO cyan, MEO amber/gold, GEO violet (lock-step with
  // the ring-spec colours).
  function bandColor(altKm) {
    if (altKm <= 2000) return [90, 200, 250];   // LEO
    if (altKm <= 30000) return [240, 190, 70];   // MEO
    return [180, 130, 240];                       // GEO
  }
  function bandForAltKm(rings, km) {
    for (var i = 0; i < rings.length; i++) {
      var b = rings[i];
      if (km >= b.altLowKm && km < b.altHighKm) return b;
    }
    return km < rings[0].altHighKm ? rings[0] : rings[rings.length - 1];
  }

  // Draw one concentric TILTED ELLIPSE ring centred on the disc: semi-major
  // a = discRadius × radiusFactor, semi-minor b = a × tilt (the foreshorten of a
  // ring seen at an angle). FRONT (near) arc solid + bright, BACK (far) arc
  // dashed + dim — the 2D analogue of the globe depth-occluding the ring's back.
  // Canvas ellipse angles run clockwise from +x (y-down), so 0→π is the bottom
  // (front) half and π→2π the top (back) half.
  function drawRing(ctx, cx, cy, a, b, rgb) {
    if (!ctx.ellipse) return; // very old canvas: skip rings (sats still draw)
    // back arc (top, behind the globe): dim + dashed.
    ctx.beginPath(); ctx.ellipse(cx, cy, a, b, 0, Math.PI, 2 * Math.PI);
    ctx.lineWidth = 1.2;
    ctx.strokeStyle = 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0.30)';
    try { ctx.setLineDash([5, 5]); } catch (e) {/* ignore */}
    ctx.stroke();
    try { ctx.setLineDash([]); } catch (e) {/* ignore */}
    // front arc (bottom, in front of the globe): solid + bright.
    ctx.beginPath(); ctx.ellipse(cx, cy, a, b, 0, 0, Math.PI);
    ctx.lineWidth = 1.6;
    ctx.strokeStyle = 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0.92)';
    ctx.stroke();
  }

  // A named satellite riding its ring: front = solid + labelled; back = dim, no
  // label (it is occluded behind the globe).
  function drawSat(ctx, x, y, rgb, label, front) {
    ctx.beginPath(); ctx.arc(x, y, front ? 3.6 : 2.4, 0, 6.2832);
    ctx.fillStyle = 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + (front ? 0.98 : 0.4) + ')';
    ctx.fill();
    ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(8,12,20,' + (front ? 0.7 : 0.3) + ')'; ctx.stroke();
    if (!front || !label) return;
    ctx.save();
    ctx.font = '12px system-ui, -apple-system, sans-serif';
    ctx.textBaseline = 'middle';
    var tx = x + 6, ty = y - 7, w = ctx.measureText(label).width;
    ctx.fillStyle = 'rgba(8,12,20,0.55)'; ctx.fillRect(tx - 2, ty - 7, w + 4, 14);
    ctx.fillStyle = 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0.98)';
    ctx.fillText(label, tx, ty);
    ctx.restore();
  }

  // Elevated LEO/MEO/GEO orbit rings: three concentric TILTED ELLIPSES centred on
  // the disc, with the named satellites riding their band's ellipse at the
  // AZIMUTH of their sub-satellite point (so placement tracks rotation + is
  // roughly real, not random). Redrawn against the disc each frame, so a
  // projection / region / rotate change stays correct. Returns no hits
  // (satellites are ambient — excluded from the click hit-test + lat/long probe).
  function renderOrbital(ctx, projection, ps) {
    var rings = (ps.rings && ps.rings.length) ? ps.rings : DEFAULT_ORBIT_RINGS;
    var pts = ps.points || [];
    var center = projection.translate ? projection.translate() : [0, 0];
    var cx = center[0], cy = center[1];
    var isGlobe = !!(projection.rotate && projection.rotate());
    // disc radius in px — d3 globe projections expose scale() = the sphere radius.
    var Rdisc = projection.scale ? projection.scale() : Math.min(cx, cy);
    if (!isGlobe) {
      // Full-frame map (equirectangular / mercator / …): no disc to ring around —
      // draw the named sats as plain labelled dots at their map position.
      for (var j = 0; j < pts.length; j++) {
        var fp = pts[j];
        var fs = projection([fp.lon, fp.lat]);
        if (!fs || !isFinite(fs[0]) || !isFinite(fs[1])) continue;
        drawSat(ctx, fs[0], fs[1], bandForAltKm(rings, fp.value).rgb, fp.label, true);
      }
      return [];
    }
    // 1) the three concentric tilted ellipses.
    for (var r = 0; r < rings.length; r++) {
      var band = rings[r], aa = Rdisc * band.radiusFactor;
      drawRing(ctx, cx, cy, aa, aa * band.tilt, band.rgb);
    }
    // 2) named sats riding their band's ellipse at the azimuth of their sub-pt.
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i];
      var bnd = bandForAltKm(rings, p.value);
      var a = Rdisc * bnd.radiusFactor, b = a * bnd.tilt;
      var s = projection([p.lon, p.lat]);
      if (!s || !isFinite(s[0]) || !isFinite(s[1])) continue;
      var az = Math.atan2(s[1] - cy, s[0] - cx);
      var phi = Math.atan2(a * Math.sin(az), b * Math.cos(az));
      var ex = cx + a * Math.cos(phi), ey = cy + b * Math.sin(phi);
      drawSat(ctx, ex, ey, bnd.rgb, p.label, onFront(projection, p.lon, p.lat));
    }
    return [];
  }

  function render(ctx, projection, ps, opts) {
    opts = opts || {};
    if ((opts.render || ps.render) === 'orbital') return renderOrbital(ctx, projection, ps);
    var pal = opts.palette || ps.palette || 'fire';
    var shape = opts.shape || ps.shape || 'circle';
    var lo = ps.valueMin != null ? ps.valueMin : 0;
    var hi = ps.valueMax != null ? ps.valueMax : 1;
    var baseR = opts.baseRadius || 5;
    var pts = ps.points || [];
    var hits = [];
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i];
      if (!onFront(projection, p.lon, p.lat)) continue;
      var s = projection([p.lon, p.lat]);
      if (!s || !isFinite(s[0]) || !isFinite(s[1])) continue;
      var t = normalize(p.value, lo, hi);
      var cluster = (p.count || 1) > 1;
      // Item 5: a folded-in biodiversity richness dot draws LARGER (~1.7x) and in
      // an ALT colour-scale (`mag`) so it reads distinctly from the host Protected
      // Areas dots (teal).
      var isBio = !!p.bio;
      // A1: RADIUS = diameter/2 of the shared curve (identical to Cesium px).
      // Single = value-sized; cluster = same curve + capped count nudge.
      var r = isBio
        ? markerDiameter(t) / 2 * 1.7
        : (cluster ? clusterDiameter(t, p.count) / 2 : markerDiameter(t) / 2);
      var c = isBio ? paletteColor('mag', t) : paletteColor(pal, t);
      markerPath(ctx, shape, s[0], s[1], r);
      ctx.fillStyle = 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',0.9)';
      ctx.fill();
      ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(10,14,22,0.65)'; ctx.stroke();
      if (cluster) {
        markerPath(ctx, shape, s[0], s[1], r + 2.5);
        ctx.strokeStyle = 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',0.55)'; ctx.stroke();
      }
      hits.push({ x: s[0], y: s[1], r: r + 3, point: p, cluster: cluster });
    }
    return hits;
  }

  // Nearest marker within its radius (topmost wins on ties).
  function hitTest(hits, x, y) {
    var best = null, bestD = Infinity;
    for (var i = 0; i < hits.length; i++) {
      var h = hits[i], dx = x - h.x, dy = y - h.y, d = dx * dx + dy * dy;
      if (d <= h.r * h.r && d <= bestD) { bestD = d; best = h; }
    }
    return best;
  }

  // The governed snapshot for a clicked marker: a single record's detail, or a
  // cluster's "browse in Data View" path (never invents data).
  function snapshot(hit, ps) {
    if (!hit) return null;
    var p = hit.point;
    if (hit.cluster) {
      // value+units are required by the card model (a payload with no numeric
      // `value` parses to null → no card). Pass the cluster's REAL label (it
      // carries the country, e.g. "92 datacenters · GB") so the in-popup browse
      // can filter that layer's records by country — mirrors the Cesium path
      // (index.html sends earthPointLabel). Falls back to a count string.
      return { kind: 'cluster', value: p.value, units: ps.units || '',
        count: p.count, lat: p.lat, lon: p.lon,
        label: p.label || ((p.count) + ' records'),
        // Item 3: THIS dot's own member labels (build-time embedded) so the
        // snapshot lists exactly the clicked dot's members, not a rollup.
        members: Array.isArray(p.members) ? p.members : undefined,
        action: 'browse in Data View',
        caption: ps.caption || ps.label, isLive: !!ps.isLive };
    }
    return { kind: 'record', value: p.value, units: ps.units || '', lat: p.lat, lon: p.lon,
      label: p.label || ps.label, caption: ps.caption || ps.label, isLive: !!ps.isLive };
  }

  global.Earth2dPoints = {
    normalize: normalize, markerScale: markerScale, clusterScale: clusterScale,
    paletteColor: paletteColor, render: render, hitTest: hitTest,
    snapshot: snapshot, version: '0.2.0-points'
  };
})(typeof self !== 'undefined' ? self : this);

/*
 * earth2d_flow.js — 2D-canvas PARTICLE-FLOW renderer (north-star build-out #6).
 *
 * Consumes the LIVE flow contract READ-ONLY: an EarthWindGrid u/v bridge payload
 * { nx, ny, lon0, lat0, dlon, dlat, u[nx*ny], v[nx*ny], maxSpeed, isLive, caption }.
 * ONE particle engine serves both wind and ocean-currents (exactly like the live
 * EarthFlowFieldFrame: palette chosen by `flowKind`). Projection is injected, so
 * particles advect in GEOGRAPHIC space (sample u/v -> step lon/lat -> reproject),
 * which is correct under all 8 projections — the nullschool/cambecc approach.
 *
 * Honors the motion budget (EarthFlowFieldMotionBudget): step() suspends advection
 * when dragging / reduced-motion / hidden, but still repaints so the field stays
 * put. Trails fade via a translucent wipe each frame.
 *
 * File-disjoint port: never imports/edits web/earth_flow_field.js or Cesium.
 */
(function (global) {
  'use strict';

  var DEG = Math.PI / 180;

  // Item 6 (nullschool parity): LIGHTER ramps — every stop is brightened,
  // especially the low (slow-particle) end, so even calm flow reads as light
  // streamlines instead of dark threads. Currents + waves get the biggest lift
  // (they were the darkest / hardest to see).
  // Owner pass 2: currents + waves BRIGHTER STILL — the ocean ramp is lifted
  // toward foam-white at every stop and the waves ramp is near-white so the
  // fat-stroke swell reads clearly (nullschool's bright currents/waves).
  var PALETTES = {
    wind: [[0, [90, 140, 128]], [0.4, [150, 205, 158]], [0.72, [214, 232, 156]], [1, [250, 253, 240]]],
    ocean: [[0, [120, 195, 222]], [0.5, [170, 232, 240]], [1, [232, 252, 250]]],
    // Waves (NOAA WW3): a near-white foam ramp distinct from the ocean-current
    // blue; rendered as FAT swell strokes (see step()). Wave height drives value.
    waves: [[0, [150, 210, 235]], [0.45, [195, 238, 246]], [0.78, [226, 250, 251]], [1, [250, 254, 254]]]
  };
  function ramp(stops, t) {
    if (t <= 0) return stops[0][1];
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i][0]) {
        var a = stops[i - 1], b = stops[i], f = (t - a[0]) / ((b[0] - a[0]) || 1);
        return [(a[1][0] + (b[1][0] - a[1][0]) * f) | 0,
                (a[1][1] + (b[1][1] - a[1][1]) * f) | 0,
                (a[1][2] + (b[1][2] - a[1][2]) * f) | 0];
      }
    }
    return stops[stops.length - 1][1];
  }

  // Bilinear (u,v) sample of an EarthWindGrid bridge payload. lon wraps, lat
  // clamps — mirrors EarthWindGrid.sample exactly.
  function sampleUV(g, lon, lat) {
    var nx = g.nx, ny = g.ny;
    var fx = ((lon - g.lon0) / g.dlon) % nx; if (fx < 0) fx += nx;
    var x0 = Math.floor(fx) % nx, x1 = (x0 + 1) % nx, tx = fx - Math.floor(fx);
    var fy = (lat - g.lat0) / g.dlat; if (fy < 0) fy = 0; else if (fy > ny - 1) fy = ny - 1;
    var y0 = Math.floor(fy), y1 = Math.min(y0 + 1, ny - 1), ty = fy - y0;
    var u = g.u, v = g.v;
    function bl(a) { var t = a[y0 * nx + x0] + (a[y0 * nx + x1] - a[y0 * nx + x0]) * tx;
      var b = a[y1 * nx + x0] + (a[y1 * nx + x1] - a[y1 * nx + x0]) * tx; return t + (b - t) * ty; }
    return [bl(u), bl(v)];
  }

  function Engine(opts) {
    opts = opts || {};
    // Item 6: DENSER field (nullschool-class). Default + caps raised so the
    // streamlines pack the globe instead of reading sparse.
    this.count = opts.count || 3600;
    this.maxLife = opts.maxLife || 90;
    this.speedScale = opts.speedScale || 0.07;
    // Item 6: slightly LONGER trails (stronger streamlines) — each frame removes
    // `fade` of the prior trail. 0.075 → ~9-frame half-life (was 0.09).
    this.fade = opts.fade != null ? opts.fade : 0.075;
    this.flowKind = 'wind';
    this.domain = 'global'; // 'global' (wind) bypasses the land/sea mask
    // Owner pass 2: WAVES render fewer, FATTER swell strokes (nullschool look),
    // so they use a lower density than the thin wind/currents streamlines.
    this.densityScale = 1;
    this.grid = null;
    this.projection = null;
    this.ps = [];
  }
  Engine.prototype._targetCount = function () {
    return Math.max(1, (this.count * this.densityScale) | 0);
  };
  // Density target — nullschool scales particle count with canvas area. Called
  // from the mount on resize; rebuilds the field lazily on the next step.
  Engine.prototype.setCount = function (n) {
    // Item 6: denser bounds (was 2500..7000) so larger canvases pack more
    // streamlines, matching nullschool density.
    // PERF (mobile): the count scales with CSS area (~w*ht/170). A 3200 FLOOR
    // force-densified small phone canvases (~1600 natural) back up to 3200,
    // doubling the per-frame advection loop into jank. Lower the floor to 1500
    // so phones run at their natural light density; large canvases are well
    // above it and keep the full nullschool density (capped 9000).
    n = Math.max(1500, Math.min(9000, n | 0));
    if (n !== this.count) { this.count = n; this.ps = []; }
  };
  Engine.prototype.setGrid = function (grid, flowKind) {
    var prevKind = this.flowKind;
    this.grid = grid; this.flowKind = flowKind || 'wind';
    // Ocean + waves are masked to the sea; wind is global.
    this.domain =
      (this.flowKind === 'ocean' || this.flowKind === 'waves') ? 'ocean' : 'global';
    // Waves: ~half the streamline count → fewer, fatter swell strokes; rebuild
    // the field when the kind changes so the density takes effect immediately.
    this.densityScale = (this.flowKind === 'waves') ? 0.5 : 1;
    if (this.flowKind !== prevKind) this.ps = [];
    if (grid) {
      if (!grid.maxSpeed) {
        var m = 0; for (var k = 0; k < grid.u.length; k++) { var s = grid.u[k] * grid.u[k] + grid.v[k] * grid.v[k]; if (s > m) m = s; }
        grid.maxSpeed = Math.sqrt(m) || 1;
      }
      // PER-KIND SPEED NORMALIZATION (nullschool feel): advect every layer to a
      // similar visual peak regardless of native units — wind ~13 m/s, ocean
      // ~1 m/s (would be frozen at a fixed scale → why ocean didn't animate),
      // waves ~10 m wave-height. Owner device-pass: the old 1.3 target read as
      // "too strong" vs nullschool → 0.85 (≈35% slower) for calmer streamlines.
      // Clamped so a near-zero grid can't explode. DEVICE-PASS TUNABLE.
      // Owner pass 2: waves advect a touch SLOWER (0.6 target) so the fat swell
      // strokes roll like ocean swells rather than darting like wind.
      var target = (this.flowKind === 'waves') ? 0.6 : 0.85;
      this.speedScale = Math.max(0.04, Math.min(8, target / (grid.maxSpeed || 1)));
    }
  };
  Engine.prototype.setProjection = function (p) { this.projection = p; };
  // In this engine's domain at (lon,lat)? Reuses the scalar renderer's shared
  // land/sea mask (Earth2dScalar.domainAlpha). Fail-open until the mask loads so
  // the field never blanks (the grid's zero-on-land u/v already damps land flow).
  Engine.prototype._inDomain = function (lon, lat) {
    if (this.domain === 'global') return true;
    var S = global.Earth2dScalar;
    if (!S || !S.domainAlpha || (S.maskReady && !S.maskReady())) return true;
    return S.domainAlpha('ocean', lon, lat) > 0.5;
  };
  // Land test (wind land-friction). Reuses the shared ocean mask: not-ocean =
  // land. Fail-open to SEA (no damp) until the mask loads, so wind never blanks.
  Engine.prototype._isLand = function (lon, lat) {
    var S = global.Earth2dScalar;
    if (!S || !S.domainAlpha || (S.maskReady && !S.maskReady())) return false;
    return S.domainAlpha('ocean', lon, lat) <= 0.5;
  };
  Engine.prototype._spawn = function (pt) {
    pt = pt || {};
    // Domain-aware spawn: keep ocean/waves particles in the sea (bounded retry).
    for (var t = 0; t < 6; t++) {
      pt.lon = Math.random() * 360 - 180;
      pt.lat = Math.asin(Math.random() * 2 - 1) / DEG;
      if (this.domain === 'global' || this._inDomain(pt.lon, pt.lat)) break;
    }
    pt.age = (Math.random() * this.maxLife) | 0;
    pt.px = null; pt.py = null;
    return pt;
  };
  Engine.prototype.reset = function () { this.ps = []; var n = this._targetCount(); for (var i = 0; i < n; i++) this.ps.push(this._spawn({})); };

  // Advance + paint one frame. budget: {dragging, reducedMotion, hidden}.
  Engine.prototype.step = function (ctx, W, H, budget) {
    var g = this.grid, proj = this.projection;
    if (!proj) return;
    var animate = !(budget && (budget.dragging || budget.reducedMotion || budget.hidden));
    // Item 1 (readiness gate): the mount fades the field IN after the camera /
    // projection settles (post-load, post-rotate, post region/projection change).
    // alphaScale ramps 0->1 so streamlines never POP onto a just-settled globe;
    // when 0 we still fade the existing trails but draw no new segments.
    var alphaScale = (budget && budget.alphaScale != null) ? budget.alphaScale : 1;
    if (alphaScale < 0) alphaScale = 0; else if (alphaScale > 1) alphaScale = 1;
    if (!this.ps.length) this.reset();
    // WAVES are a DISTINCT animation from wind/currents (owner pass 2): FAT,
    // round-capped swell strokes that leave a LONGER trail (nullschool's
    // "primary/waves" look), vs the thin hair streamlines of wind/currents.
    var isWaves = this.flowKind === 'waves';
    // WAVES = short directional-dash/stipple (reverses the fat long-trail "pass
    // 2" that read as currents): a quicker per-frame fade so each dash is short,
    // and particles respawn sooner (shorter maxAge) for the stipple texture.
    var fade = isWaves ? 0.28 : this.fade;
    var maxLife = isWaves ? Math.round(this.maxLife * 0.4) : this.maxLife;
    // TRAIL-FADE on a TRANSPARENT layer: fade existing trails toward transparent
    // (destination-out) rather than painting a dark wipe. The mount composites
    // this layer OVER the scalar heatmap base each frame, so a source-over dark
    // fade would dim the heatmap underneath (the old either/or behaviour). Faded
    // every frame as before; advection is still gated on the motion budget.
    ctx.globalCompositeOperation = 'destination-out';
    ctx.fillStyle = 'rgba(0,0,0,' + fade + ')';
    ctx.fillRect(0, 0, W, H);
    ctx.globalCompositeOperation = 'source-over';
    if (!g) return;
    var stops = PALETTES[this.flowKind] || PALETTES.wind;
    var maxS = g.maxSpeed || 1;
    // Wind/currents: crisp hair streamlines. Waves: THIN round dashes (was a fat
    // 2.8 swept stroke that read as a current), oriented along the wave heading.
    ctx.lineWidth = isWaves ? 1.6 : 0.95;
    ctx.lineCap = isWaves ? 'round' : 'butt';
    ctx.lineJoin = isWaves ? 'round' : 'miter';
    // Stroke alpha is now SPEED-DRIVEN per particle (computed in the loop) — the
    // old constant per-kind alpha is what made wind read as a uniform sheet.
    for (var i = 0; i < this.ps.length; i++) {
      var p = this.ps[i];
      var scr = proj([p.lon, p.lat]);
      var vis = scr && isFinite(scr[0]) && isFinite(scr[1]) && this._onFront(p.lon, p.lat);
      if (animate) {
        var uv = sampleUV(g, p.lon, p.lat);
        var sp = Math.sqrt(uv[0] * uv[0] + uv[1] * uv[1]);
        // LAND FRICTION (wind only — currents/waves are sea-masked): ease the
        // wind's speed + opacity to ~0.55 over land instead of killing it.
        var landDamp = (this.domain === 'global' && this._isLand(p.lon, p.lat)) ? 0.55 : 1;
        if (vis && p.px != null && scr) {
          var dx = scr[0] - p.px, dy = scr[1] - p.py;
          if (dx * dx + dy * dy < 900) {
            var t = Math.min(1, sp / maxS);
            var c = ramp(stops, t);
            // SPEED-DRIVEN opacity (nullschool parity): slow flow nearly vanishes,
            // fast flow reads bright — this kills the old uniform sheet. Waves use
            // a higher floor so the near-white foam stipple stays visible.
            // LOCKDOWN: raise the calm-flow floor from 0.05 (near-invisible) to
            // ~0.4 so calm wind clearly reads; still speed-scaled up to ~0.9.
            // Waves already floor at 0.45 (short-dash foam stipple).
            var aBase = isWaves
              ? (0.45 + 0.5 * Math.pow(t, 1.2))
              : (0.4 + 0.5 * Math.pow(t, 1.5));
            var a = aBase * landDamp * alphaScale;
            ctx.strokeStyle = 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')';
            ctx.beginPath(); ctx.moveTo(p.px, p.py); ctx.lineTo(scr[0], scr[1]); ctx.stroke();
          }
        }
        var coslat = Math.cos(p.lat * DEG); if (coslat < 0.2) coslat = 0.2;
        var adv = this.speedScale * landDamp;
        p.lon += uv[0] * adv / coslat;
        p.lat += uv[1] * adv;
        if (p.lon > 180) p.lon -= 360; else if (p.lon < -180) p.lon += 360;
        if (p.lat > 89) p.lat = 89; else if (p.lat < -89) p.lat = -89;
        if (++p.age > maxLife) { this._spawn(p); continue; }
        // GEO-VALIDITY: an ocean/waves particle that advected onto land is killed
        // and reseeded into the sea, so the field stays inside its medium
        // (mirrors the Cesium flow renderer; the 2D engine lacked this).
        if (this.domain !== 'global' && !this._inDomain(p.lon, p.lat)) {
          this._spawn(p); continue;
        }
      }
      p.px = vis && scr ? scr[0] : null; p.py = vis && scr ? scr[1] : null;
    }
    ctx.globalCompositeOperation = 'source-over';
  };
  // Horizon cull for globe projections: a point is on the near face when its
  // angular distance from the projection centre < 90deg. For full-frame
  // projections the projection's own clip handles visibility, so default true.
  Engine.prototype._onFront = function (lon, lat) {
    var r = this.projection.rotate ? this.projection.rotate() : null;
    if (!r) return true;
    var clip = this.projection.clipAngle ? this.projection.clipAngle() : null;
    if (clip == null || clip >= 180) return true;
    var lon0 = -r[0], lat0 = -r[1];
    var cosc = Math.sin(lat0 * DEG) * Math.sin(lat * DEG) +
      Math.cos(lat0 * DEG) * Math.cos(lat * DEG) * Math.cos((lon - lon0) * DEG);
    return cosc >= Math.cos((clip || 90) * DEG);
  };

  global.Earth2dFlow = {
    PALETTES: PALETTES, ramp: ramp, sampleUV: sampleUV,
    create: function (opts) { return new Engine(opts); },
    version: '0.3.0-flow'
  };
})(typeof self !== 'undefined' ? self : this);

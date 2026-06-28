/*
 * earth2d_projections.js — the 8 projection presets for the 2D-canvas renderer.
 *
 * Build-out slice #5. The scalar/flow/point renderers are projection-INJECTED
 * (they only need `projection.invert` per pixel + `projection` for d3.geoPath
 * vectors), so "8 projections" is a registry of configured d3-geo projections —
 * NOT eight bespoke renderers. Each entry returns a projection fitted to a
 * w x h canvas. `globe:true` = a hemisphere/disc projection (has a limb);
 * `globe:false` = a full-frame world projection.
 *
 * Requires d3-geo on the global (the harness/app provides it; this file stays
 * dependency-free at parse time so `node --check` passes without d3).
 */
(function (global) {
  'use strict';

  function makeRegistry(d3) {
    function globeScale(w, h) { return Math.min(w, h) / 2 - 6; }
    function fitSphere(p, w, h, pad) {
      try {
        p.fitExtent([[pad, pad], [w - pad, h - pad]], { type: 'Sphere' });
      } catch (e) { /* unbounded sphere -> caller set scale manually */ }
      return p;
    }

    return [
      { id: 'orthographic', label: 'Orthographic (globe)', globe: true,
        make: function (w, h) {
          return d3.geoOrthographic().scale(globeScale(w, h))
            .translate([w / 2, h / 2]).clipAngle(90).rotate([0, -10]);
        } },
      { id: 'stereographic', label: 'Stereographic', globe: true,
        make: function (w, h) {
          // FILL the viewport (owner: "fill all black area like nullschool").
          // Scale so the front hemisphere covers the canvas CORNERS; clipAngle
          // 160 (>150) makes earth2d_mount's globe-fit shrink SKIP this preset,
          // so the fill scale is honored (orthographic stays framed/shrunk).
          return d3.geoStereographic()
            .scale(Math.sqrt(w * w + h * h) / 4 * 1.08)
            .translate([w / 2, h / 2]).clipAngle(160).rotate([0, -10]);
        } },
      { id: 'azimuthal-equal-area', label: 'Azimuthal equal-area', globe: true,
        make: function (w, h) {
          return d3.geoAzimuthalEqualArea().scale(globeScale(w, h) * 0.95)
            .translate([w / 2, h / 2]).clipAngle(168).rotate([0, -10]);
        } },
      { id: 'gnomonic', label: 'Gnomonic', globe: true,
        make: function (w, h) {
          return d3.geoGnomonic().scale(globeScale(w, h) * 0.7)
            .translate([w / 2, h / 2]).clipAngle(68).rotate([0, -10]);
        } },
      { id: 'equirectangular', label: 'Equirectangular', globe: false,
        make: function (w, h) {
          return d3.geoEquirectangular().scale(w / (2 * Math.PI))
            .translate([w / 2, h / 2]).rotate([0, 0]);
        } },
      { id: 'mercator', label: 'Mercator', globe: false,
        make: function (w, h) {
          return d3.geoMercator().scale(w / (2 * Math.PI))
            .translate([w / 2, h / 2]).rotate([0, 0]);
        } },
      { id: 'natural-earth', label: 'Natural Earth', globe: false,
        make: function (w, h) {
          return fitSphere(d3.geoNaturalEarth1().rotate([0, 0]), w, h, 6);
        } },
      { id: 'conic-conformal', label: 'Conic conformal', globe: false,
        make: function (w, h) {
          return d3.geoConicConformal().parallels([15, 50]).center([0, 22])
            .scale(w / 6.5).translate([w / 2, h * 0.62]).rotate([0, 0]);
        } }
    ];
  }

  global.Earth2dProjections = {
    ids: ['orthographic', 'stereographic', 'azimuthal-equal-area', 'gnomonic',
      'equirectangular', 'mercator', 'natural-earth', 'conic-conformal'],
    makeRegistry: makeRegistry,
    byId: function (d3, id, w, h) {
      var reg = makeRegistry(d3);
      for (var i = 0; i < reg.length; i++) if (reg[i].id === id) return reg[i].make(w, h);
      return reg[0].make(w, h);
    }
  };
})(typeof self !== 'undefined' ? self : this);

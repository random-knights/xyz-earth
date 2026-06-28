/// SHARED, SCHEMATIC orbit-ring band spec — the single source of truth for the
/// ambient satellites layer (Space mode), consumed by BOTH globe renderers:
/// `web/earth_point_field.js` (Cesium 3D) and `web/earth2d_points.js` (2D
/// canvas). It is carried into the renderers via the bridge payload
/// ([EarthPointSet.toBridgeJson] `rings`) so the geometry is data-driven and the
/// band radii / tilts / colours are never hand-duplicated across the two files.
///
/// WHY SCHEMATIC: a true GEO orbit sits at ~6.6 Earth radii — far off the framed
/// globe — and MEO at ~4.2 R, so drawing the rings at real altitude would push
/// MEO/GEO out of view (the old bug: only low LEO showed). Instead the three
/// bands are COMPRESSED to fixed radius multiples of the Earth radius that all
/// float just OUTSIDE the globe, as concentric tilted rings (the mock). The
/// named satellites ride their band's ring; the radii are honest-by-disclosure
/// schematic, not metric.
library;

/// One orbit-band ring (LEO / MEO / GEO).
final class EarthOrbitRingBand {
  const EarthOrbitRingBand({
    required this.id,
    required this.label,
    required this.colorRgb,
    required this.radiusFactor,
    required this.tilt,
    required this.inclinationDeg,
    required this.altLowKm,
    required this.altHighKm,
  });

  /// Stable band id: `leo` | `meo` | `geo`.
  final String id;

  /// Display label: `LEO` | `MEO` | `GEO`.
  final String label;

  /// Band colour as RGB bytes — lock-step with the renderers' `bandColor`
  /// (LEO blue, MEO amber/gold, GEO violet).
  final List<int> colorRgb;

  /// SCHEMATIC ring radius as a multiple of the Earth radius (NOT true km).
  /// LEO 1.15× / MEO 1.40× / GEO 1.70× — each sits just outside the globe.
  final double radiusFactor;

  /// 2D ellipse foreshorten (semi-minor ÷ semi-major) used by the 2D canvas
  /// renderer to draw the ring as a tilted ellipse seen at an angle.
  final double tilt;

  /// 3D ring-plane inclination (degrees) used by the Cesium renderer to incline
  /// the orbit-ring polyline. Schematic display tilt, spread per band so the
  /// three concentric rings read as distinct planes.
  final double inclinationDeg;

  /// Altitude bucket bounds (km) — a propagated satellite's altitude is
  /// classified into the band whose `[altLowKm, altHighKm)` it falls in.
  final double altLowKm;
  final double altHighKm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'rgb': colorRgb,
        'radiusFactor': radiusFactor,
        'tilt': tilt,
        'inclinationDeg': inclinationDeg,
        'altLowKm': altLowKm,
        'altHighKm': altHighKm,
      };
}

/// The canonical three-band spec. The radius factors / tilts / colours here are
/// the values the renderers fall back to when the bridge omits `rings`, enforced
/// by `earth_orbit_ring_test.dart` so the JS defaults can never silently drift.
abstract final class EarthOrbitRingSpec {
  static const bands = <EarthOrbitRingBand>[
    // LEO — blue, ~550–2,000 km. Inclined like the ISS/Starlink shells.
    EarthOrbitRingBand(
      id: 'leo',
      label: 'LEO',
      colorRgb: [90, 200, 250],
      radiusFactor: 1.15,
      tilt: 0.34,
      inclinationDeg: 55,
      altLowKm: 0,
      altHighKm: 2000,
    ),
    // MEO — amber/gold, ~20,200 km (GPS/NAVSTAR).
    EarthOrbitRingBand(
      id: 'meo',
      label: 'MEO',
      colorRgb: [240, 190, 70],
      radiusFactor: 1.40,
      tilt: 0.30,
      inclinationDeg: 42,
      altLowKm: 2000,
      altHighKm: 30000,
    ),
    // GEO — violet, ~35,786 km. Nearly equatorial; a gentle display tilt so the
    // outermost ring still reads as a ring (not edge-on) from the default view.
    EarthOrbitRingBand(
      id: 'geo',
      label: 'GEO',
      colorRgb: [180, 130, 240],
      radiusFactor: 1.70,
      tilt: 0.22,
      inclinationDeg: 18,
      altLowKm: 30000,
      altHighKm: double.infinity,
    ),
  ];

  /// The ring table as emitted into the bridge payload (`rings`).
  static List<Map<String, dynamic>> get bridgeRings =>
      [for (final b in bands) b.toJson()];

  /// The band an altitude (km) falls into; clamps to the nearest band so a stray
  /// altitude never falls through (e.g. a slightly-low LEO or super-GEO value).
  static EarthOrbitRingBand bandForAltitudeKm(double km) {
    for (final b in bands) {
      if (km >= b.altLowKm && km < b.altHighKm) return b;
    }
    return km < bands.first.altHighKm ? bands.first : bands.last;
  }
}

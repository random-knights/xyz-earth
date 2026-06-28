import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:xyz_earth/models/earth/earth_orbit.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';
import 'package:xyz_earth/services/earth/earth_scalar_field_source.dart';

/// Builds the AMBIENT satellites point set (Space mode) from a bundled curated
/// TLE catalogue: one CURRENT, NAMED dot per satellite (ISS / GPS / GOES / …),
/// each carrying its altitude (→ orbit band) and its name as a display label.
///
/// The three orbit-band RINGS themselves are SCHEMATIC geometry drawn by the
/// renderers from the shared [EarthOrbitRingSpec] (compressed LEO/MEO/GEO circles
/// that float just outside the globe — true GEO is ~6.6 Earth radii, off-screen),
/// so this source no longer samples ground tracks into ring dots; it only places
/// the named satellites that ride those rings. Positions come from the simplified
/// [EarthOrbitPropagator] (educational / non-trackable).
///
/// GOVERNANCE: the layer stays AMBIENT — non-interactive (no per-satellite click,
/// readout, or live track). The names are static, educational labels on a
/// schematic ring (ISS and GPS are well-known public objects), not a tracking
/// surface — the same ambient lock as flights, plus a label.
class SatellitePointSetSource implements EarthPointSetSource {
  const SatellitePointSetSource({
    this.assetPath = 'assets/earth/satellites/curated-tle-v1.json',
    this.now,
  });

  /// Bundled curated TLE catalogue (earth.tle.v1).
  final String assetPath;

  /// Injected clock for deterministic tests; defaults to [DateTime.now] (UTC).
  final DateTime? now;

  @override
  Future<EarthPointSet> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final sats = (json['satellites'] as List).cast<dynamic>();
    final t = (now ?? DateTime.now()).toUtc();

    final points = <EarthScalarPoint>[];
    for (final s in sats) {
      final m = (s as Map).cast<String, dynamic>();
      try {
        final tle = EarthTle.parse(
          m['name'] as String? ?? '',
          m['l1'] as String,
          m['l2'] as String,
        );
        final p = EarthOrbitPropagator.propagate(tle, t);
        // The CURRENT sub-satellite point + altitude (→ band) + the name. The
        // renderer maps the sub-satellite longitude → an angle on the band's
        // schematic ring, so the placement is roughly real, not random.
        points.add(EarthScalarPoint(
          lat: p.latDeg,
          lon: p.lonDeg,
          value: p.altitudeKm,
          label: tle.name.isEmpty ? null : tle.name,
        ));
      } catch (_) {/* skip a malformed TLE */}
    }

    return EarthPointSet(
      points: points,
      valueMin: 0,
      // GEO altitude ~35 786 km caps the colour/size scale, so LEO→GEO reads as
      // an altitude gradient (violet ramp).
      valueMax: 36000,
      units: 'km altitude',
      paletteId: 'violet',
      domain: EarthLayerDomain.global,
      label: 'Satellite orbit bands (LEO/MEO/GEO) + named satellites',
      attribution:
          'CelesTrak GP (public). Approximate Keplerian propagation — '
          'educational / ambient, not precise tracking.',
      source: 'CelesTrak',
      isLive: false,
      // Ambient governance lock (same as flights): non-interactive.
      interactive: false,
    ).ambient();
  }
}

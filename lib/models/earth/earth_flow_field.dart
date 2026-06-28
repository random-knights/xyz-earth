// C9 — Cesium V2.16 slice 3: flow-field layers (wind + ocean currents).
//
// Pure, unit-testable flow-field state for the Cesium globe. The frame is
// LIVE-DATA-DRIVEN visualization of already-governed layers: vectors come only
// from the existing wind ([EarthWindModel]) and ocean-currents
// ([EarthOceanCurrentsProviderFixture]) models — no new sources, no new
// overlays. Layer activation follows the earth+ filter state: the selected
// layer renders its flow field, others don't. Animation obeys the D1 motion
// budget (suspend when hidden, reduced-motion, or during drag).

import 'dart:math' as math;

import 'package:xyz_earth/models/earth/earth_ocean_currents_live.dart';
import 'package:xyz_earth/models/earth/earth_wind.dart';

/// Catalog layer ids (earth_source_layer_catalog.dart) that own a flow field.
abstract final class EarthFlowFieldLayerIds {
  static const wind = 'wind';
  static const oceanCurrents = 'ocean-currents';
  static const waves = 'waves';
  static const all = {wind, oceanCurrents, waves};

  static bool ownsFlowField(String layerId) => all.contains(layerId);
}

/// One governed flow vector: heading + speed normalized into the same
/// intensity scale the retained motion suite uses
/// (earth_motion_flow_painter.dart: amplitude/width grow with intensity).
final class EarthFlowFieldVector {
  const EarthFlowFieldVector({
    required this.layerId,
    required this.headingDegrees,
    required this.speed,
    required this.speedCeiling,
    required this.sourceLabel,
  });

  /// Wind: km/h speed from the live weather-wind provider model. Ceiling 31
  /// matches the EarthWindModel `windy`→`strong` classification boundary.
  factory EarthFlowFieldVector.fromWind(EarthWindModel wind) {
    return EarthFlowFieldVector(
      layerId: EarthFlowFieldLayerIds.wind,
      headingDegrees: wind.directionDegrees ?? 0,
      speed: wind.speed ?? 0,
      speedCeiling: 31,
      sourceLabel: wind.source,
    );
  }

  /// Ocean currents: km/h current velocity from the governed live fixture
  /// shape. Ceiling 4 km/h — strong surface currents top out near that.
  factory EarthFlowFieldVector.fromOceanCurrents(
    EarthOceanCurrentsProviderFixture currents,
  ) {
    return EarthFlowFieldVector(
      layerId: EarthFlowFieldLayerIds.oceanCurrents,
      headingDegrees: currents.currentDirectionDegrees,
      speed: currents.currentVelocityKmh,
      speedCeiling: 4,
      sourceLabel: currents.sourceLabel,
    );
  }

  final String layerId;
  final int headingDegrees;
  final double speed;
  final double speedCeiling;
  final String sourceLabel;

  /// 0..1 intensity on the motion-suite scale; drives particle speed and
  /// streamline amplitude exactly like the retained painter's `intensity`.
  double get intensity {
    if (speedCeiling <= 0) return 0;
    final normalized = speed / speedCeiling;
    if (normalized.isNaN || normalized < 0) return 0;
    return normalized > 1 ? 1 : normalized;
  }

  int get normalizedHeadingDegrees => ((headingDegrees % 360) + 360) % 360;
}

/// A coarse global u/v wind grid — the Phase 1a data contract.
///
/// HONESTY: [label]/[attribution]/[isLive] carry the governed framing. The
/// static Phase 1a asset is a representative climatology ([isLive] == false);
/// the Phase 1b NOAA-GFS function emits the IDENTICAL shape with the same
/// fields — the renderer never changes, only the source repoints. Longitude is
/// periodic; latitude runs north→south from [lat0] by [dlat].
final class EarthWindGrid {
  const EarthWindGrid({
    required this.nx,
    required this.ny,
    required this.lon0,
    required this.lat0,
    required this.dlon,
    required this.dlat,
    required this.u,
    required this.v,
    required this.label,
    required this.attribution,
    required this.license,
    required this.source,
    required this.units,
    required this.vintage,
    this.isLive = false,
    this.referenceTime,
  });

  factory EarthWindGrid.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map).cast<String, dynamic>();
    final grid = (json['grid'] as Map).cast<String, dynamic>();
    final u = (grid['u'] as List).map((e) => (e as num).toDouble()).toList();
    final v = (grid['v'] as List).map((e) => (e as num).toDouble()).toList();
    final nx = (grid['nx'] as num).toInt();
    final ny = (grid['ny'] as num).toInt();
    if (u.length != nx * ny || v.length != nx * ny) {
      throw FormatException(
        'wind grid u/v length ${u.length}/${v.length} != nx*ny ${nx * ny}',
      );
    }
    return EarthWindGrid(
      nx: nx,
      ny: ny,
      lon0: (grid['lon0'] as num).toDouble(),
      lat0: (grid['lat0'] as num).toDouble(),
      dlon: (grid['dlon'] as num).toDouble(),
      dlat: (grid['dlat'] as num).toDouble(),
      u: u,
      v: v,
      label: (meta['label'] as String?) ?? 'representative wind',
      attribution: (meta['attribution'] as String?) ?? '',
      license: (meta['license'] as String?) ?? '',
      source: (meta['source'] as String?) ?? '',
      units: (meta['units'] as String?) ?? 'm/s',
      vintage: (meta['vintage'] as String?) ?? 'unknown',
      isLive: (meta['liveReady'] as bool?) ?? (meta['isLive'] as bool?) ?? false,
      referenceTime: meta['referenceTime'] as String?,
    );
  }

  final int nx;
  final int ny;
  final double lon0;
  final double lat0;
  final double dlon;
  final double dlat;
  final List<double> u;
  final List<double> v;

  /// Governed honesty framing — surfaced by governance/UI, never implies live.
  final String label;
  final String attribution;
  final String license;
  final String source;
  final String units;
  final String vintage;
  final bool isLive;

  /// ISO-8601 data reference time for LIVE grids (the GFS cycle time). Null for
  /// the static representative climatology (which has no current timestamp).
  final String? referenceTime;

  int get cellCount => nx * ny;

  /// The honest user-facing caption: a live grid shows source + reference time;
  /// the static grid shows its "not current conditions" label. Never implies
  /// live data when [isLive] is false.
  String get caption {
    if (isLive) {
      final ref = referenceTime;
      return ref == null || ref.isEmpty
          ? '$source · live'
          : '$source · $ref';
    }
    return label;
  }

  /// Peak vector magnitude (m/s) for normalization. Cheap; grid is small.
  double get maxSpeed {
    var maxSq = 0.0;
    for (var k = 0; k < u.length; k++) {
      final s = u[k] * u[k] + v[k] * v[k];
      if (s > maxSq) maxSq = s;
    }
    return maxSq <= 0 ? 1 : math.sqrt(maxSq);
  }

  /// Bilinear sample at (lon, lat) → (u, v). Longitude wraps; latitude clamps.
  (double, double) sample(double lon, double lat) {
    final fx = ((lon - lon0) / dlon) % nx;
    final x0 = fx.floor() % nx;
    final x1 = (x0 + 1) % nx;
    final tx = fx - fx.floor();

    var fy = (lat - lat0) / dlat;
    if (fy < 0) fy = 0;
    if (fy > ny - 1) fy = (ny - 1).toDouble();
    final y0 = fy.floor();
    final y1 = (y0 + 1).clamp(0, ny - 1);
    final ty = fy - y0;

    double at(List<double> g, int xi, int yi) => g[yi * nx + xi];
    double lerp(double a, double b, double t) => a + (b - a) * t;

    final uTop = lerp(at(u, x0, y0), at(u, x1, y0), tx);
    final uBot = lerp(at(u, x0, y1), at(u, x1, y1), tx);
    final vTop = lerp(at(v, x0, y0), at(v, x1, y0), tx);
    final vBot = lerp(at(v, x0, y1), at(v, x1, y1), tx);
    return (lerp(uTop, uBot, ty), lerp(vTop, vBot, ty));
  }

  /// Compact payload for the JS flow renderer. Carries the honest label so the
  /// renderer/overlay can never imply live data.
  Map<String, dynamic> toBridgeJson() {
    return {
      'nx': nx,
      'ny': ny,
      'lon0': lon0,
      'lat0': lat0,
      'dlon': dlon,
      'dlat': dlat,
      'maxSpeed': double.parse(maxSpeed.toStringAsFixed(3)),
      'vintage': vintage,
      'label': label,
      'caption': caption,
      'isLive': isLive,
      if (referenceTime != null) 'referenceTime': referenceTime,
      'u': u,
      'v': v,
    };
  }
}

/// D1 motion-budget contract for flow-field animation: no motion when the
/// stage is hidden, the user prefers reduced motion, or a drag is in progress.
final class EarthFlowFieldMotionBudget {
  const EarthFlowFieldMotionBudget({
    required this.stageVisible,
    required this.reducedMotion,
    required this.dragging,
  });

  final bool stageVisible;
  final bool reducedMotion;
  final bool dragging;

  bool get animationAllowed => stageVisible && !reducedMotion && !dragging;

  String get suspensionReason {
    if (!stageVisible) return 'stage hidden';
    if (reducedMotion) return 'reduced motion';
    if (dragging) return 'drag in progress';
    return 'none';
  }
}

/// A resolved flow-field frame: which layers render and whether they animate.
/// This is the only payload the renderer bridge receives — selection and
/// budget decisions are made here, never in the bridge.
final class EarthFlowFieldFrame {
  const EarthFlowFieldFrame({
    required this.vectors,
    required this.animate,
    this.windGrid,
    this.oceanGrid,
    this.wavesGrid,
    this.hd = false,
  });

  static const empty = EarthFlowFieldFrame(vectors: [], animate: false);

  /// Resolves the frame from the earth+ filter state: only the SELECTED layer
  /// renders its flow field; selecting any non-flow layer clears the field.
  ///
  /// Wind (Phase 1a): when [windGrid] is supplied and wind is selected, the
  /// frame carries the GLOBAL grid for the nullschool-style field; the optional
  /// single [wind] vector is retained only as the governance-summary
  /// representative. A selected flow layer with neither a grid nor a live
  /// vector renders nothing (fail-closed — never a synthetic vector).
  factory EarthFlowFieldFrame.resolve({
    required String selectedLayerId,
    required EarthFlowFieldMotionBudget budget,
    EarthFlowFieldVector? wind,
    EarthFlowFieldVector? oceanCurrents,
    EarthWindGrid? windGrid,
    EarthWindGrid? oceanGrid,
    EarthWindGrid? wavesGrid,
    bool hd = false,
  }) {
    switch (selectedLayerId) {
      case EarthFlowFieldLayerIds.wind:
        if (windGrid == null && wind == null) return empty;
        return EarthFlowFieldFrame(
          vectors: wind == null ? const [] : [wind],
          windGrid: windGrid,
          animate: budget.animationAllowed,
          hd: hd,
        );
      case EarthFlowFieldLayerIds.oceanCurrents:
        // Ocean reuses the same global u/v grid contract + particle engine as
        // wind; a distinct palette (set by the renderer from [flowKind]) makes
        // it read differently. A single fixture vector is retained only as the
        // governance-summary representative when no grid is supplied.
        if (oceanGrid == null && oceanCurrents == null) return empty;
        return EarthFlowFieldFrame(
          vectors: oceanCurrents == null ? const [] : [oceanCurrents],
          oceanGrid: oceanGrid,
          animate: budget.animationAllowed,
          hd: hd,
        );
      case EarthFlowFieldLayerIds.waves:
        // NOAA WaveWatch III waves reuse the SAME global u/v grid contract +
        // particle engine as wind/ocean; significant wave height drives the
        // speed, peak direction the heading, and a distinct palette (set by the
        // renderer from [flowKind]='waves') reads it apart. Ocean domain.
        if (wavesGrid == null) return empty;
        return EarthFlowFieldFrame(
          vectors: const [],
          wavesGrid: wavesGrid,
          animate: budget.animationAllowed,
          hd: hd,
        );
      default:
        return empty;
    }
  }

  final List<EarthFlowFieldVector> vectors;
  final bool animate;

  /// HD toggle (item 6): when true the renderer raises the flow-field particle
  /// budget toward nullschool density (still within the global motion budget +
  /// reduced-motion caps) and may request a finer grid when one is available.
  final bool hd;

  /// The global wind grid for the nullschool-style field (wind only).
  final EarthWindGrid? windGrid;

  /// The global ocean-current grid (ocean-currents only). Same u/v contract as
  /// [windGrid] — one particle engine, palette chosen per [flowKind].
  final EarthWindGrid? oceanGrid;

  /// The global ocean-waves grid (waves only). Same u/v contract — significant
  /// wave height as the magnitude, peak wave direction as the heading.
  final EarthWindGrid? wavesGrid;

  /// The active flow grid (wind, ocean, or waves), whichever this frame carries.
  EarthWindGrid? get flowGrid => windGrid ?? oceanGrid ?? wavesGrid;

  /// Renderer palette selector: `wind`, `ocean`, `waves`, or null when gridless.
  String? get flowKind {
    if (windGrid != null) return 'wind';
    if (oceanGrid != null) return 'ocean';
    if (wavesGrid != null) return 'waves';
    return null;
  }

  bool get hasFlow =>
      vectors.isNotEmpty ||
      windGrid != null ||
      oceanGrid != null ||
      wavesGrid != null;

  bool get hasWindGrid => windGrid != null;

  bool get hasOceanGrid => oceanGrid != null;

  bool get hasWavesGrid => wavesGrid != null;

  Set<String> get activeLayerIds => {
        for (final v in vectors) v.layerId,
        if (windGrid != null) EarthFlowFieldLayerIds.wind,
        if (oceanGrid != null) EarthFlowFieldLayerIds.oceanCurrents,
        if (wavesGrid != null) EarthFlowFieldLayerIds.waves,
      };

  /// Same frame with animation forced off (renderer suspended).
  EarthFlowFieldFrame suspended() {
    if (!animate) return this;
    return EarthFlowFieldFrame(
      vectors: vectors,
      windGrid: windGrid,
      oceanGrid: oceanGrid,
      animate: false,
      hd: hd,
    );
  }
}

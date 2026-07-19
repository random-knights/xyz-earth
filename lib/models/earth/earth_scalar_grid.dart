// 8-LAYER PUSH — the two ratified renderer data contracts.
//
// EarthScalarGrid : a coarse per-cell scalar field (air-quality, SST, density,
//   forest...) rendered as a palette-driven alpha heatmap, DOMAIN-MASKED to the
//   layer's valid medium (geo-validity: air-quality=land/coast, SST=ocean,
//   density/forest=land). Same grid geometry family as EarthWindGrid so it
//   reuses the land/sea mask + projection.
// EarthPointSet : masked markers sized/coloured by value (wildfire, biodiversity)
//   rendered by the point renderer, horizon-culled + domain-masked to land.
//
// HONESTY: [isLive] + [caption] carry the governed framing exactly like
// EarthWindGrid — a layer reads "live" ONLY when bound to a real source grid;
// otherwise the Data View labels it representative/fixture.

import 'dart:math' as math;

import 'package:xyz_earth/models/earth/earth_orbit_ring_spec.dart';

/// Palette ids the scalar/point renderers know (kept in lock-step with the JS
/// PALETTES in web/earth_scalar_field.js + web/earth_point_field.js and the
/// Dart scale-bar stops in earth_overlay_scale_bar.dart).
abstract final class EarthRendererPalettes {
  static const airQuality = 'aqi'; // green -> yellow -> orange -> red -> purple
  static const thermal = 'thermal'; // blue -> cyan -> yellow -> red (SST)
  static const fire = 'fire'; // yellow -> orange -> deep red (wildfire)
  static const vegetation = 'veg'; // brown -> yellow -> green (forest)
  static const magnitude = 'mag'; // dark -> bright single-hue (density)
  static const violet = 'violet'; // indigo -> violet -> lilac (carbon)
  static const teal = 'teal'; // deep teal -> aqua (protected areas)
  static const ember = 'ember'; // brown -> amber -> gold (tree-time)
  static const cyan = 'cyan'; // deep navy -> bright cyan (datacenters)
  static const storm = 'storm'; // calm blue -> green -> amber -> red -> magenta (CAPE instability)
  static const ice = 'ice'; // light-blue throughout (glacier point markers)
  static const nonprofits = 'nonprofits'; // lime ramp (environmental-nonprofits points)
  static const all = {
    airQuality, thermal, fire, vegetation, magnitude, violet, teal, ember, cyan,
    storm, ice, nonprofits,
  };
}

/// T1 (E) — client-side per-POINT-LAYER display overrides, independent of the
/// data feed: the renderers key marker colour off the point set's [paletteId]
/// and the marker glyph off its [markerShape], so these reskin a layer without a
/// data re-publish. Applied in [EarthFrameResolver.pointFrameFor].
abstract final class EarthPointLayerDisplay {
  static const _palette = <String, String>{
    // Glaciers → light-blue dots.
    'glaciers': EarthRendererPalettes.ice,
    // Environmental nonprofits (US, IRS BMF): lime ramp, value = log10 revenue.
    'environmental-nonprofits': EarthRendererPalettes.nonprofits,
  };
  static const _shape = <String, String>{
    // Flights → triangle/arrow markers (boats already ride 'diamond' from data).
    'flights': 'triangle',
  };
  static const _render = <String, String>{
    // Satellites → elevated LEO/MEO/GEO orbit shells (not surface dots).
    'satellites': 'orbital',
  };

  static String? paletteFor(String layerId) => _palette[layerId];
  static String? shapeFor(String layerId) => _shape[layerId];
  static String? renderModeFor(String layerId) => _render[layerId];
}

/// Canonical, data-source-INDEPENDENT palette per scalar layer. Resolved client-
/// side at render so each layer is always visually DISTINCT, regardless of what
/// a representative asset or a live refresher baked into the grid meta. Fixes the
/// device-pass collision where carbon+density both read 'mag' and forest+
/// protected-areas+tree-time all read 'veg' (indistinguishable layers). Returns
/// null for layers with no override (the grid's own palette is then used).
abstract final class EarthScalarLayerPalettes {
  static const _byLayer = <String, String>{
    'particulates': EarthRendererPalettes.airQuality,
    'chemistry': EarthRendererPalettes.magnitude,
    'protected-areas': EarthRendererPalettes.teal,
    'tree-time': EarthRendererPalettes.ember,
    'forest': EarthRendererPalettes.vegetation,
    'human-encroachment': EarthRendererPalettes.magnitude,
    'air-quality': EarthRendererPalettes.airQuality,
    'sst': EarthRendererPalettes.thermal,
    'ssta': EarthRendererPalettes.thermal,
    // Bleaching Alert Area (0-4): a severity ramp (no-stress → alert level 2),
    // distinct from the thermal SST layers.
    'baa': EarthRendererPalettes.airQuality,
    // New atmosphere overlays (excluded from the score). CAPE gets its own
    // instability ramp; dust reuses ember (ochre); misery-index reuses thermal.
    'cape': EarthRendererPalettes.storm,
    'dust-aod': EarthRendererPalettes.ember,
    'misery-index': EarthRendererPalettes.thermal,
  };

  static String? of(String layerId) => _byLayer[layerId];
}

/// The active scalar OVERLAY's value scale — published by the globe view for the
/// Globe-View scale-bar / value key (nullschool-parity slice 5a). Presentation
/// metadata only, derived from the governed grid the renderer is showing; null
/// when no scalar overlay is active. Value equality so the notifier only fires
/// on a real change.
final class EarthOverlayScale {
  const EarthOverlayScale({
    required this.paletteId,
    required this.valueMin,
    required this.valueMax,
    required this.units,
    required this.label,
    required this.isLive,
  });

  final String paletteId;
  final double valueMin;
  final double valueMax;
  final String units;
  final String label;
  final bool isLive;

  /// [paletteOverride] (when non-null) replaces the grid's palette so the scale-
  /// bar matches the canonical per-layer palette the renderer draws.
  factory EarthOverlayScale.fromGrid(
    EarthScalarGrid g, {
    String? paletteOverride,
  }) =>
      EarthOverlayScale(
        paletteId: paletteOverride ?? g.paletteId,
        valueMin: g.valueMin,
        valueMax: g.valueMax,
        units: g.units,
        label: g.label,
        isLive: g.isLive,
      );

  @override
  bool operator ==(Object other) =>
      other is EarthOverlayScale &&
      other.paletteId == paletteId &&
      other.valueMin == valueMin &&
      other.valueMax == valueMax &&
      other.units == units &&
      other.label == label &&
      other.isLive == isLive;

  @override
  int get hashCode =>
      Object.hash(paletteId, valueMin, valueMax, units, label, isLive);
}

/// Which renderer drives a built animated layer.
enum EarthLayerRenderKind { flow, scalar, point }

/// The built/selectable animated layers and the renderer each one uses. The
/// Earth+ picker enables a layer iff [isBuilt]; the globe view dispatches by
/// [renderKindFor] (flow=particles, scalar=heatmap, point=markers). Grows as
/// layers ship — flow ids mirror EarthFlowFieldLayerIds.
abstract final class EarthAnimatedLayerIds {
  // NOAA WaveWatch III significant-wave-height + peak-direction flow (ocean).
  static const flow = {'wind', 'ocean-currents', 'waves'};
  static const scalar = {
    'air-quality',
    // CAMS surface PM2.5 (global atmospheric field), rendered by the earth-worker
    // Cloud Run Job; representative until that worker writes its Storage grid.
    'particulates',
    // CAMS surface NO2 (global atmospheric field), same earth-worker pipe.
    'chemistry',
    'forest',
    'human-encroachment',
    'human-modification',
    'sst',
    // SST anomaly vs 1991-2020 climatology (nullschool SSTA), same NOAA OISST
    // refresher as sst — emitted alongside the absolute grid.
    'ssta',
    // NOAA Coral Reef Watch Bleaching Alert Area (ocean; 0-4 alert levels). REAL
    // dated representative snapshot; live via a future earthBaaRefresh grid.
    'baa',
    // Batch-2 scalar verticals (land): WDPA protected-area coverage + the
    // derived tree-time index. The synthetic 'carbon' ppm scalar was RETIRED
    // from the globe overlay (representative IDW, not factual — owner directive);
    // carbon survives as a Data-View/analytics catalog concept + the REAL
    // Berkeley VCM 'carbon-offset-projects' POINT layer below.
    'protected-areas',
    'tree-time',
    // NEW atmosphere overlays — EXCLUDED from the health score (no signal map
    // entry), representative→live honesty. CAPE = GFS convective instability
    // (J/kg); dust-aod = CAMS dust AOD@550nm; misery-index = NWS feels-like
    // (heat index ⊕ wind chill) from GFS 2m temp/humidity/10m wind. (Added LAST
    // — the boats lane edits the `point` set below; keep these disjoint.)
    'cape',
    'dust-aod',
    'misery-index',
  };
  static const point = {
    'wildfires',
    'biodiversity-habitat',
    // Batch-2 point verticals (land): WGMS glacier sites + VCM project sites.
    'glaciers',
    'carbon-offset-projects',
    // Earth impact-players point verticals (clustered earth.pointset.v1, static
    // ingest, no live feed). protected-areas-points is ADDITIVE — distinct from
    // the existing `protected-areas` SCALAR layer (score reads the scalar grid).
    'species-threatened',
    'businesses-footprint',
    'datacenters',
    'industrial-sites',
    'protected-areas-points',
    // Anthroposphere annotation layers (clustered earth.pointset.v1, real public
    // ingests): WRI power plants + Maus mining/extraction sites. Wired to a
    // live-storage source with a representative fallback; EXCLUDED from the
    // health score (no signal-map entry).
    'power-plants',
    'extraction-sites',
    // Ambient airborne-aircraft positions (OpenSky ADS-B), identity-stripped,
    // rendered as non-interactive decimated cyan flow dots (mobility lane).
    'flights',
    // Ambient vessel activity (Global Fishing Watch aggregated fishing effort),
    // identity-FREE by construction, non-interactive teal DIAMOND dots (mobility
    // lane). Sits under Ocean mode for now (T1 relabels to Anthroposphere later).
    'boats',
    // Ambient satellite orbit bands (LEO/MEO/GEO ground tracks) + named
    // satellites, propagated client-side from CelesTrak TLEs (Space mode).
    'satellites',
    // US environmental nonprofits (IRS Exempt Organizations BMF located via US
    // Census ZCTA Gazetteer ZIP centroids; value = log10 annual revenue USD).
    // Bundled representative fallback for the keyless offline boot; the live
    // upgrade reads the nonprofits ingest snapshot. Health/trend-neutral (no
    // score signal). Organizations, not people.
    'environmental-nonprofits',
  };

  static Set<String> get all => {...flow, ...scalar, ...point};

  static bool isBuilt(String layerId) => all.contains(layerId);

  static EarthLayerRenderKind? renderKindFor(String layerId) {
    if (flow.contains(layerId)) return EarthLayerRenderKind.flow;
    if (scalar.contains(layerId)) return EarthLayerRenderKind.scalar;
    if (point.contains(layerId)) return EarthLayerRenderKind.point;
    return null;
  }
}

/// A resolved scalar-field frame for the renderer bridge: the grid + whether it
/// animates ([active]). Mirrors EarthFlowFieldFrame's role for the heatmap.
final class EarthScalarFrame {
  const EarthScalarFrame({
    this.grid,
    this.active = false,
    this.paletteOverride,
    this.prewarm = false,
  });

  static const empty = EarthScalarFrame();

  final EarthScalarGrid? grid;
  final bool active;

  /// Canonical per-layer palette (see [EarthScalarLayerPalettes]); when set it
  /// overrides the grid's baked palette so the layer is always distinct.
  final String? paletteOverride;

  /// When true this frame is a PRE-WARM request: the renderer builds + caches
  /// the layer's texture (idle, no drape) so its first selection is instant.
  /// The controller forwards it without making it the active frame.
  final bool prewarm;

  bool get hasGrid => grid != null;

  /// Same frame with animation forced off (renderer cleared / suspended).
  EarthScalarFrame suspended() => active
      ? EarthScalarFrame(
          grid: grid, active: false, paletteOverride: paletteOverride)
      : this;

  Map<String, dynamic> toBridgeJson() {
    final g = grid;
    return {
      'active': active && g != null,
      if (prewarm) 'prewarm': true,
      if (g != null) 'domain': g.domain.id,
      if (g != null) 'palette': paletteOverride ?? g.paletteId,
      'grid': g?.toBridgeJson(),
    };
  }
}

/// A resolved POINT frame for the renderer bridge: the point set + whether it
/// animates ([active]). Mirrors EarthScalarFrame for the marker renderer.
final class EarthPointFrame {
  const EarthPointFrame({this.pointSet, this.active = false});

  static const empty = EarthPointFrame();

  final EarthPointSet? pointSet;
  final bool active;

  bool get hasPoints => pointSet != null && pointSet!.points.isNotEmpty;

  EarthPointFrame suspended() =>
      active ? EarthPointFrame(pointSet: pointSet, active: false) : this;

  Map<String, dynamic> toBridgeJson() {
    final ps = pointSet;
    return {
      'active': active && ps != null && ps.points.isNotEmpty,
      if (ps != null) ...ps.toBridgeJson(),
    };
  }
}

/// Geo-validity domain for a data layer (matches the renderer's validDomain).
enum EarthLayerDomain { global, ocean, land, landCoastal }

extension EarthLayerDomainId on EarthLayerDomain {
  String get id => switch (this) {
        EarthLayerDomain.global => 'global',
        EarthLayerDomain.ocean => 'ocean',
        EarthLayerDomain.land => 'land',
        EarthLayerDomain.landCoastal => 'land-coastal',
      };
}

/// Shared honesty meta for both renderer contracts.
mixin _EarthLayerHonesty {
  String get label;
  String get source;
  bool get isLive;
  String? get referenceTime;

  /// The honest user-facing caption: live shows source + reference time; a
  /// representative/fixture layer shows its "not current conditions" label.
  String get caption {
    if (isLive) {
      final ref = referenceTime;
      return ref == null || ref.isEmpty ? '$source · live' : '$source · $ref';
    }
    return label;
  }
}

/// A coarse global scalar field on the shared grid lattice.
final class EarthScalarGrid with _EarthLayerHonesty {
  const EarthScalarGrid({
    required this.nx,
    required this.ny,
    required this.lon0,
    required this.lat0,
    required this.dlon,
    required this.dlat,
    required this.values,
    required this.valueMin,
    required this.valueMax,
    required this.units,
    required this.paletteId,
    required this.domain,
    required this.label,
    required this.attribution,
    required this.license,
    required this.source,
    required this.vintage,
    this.isLive = false,
    this.referenceTime,
    this.choropleth = false,
    this.choroplethSteps = 9,
  });

  factory EarthScalarGrid.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map).cast<String, dynamic>();
    final grid = (json['grid'] as Map).cast<String, dynamic>();
    final values =
        (grid['values'] as List).map((e) => (e as num).toDouble()).toList();
    final nx = (grid['nx'] as num).toInt();
    final ny = (grid['ny'] as num).toInt();
    if (values.length != nx * ny) {
      throw FormatException(
        'scalar grid values length ${values.length} != nx*ny ${nx * ny}',
      );
    }
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in values) {
      if (v.isNaN) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    return EarthScalarGrid(
      nx: nx,
      ny: ny,
      lon0: (grid['lon0'] as num).toDouble(),
      lat0: (grid['lat0'] as num).toDouble(),
      dlon: (grid['dlon'] as num).toDouble(),
      dlat: (grid['dlat'] as num).toDouble(),
      values: values,
      valueMin: (meta['valueMin'] as num?)?.toDouble() ??
          (lo.isFinite ? lo : 0),
      valueMax: (meta['valueMax'] as num?)?.toDouble() ??
          (hi.isFinite ? hi : 1),
      units: (meta['units'] as String?) ?? '',
      paletteId: (meta['palette'] as String?) ?? EarthRendererPalettes.magnitude,
      domain: switch (meta['domain'] as String?) {
        'ocean' => EarthLayerDomain.ocean,
        'land' => EarthLayerDomain.land,
        'land-coastal' => EarthLayerDomain.landCoastal,
        _ => EarthLayerDomain.global,
      },
      label: (meta['label'] as String?) ?? 'representative field',
      attribution: (meta['attribution'] as String?) ?? '',
      license: (meta['license'] as String?) ?? '',
      source: (meta['source'] as String?) ?? '',
      vintage: (meta['vintage'] as String?) ?? 'unknown',
      isLive: (meta['liveReady'] as bool?) ?? (meta['isLive'] as bool?) ?? false,
      referenceTime: meta['referenceTime'] as String?,
      // Item 8: a density-style field renders as a crisp choropleth (discrete
      // colour steps, nearest cell edges, no de-block blur) — not a smooth blob.
      choropleth: (meta['choropleth'] as bool?) ?? false,
      choroplethSteps: (meta['choroplethSteps'] as num?)?.toInt() ?? 9,
    );
  }

  final int nx;
  final int ny;
  final double lon0;
  final double lat0;
  final double dlon;
  final double dlat;
  final List<double> values;
  final double valueMin;
  final double valueMax;
  final String units;
  final String paletteId;
  final EarthLayerDomain domain;

  @override
  final String label;
  final String attribution;
  final String license;
  @override
  final String source;
  final String vintage;
  @override
  final bool isLive;
  @override
  final String? referenceTime;

  /// Item 8: render as a crisp choropleth (discrete colour steps, nearest cell
  /// edges, no de-block blur) instead of a smooth interpolated field.
  final bool choropleth;
  final int choroplethSteps;

  int get cellCount => nx * ny;

  /// 0..1 normalization on the value range (clamped), for the palette lookup.
  double normalize(double v) {
    if (v.isNaN) return 0;
    final span = valueMax - valueMin;
    if (span <= 0) return 0;
    final t = (v - valueMin) / span;
    return t < 0 ? 0 : (t > 1 ? 1 : t);
  }

  /// Compact payload for the JS scalar renderer.
  Map<String, dynamic> toBridgeJson() {
    return {
      'nx': nx,
      'ny': ny,
      'lon0': lon0,
      'lat0': lat0,
      'dlon': dlon,
      'dlat': dlat,
      'valueMin': valueMin,
      'valueMax': valueMax,
      'palette': paletteId,
      'domain': domain.id,
      'label': label,
      'caption': caption,
      'units': units,
      'isLive': isLive,
      if (referenceTime != null) 'referenceTime': referenceTime,
      // Item 8: crisp-choropleth hint for the scalar renderers.
      if (choropleth) 'choropleth': true,
      if (choropleth) 'choroplethSteps': choroplethSteps,
      'values': values,
    };
  }
}

/// One value-bearing point for the point renderer.
final class EarthScalarPoint {
  const EarthScalarPoint({
    required this.lat,
    required this.lon,
    required this.value,
    this.label,
    this.count = 1,
    this.members = const [],
    this.bio = false,
  });

  final double lat;
  final double lon;
  final double value;
  final String? label;

  /// Item 5: this point is a folded-in BIODIVERSITY richness dot (rendered inside
  /// the Protected Areas annotation as a LARGER, alt-colour dot). The standalone
  /// biodiversity layer is dropped from the picker; its points ride here.
  final bool bio;

  /// How many underlying records this marker represents. 1 = a single record;
  /// >1 = a spatial CLUSTER (the renderer draws a larger dot, and the snapshot
  /// offers a "browse in Data View" path instead of one record's detail). Used
  /// by the Berkeley VCM carbon layer to collapse dense metro blobs into one
  /// count-sized dot (perf + de-clutter).
  final int count;

  /// Item 3: the governed LABEL of each underlying member of THIS cluster dot
  /// (capped at build time). The click snapshot lists exactly these — the dot's
  /// own members — instead of a country rollup, so a 2-member dot shows 2.
  /// Empty for a single record or an un-enriched (legacy) asset.
  final List<String> members;

  bool get isCluster => count > 1;
}

/// A set of masked markers sized/coloured by value (wildfire, biodiversity).
final class EarthPointSet with _EarthLayerHonesty {
  const EarthPointSet({
    required this.points,
    required this.valueMin,
    required this.valueMax,
    required this.units,
    required this.paletteId,
    required this.domain,
    required this.label,
    required this.attribution,
    required this.source,
    this.isLive = false,
    this.referenceTime,
    this.interactive = true,
    this.markerShape,
    this.renderMode,
  });

  factory EarthPointSet.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map).cast<String, dynamic>();
    final pts = (json['points'] as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return EarthScalarPoint(
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        value: (m['value'] as num).toDouble(),
        label: m['label'] as String?,
        count: (m['count'] as num?)?.toInt() ?? 1,
        members: (m['members'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [],
        bio: (m['bio'] == 1 || m['bio'] == true),
      );
    }).toList();
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final p in pts) {
      if (p.value < lo) lo = p.value;
      if (p.value > hi) hi = p.value;
    }
    return EarthPointSet(
      points: pts,
      valueMin: (meta['valueMin'] as num?)?.toDouble() ??
          (lo.isFinite ? lo : 0),
      valueMax: (meta['valueMax'] as num?)?.toDouble() ??
          (hi.isFinite ? hi : 1),
      units: (meta['units'] as String?) ?? '',
      paletteId: (meta['palette'] as String?) ?? EarthRendererPalettes.fire,
      domain: switch (meta['domain'] as String?) {
        'ocean' => EarthLayerDomain.ocean,
        'land-coastal' => EarthLayerDomain.landCoastal,
        'global' => EarthLayerDomain.global,
        _ => EarthLayerDomain.land,
      },
      label: (meta['label'] as String?) ?? 'representative points',
      attribution: (meta['attribution'] as String?) ?? '',
      source: (meta['source'] as String?) ?? '',
      isLive: (meta['liveReady'] as bool?) ?? (meta['isLive'] as bool?) ?? false,
      referenceTime: meta['referenceTime'] as String?,
      interactive: (meta['interactive'] as bool?) ?? true,
      // Optional per-layer marker glyph (e.g. 'diamond' for boats); null = the
      // default circle. Renderers fall back to a circle for any unknown value.
      markerShape: meta['shape'] as String?,
      // Optional render mode ('orbital' = elevated LEO/MEO/GEO shells for the
      // satellites layer); null = the default surface markers.
      renderMode: meta['render'] as String?,
    );
  }

  final List<EarthScalarPoint> points;
  final double valueMin;
  final double valueMax;
  final String units;
  final String paletteId;
  final EarthLayerDomain domain;

  @override
  final String label;
  final String attribution;
  @override
  final String source;
  @override
  final bool isLive;
  @override
  final String? referenceTime;

  /// Whether a click on a marker opens the snapshot card. False for AMBIENT
  /// mobility layers (flights / boats) — they render as non-trackable flow dots
  /// with no per-point click, readout, or tooltip (governance lock). A click
  /// falls through to the lat/long flow probe instead of selecting an aircraft.
  final bool interactive;

  /// Optional marker glyph for this layer ('diamond' for boats). Null renders
  /// the default circle. Carried to both renderers via [toBridgeJson].
  final String? markerShape;

  /// Optional render mode. 'orbital' draws the points as elevated LEO/MEO/GEO
  /// orbit shells (the satellites layer) instead of surface markers. Null = the
  /// default surface point markers. Carried to both renderers via [toBridgeJson].
  final String? renderMode;

  int get pointCount => points.length;

  /// Item A/flights — render as an AMBIENT, non-trackable layer: mark it
  /// non-interactive and decimate evenly to at most [maxPoints] so it reads as
  /// flow, not as followable individual targets. Identity is already absent (the
  /// model only carries lat/lon/value); this enforces the rest client-side.
  EarthPointSet ambient({int? maxPoints}) {
    var pts = points;
    if (maxPoints != null && maxPoints > 0 && points.length > maxPoints) {
      final stride = (points.length / maxPoints).ceil();
      pts = [
        for (var i = 0; i < points.length; i += stride) points[i],
      ];
    }
    return EarthPointSet(
      points: pts,
      valueMin: valueMin,
      valueMax: valueMax,
      units: units,
      paletteId: paletteId,
      domain: domain,
      label: label,
      attribution: attribution,
      source: source,
      isLive: isLive,
      referenceTime: referenceTime,
      interactive: false,
      markerShape: markerShape,
      renderMode: renderMode,
    );
  }

  /// Returns a copy with display-only overrides ([paletteId] / [markerShape]).
  /// Used for the T1 (E) client-side reskins (glaciers→ice, flights→triangle)
  /// applied at the frame resolver, independent of the data feed.
  EarthPointSet withDisplay(
          {String? paletteId, String? markerShape, String? renderMode}) =>
      EarthPointSet(
        points: points,
        valueMin: valueMin,
        valueMax: valueMax,
        units: units,
        paletteId: paletteId ?? this.paletteId,
        domain: domain,
        label: label,
        attribution: attribution,
        source: source,
        isLive: isLive,
        referenceTime: referenceTime,
        interactive: interactive,
        markerShape: markerShape ?? this.markerShape,
        renderMode: renderMode ?? this.renderMode,
      );

  double normalize(double v) {
    final span = valueMax - valueMin;
    if (span <= 0) return 0;
    final t = (v - valueMin) / span;
    return t < 0 ? 0 : (t > 1 ? 1 : t);
  }

  Map<String, dynamic> toBridgeJson() {
    return {
      'palette': paletteId,
      'domain': domain.id,
      'valueMin': valueMin,
      'valueMax': valueMax,
      'label': label,
      'caption': caption,
      'units': units,
      'isLive': isLive,
      // Ambient mobility layers (flights/boats) are non-interactive — the
      // renderer skips hit-testing so there is no per-point click/readout.
      'interactive': interactive,
      // Optional marker glyph ('diamond' for boats); renderers default to circle.
      if (markerShape != null) 'shape': markerShape,
      // Optional render mode ('orbital' = elevated LEO/MEO/GEO satellite shells).
      if (renderMode != null) 'render': renderMode,
      // Orbital layers carry the SHARED schematic ring spec (band radii / tilts /
      // colours) so both renderers draw identical concentric rings — the single
      // source of truth is EarthOrbitRingSpec, never hand-copied into the JS.
      if (renderMode == 'orbital') 'rings': EarthOrbitRingSpec.bridgeRings,
      if (referenceTime != null) 'referenceTime': referenceTime,
      'points': [
        for (final p in points)
          {
            'lat': double.parse(p.lat.toStringAsFixed(3)),
            'lon': double.parse(p.lon.toStringAsFixed(3)),
            'value': p.value,
            if (p.label != null) 'label': p.label,
            if (p.count > 1) 'count': p.count,
            // Item 3: carry each cluster dot's own member labels to the renderer
            // so the click snapshot lists THIS dot's members (not a rollup).
            if (p.members.isNotEmpty) 'members': p.members,
            // Item 5: a folded-in biodiversity richness dot (larger, alt-colour).
            if (p.bio) 'bio': 1,
          },
      ],
    };
  }

  /// Peak marker radius scale helper (renderer mirrors this curve).
  double markerScale(double value) => 0.4 + 0.6 * math.sqrt(normalize(value));
}

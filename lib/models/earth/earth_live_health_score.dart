import 'dart:convert';

// LIVE GLOBAL HEALTH SCORE — app-side reader + client recompute for the
// `earth.healthscore.v1` document (`earth/score/health-score.json`) produced by
// the ratified earthHealthScoreRefresh function. Replaces the static
// "78 - viewer-AI-carbon" estimate with canonical per-region + global scores.
//
// The doc carries per-region + global sub-scores (already coverage/exposure
// weighted server-side). The CLIENT recomputes the displayed score REACTIVELY
// on every earth+ filter (region/layer/timeline) by re-weighting the
// already-fetched sub-scores — no refetch. The app's own AI footprint (AIEDS)
// is attached as a SEPARATE field (device-local CO2e, blendedIntoScore:false)
// and is NEVER folded into the planetary number.

/// Direction of a health sub-score signal.
enum EarthLiveScoreDirection { burden, benefit }

EarthLiveScoreDirection _directionFromId(String? s) =>
    s == 'benefit' ? EarthLiveScoreDirection.benefit : EarthLiveScoreDirection.burden;

extension EarthLiveScoreDirectionLabel on EarthLiveScoreDirection {
  String get label =>
      this == EarthLiveScoreDirection.benefit ? 'benefit' : 'burden';
}

/// Maps an earth+ catalog layer id onto its health-signal DOMAIN id (v0.3
/// methodology). Several catalog layers share a domain — air-quality /
/// particulates / chemistry all map to `air`; forest / tree-time to
/// `land-cover` — so selecting any of them isolates the same domain. Layers with
/// no health signal return null (the score stays the full blend on selection).
String? earthHealthSignalForLayer(String? layerId) {
  switch (layerId) {
    case 'air-quality':
    case 'particulates':
    case 'chemistry':
      return 'air';
    case 'forest':
    case 'tree-time':
      return 'land-cover';
    case 'sst':
      return 'ocean';
    case 'wildfires':
      return 'fire';
    case 'glaciers':
      return 'cryosphere';
    case 'biodiversity-habitat':
      return 'biodiversity';
    case 'protected-areas':
      return 'conservation';
    default:
      return null;
  }
}

/// The sub-score ids that belong to each v0.3 domain — INCLUDING the legacy v0.2
/// flat ids. This lets isolation degrade gracefully across the deploy boundary:
/// against a v0.3 doc the domain id matches its own sub-score; against a still-
/// live v0.2 doc the legacy members (e.g. air-quality/particulates/chemistry for
/// `air`) match and are blended, so layer isolation keeps working either way.
const Map<String, Set<String>> earthHealthDomainMembers = {
  'air': {'air', 'air-quality', 'particulates', 'chemistry'},
  'land-cover': {'land-cover', 'forest', 'tree-time'},
  // v0.4: ocean WARMING (SST) and ocean ACIDIFICATION (aragonite Ω) are separate
  // domains. `sst` stays an `ocean` (warming) member for v0.2/v0.3 doc isolation.
  'ocean': {'ocean', 'sst'},
  'ocean-acidification': {'ocean-acidification', 'aragonite'},
  'fire': {'fire', 'wildfire'},
  'biodiversity': {'biodiversity'},
  'cryosphere': {'cryosphere', 'glaciers'},
  'conservation': {'conservation', 'protected-areas'},
  // v0.6: Anthroposphere pressure (human modification / density).
  'human': {'human', 'human-encroachment', 'human-density'},
};

/// One per-layer health sub-score.
final class EarthLiveSubScore {
  const EarthLiveSubScore({
    required this.layerId,
    required this.normalized,
    required this.direction,
    required this.weight,
    this.controlValue,
  });

  final String layerId;
  final double normalized; // 0..100 health (100 = healthiest)
  final EarthLiveScoreDirection direction;
  final double weight; // methodology weight (pre-renormalization)

  /// The raw planetary-boundary CONTROL VALUE this health was derived from
  /// (e.g. PM2.5 µg/m³, forest cover %, aragonite Ω) — DISPLAY-ONLY transparency
  /// (item G), published additively by the score function. Null on older docs.
  final double? controlValue;

  factory EarthLiveSubScore.fromJson(Map<String, dynamic> j) => EarthLiveSubScore(
        layerId: (j['layerId'] ?? '').toString(),
        normalized: ((j['normalized'] as num?) ?? 0).toDouble(),
        direction: _directionFromId(j['direction'] as String?),
        weight: ((j['weight'] as num?) ?? 0).toDouble(),
        controlValue: (j['controlValue'] as num?)?.toDouble(),
      );
}

/// A scored region (or the global rollup).
final class EarthLiveRegionScore {
  const EarthLiveRegionScore({
    required this.label,
    required this.score,
    required this.trend,
    required this.confidence,
    required this.exposure,
    required this.subScores,
  });

  final String label;
  final double score; // 0..100, coverage-weighted over available sub-scores
  final String trend; // improving|stable|worsening|unknown
  final double confidence; // 0..1 = covered weight / total methodology weight
  final double exposure;
  final List<EarthLiveSubScore> subScores;

  factory EarthLiveRegionScore.fromJson(
    Map<String, dynamic> j, {
    String? fallbackLabel,
  }) {
    final subs = ((j['subScores'] as List?) ?? const [])
        .map((e) => EarthLiveSubScore.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return EarthLiveRegionScore(
      label: (j['label'] as String?) ?? fallbackLabel ?? '',
      score: ((j['score'] as num?) ?? 0).toDouble(),
      trend: (j['trend'] as String?) ?? 'unknown',
      confidence: ((j['confidence'] as num?) ?? 0).toDouble(),
      exposure: ((j['exposure'] as num?) ?? 1).toDouble(),
      subScores: subs,
    );
  }
}

/// Parsed `earth.healthscore.v1` document.
final class EarthLiveHealthScore {
  const EarthLiveHealthScore({
    required this.schema,
    required this.methodologyVersion,
    required this.generatedAt,
    required this.label,
    required this.disclosure,
    required this.isLive,
    required this.weights,
    required this.global,
    required this.regions,
    required this.aiedsServerCo2eGrams,
    required this.aiedsBlendedIntoScore,
  });

  static const schemaId = 'earth.healthscore.v1';

  final String schema;
  final String methodologyVersion;
  final String generatedAt;
  final String label;
  final String disclosure;
  final bool isLive;
  final Map<String, double> weights;
  final EarthLiveRegionScore global;
  final Map<String, EarthLiveRegionScore> regions;

  /// Server contract slot for the AIEDS footprint — normally null (the CLIENT
  /// fills the device value). Never blended into [global.score].
  final double? aiedsServerCo2eGrams;
  final bool aiedsBlendedIntoScore; // MUST be false (governance invariant)

  double get totalWeight => weights.values.fold<double>(0, (a, b) => a + b);

  factory EarthLiveHealthScore.fromJson(Map<String, dynamic> json) {
    final meta = ((json['meta'] as Map?) ?? const {}).cast<String, dynamic>();
    final globalJson =
        ((json['global'] as Map?) ?? const {}).cast<String, dynamic>();
    final aieds =
        ((globalJson['aiedsFactor'] as Map?) ?? const {}).cast<String, dynamic>();
    final regionsJson =
        ((json['regions'] as Map?) ?? const {}).cast<String, dynamic>();
    final regions = <String, EarthLiveRegionScore>{};
    regionsJson.forEach((id, v) {
      regions[id.toString()] = EarthLiveRegionScore.fromJson(
        (v as Map).cast<String, dynamic>(),
        fallbackLabel: id.toString(),
      );
    });
    final weights = <String, double>{};
    ((meta['weights'] as Map?) ?? const {}).forEach((k, v) {
      if (v is num) weights[k.toString()] = v.toDouble();
    });
    return EarthLiveHealthScore(
      schema: (meta['schema'] as String?) ?? schemaId,
      methodologyVersion: (meta['methodologyVersion'] as String?) ?? '0',
      generatedAt: (meta['generatedAt'] as String?) ?? '',
      label: (meta['label'] as String?) ?? 'Experimental Earth Health Score',
      disclosure: (meta['disclosure'] as String?) ?? '',
      isLive: (meta['isLive'] as bool?) ?? false,
      weights: weights,
      global: EarthLiveRegionScore.fromJson(globalJson, fallbackLabel: 'Global'),
      regions: regions,
      aiedsServerCo2eGrams: (aieds['estimatedCo2eGrams'] as num?)?.toDouble(),
      aiedsBlendedIntoScore: (aieds['blendedIntoScore'] as bool?) ?? false,
    );
  }

  factory EarthLiveHealthScore.parse(String raw) =>
      EarthLiveHealthScore.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Re-weight the already-fetched sub-scores for the current earth+ filter and
  /// attach the SEPARATE device AIEDS footprint.
  ///
  /// - region drives the base score (`global` -> the exposure-weighted rollup;
  ///   any other id -> that region, falling back to global if absent).
  /// - a selected health-signal layer ISOLATES that sub-score (re-weight to
  ///   1.0) so the gauge moves per layer; non-health layers keep the full blend.
  /// - timeWindowLabel is carried for display only — v0.1 is a snapshot, so no
  ///   time-trend is fabricated (data-binding honesty).
  /// - confidence stays the region's data coverage (fail-soft).
  EarthLiveScoreView recompute({
    required String regionId,
    String? selectedLayerId,
    String? timeWindowLabel,
    double aiedsCo2eGramsDevice = 0,
  }) {
    final base = regionId == 'global' ? global : (regions[regionId] ?? global);
    return _viewFrom(
      base: base,
      regionId: regionId,
      selectedLayerId: selectedLayerId,
      timeWindowLabel: timeWindowLabel,
      aiedsCo2eGramsDevice: aiedsCo2eGramsDevice,
    );
  }

  /// GLOBAL Health Score — ALWAYS the global rollup, region-INDEPENDENT. The
  /// region filter never changes it; it is reactive to the selected layer +
  /// timeline only (two-score redesign: the full progress ring).
  EarthLiveScoreView recomputeGlobal({
    String? selectedLayerId,
    String? timeWindowLabel,
    double aiedsCo2eGramsDevice = 0,
  }) {
    return _viewFrom(
      base: global,
      regionId: 'global',
      selectedLayerId: selectedLayerId,
      timeWindowLabel: timeWindowLabel,
      aiedsCo2eGramsDevice: aiedsCo2eGramsDevice,
    );
  }

  /// REGIONAL Health Score — a SPECIFIC region only; NEVER the global rollup
  /// (two-score redesign: the radial half-ring). [regionId] should be a real
  /// region (the caller passes the user-location nearest region as the
  /// default); 'global'/unknown falls back to the first available region so the
  /// regional score is never the global aggregate.
  EarthLiveScoreView recomputeRegional({
    required String regionId,
    String? selectedLayerId,
    String? timeWindowLabel,
    double aiedsCo2eGramsDevice = 0,
  }) {
    final id = (regionId == 'global' || !regions.containsKey(regionId))
        ? (firstRegionId ?? regionId)
        : regionId;
    final base = regions[id] ?? global;
    return _viewFrom(
      base: base,
      regionId: id,
      selectedLayerId: selectedLayerId,
      timeWindowLabel: timeWindowLabel,
      aiedsCo2eGramsDevice: aiedsCo2eGramsDevice,
    );
  }

  /// First non-global region id in the doc (the regional-score default basis),
  /// or null when the doc carries only the global rollup.
  String? get firstRegionId {
    for (final k in regions.keys) {
      if (k != 'global') return k;
    }
    return null;
  }

  EarthLiveScoreView _viewFrom({
    required EarthLiveRegionScore base,
    required String regionId,
    String? selectedLayerId,
    String? timeWindowLabel,
    double aiedsCo2eGramsDevice = 0,
  }) {
    final signalId = earthHealthSignalForLayer(selectedLayerId);
    // Isolate to the selected DOMAIN: gather every present sub-score that belongs
    // to it (its own id in a v0.3 doc; the legacy flat ids in a v0.2 doc) and
    // show their coverage-weighted blend. One member in v0.3 -> the domain value.
    final members =
        signalId == null ? null : (earthHealthDomainMembers[signalId] ?? {signalId});
    final isolatedSubs = members == null
        ? const <EarthLiveSubScore>[]
        : base.subScores.where((s) => members.contains(s.layerId)).toList();

    final List<EarthLiveSubScore> shown;
    final double score;
    if (isolatedSubs.isNotEmpty) {
      shown = isolatedSubs;
      final w = isolatedSubs.fold<double>(0, (a, s) => a + s.weight);
      score = w > 0
          ? isolatedSubs.fold<double>(0, (a, s) => a + s.normalized * s.weight) / w
          : isolatedSubs.first.normalized;
    } else {
      shown = base.subScores;
      score = base.score; // full coverage-weighted blend
    }

    return EarthLiveScoreView(
      regionId: regionId,
      regionLabel: base.label,
      score: score,
      trend: base.trend,
      confidence: base.confidence,
      subScores: shown,
      isolatedLayerId: isolatedSubs.isNotEmpty ? signalId : null,
      timeWindowLabel: timeWindowLabel,
      isLive: isLive,
      aiedsCo2eGramsDevice: aiedsCo2eGramsDevice,
      totalWeight: totalWeight,
      totalSignals: weights.length,
    );
  }
}

/// The recomputed view the gauge + chips render. `score` is the planetary
/// number; `aiedsCo2eGramsDevice` is the SEPARATE device footprint and is never
/// part of `score`.
final class EarthLiveScoreView {
  const EarthLiveScoreView({
    required this.regionId,
    required this.regionLabel,
    required this.score,
    required this.trend,
    required this.confidence,
    required this.subScores,
    required this.isLive,
    required this.aiedsCo2eGramsDevice,
    required this.totalWeight,
    required this.totalSignals,
    this.isolatedLayerId,
    this.timeWindowLabel,
  });

  final String regionId;
  final String regionLabel;
  final double score; // 0..100
  final String trend; // improving|stable|worsening|unknown
  final double confidence; // 0..1 coverage
  final List<EarthLiveSubScore> subScores;
  final bool isLive;
  final double aiedsCo2eGramsDevice; // device-local; NEVER blended into score
  final double totalWeight;
  final int totalSignals; // total methodology signals in the doc (for "N of M")
  final String? isolatedLayerId; // non-null when isolated to one signal
  final String? timeWindowLabel;

  /// Governance invariant: the AIEDS footprint is never part of the score.
  bool get aiedsBlendedIntoScore => false;
  bool get isIsolated => isolatedLayerId != null;

  int get scoreRounded => score.round().clamp(0, 100);
  String get scoreLabel => '$scoreRounded/100';
  int get coveragePct => (confidence * 100).round().clamp(0, 100);

  /// Number of signals actually present (covered) in this view.
  int get coveredSignals => subScores.length;

  /// Sum of the present sub-score weights — the renormalization denominator.
  double get presentWeight => subScores.fold<double>(0, (a, s) => a + s.weight);

  /// A sub-score's weight renormalized over the PRESENT signals, so the shown
  /// contributions (normalized × renorm weight) sum exactly to the blended
  /// score. 0 when nothing is present. This is the fix for the breakdown not
  /// reconciling to the headline: rows now add up to the score directly.
  double renormalizedWeight(EarthLiveSubScore s) {
    final denom = presentWeight;
    return denom > 0 ? s.weight / denom : 0;
  }
}

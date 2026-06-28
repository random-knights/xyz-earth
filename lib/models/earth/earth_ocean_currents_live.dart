// lib/models/earth/earth_ocean_currents_live.dart
//
// Governed ocean-currents live-feed models for the Earth-Systems data
// vertical. Mirrors the weather/wind live-provider shape: a normalized
// provider fixture plus an adapter that emits a guarded EarthLayerSnapshot
// with freshness, attribution, and license fields. Ocean stays
// health/trend-neutral: snapshots never feed the Earth health score.

import 'package:xyz_earth/models/earth/earth_layer_snapshot.dart';

final class EarthOceanCurrentsProviderFixture {
  const EarthOceanCurrentsProviderFixture({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.validFrom,
    required this.validTo,
    required this.currentVelocityKmh,
    required this.currentDirectionDegrees,
    required this.seaSurfaceTempC,
    required this.waveHeightM,
    required this.regionId,
    required this.regionLabel,
    required this.sourceLabel,
    required this.caveats,
  });

  final String id;
  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final DateTime validFrom;
  final DateTime validTo;
  final double currentVelocityKmh;
  final int currentDirectionDegrees;
  final double seaSurfaceTempC;
  final double waveHeightM;
  final String regionId;
  final String regionLabel;
  final String sourceLabel;
  final List<String> caveats;

  String get generalizedCoordinateLabel {
    return '${latitude.toStringAsFixed(1)}, ${longitude.toStringAsFixed(1)} '
        'generalized';
  }

  String get currentVelocityLabel => currentVelocityKmh.toStringAsFixed(1);

  String get currentDirectionLabel => '$currentDirectionDegrees deg';

  String get seaSurfaceTempLabel => seaSurfaceTempC.toStringAsFixed(1);

  String get waveHeightLabel => waveHeightM.toStringAsFixed(1);

  static final javaSeaPreview = EarthOceanCurrentsProviderFixture(
    id: 'fixture-open-meteo-marine-shaped-java-sea-2026-06-06',
    latitude: -5.8,
    longitude: 107.0,
    capturedAt: EarthLayerSnapshotFixtures.capturedAt,
    validFrom: EarthLayerSnapshotFixtures.capturedAt,
    validTo: EarthLayerSnapshotFixtures.capturedAt.add(
      const Duration(hours: 6),
    ),
    currentVelocityKmh: 1.4,
    currentDirectionDegrees: 96,
    seaSurfaceTempC: 29.1,
    waveHeightM: 0.8,
    regionId: 'indonesia',
    regionLabel: 'Indonesia',
    sourceLabel: 'Open-Meteo-Marine-shaped preview fixture',
    caveats: EarthOceanCurrentsSnapshotAdapter.fixtureGuardrails,
  );
}

abstract final class EarthOceanCurrentsSnapshotAdapter {
  static const fixtureGuardrails = [
    'Preview Fixture',
    'Preview Only',
    'Not Live Data',
    'No Live Provider Lookup',
    'Not Provider Verified',
    'No Verified Environmental Claims',
    'Health/Trend Neutral',
  ];

  static const openMeteoMarineLicense = EarthLayerLicense(
    label: 'Open-Meteo CC BY 4.0 data / commercial subscription gated',
    url: 'https://open-meteo.com/en/terms',
    usageSummary:
        'Free Marine API is non-commercial and rate limited; production commercial app use requires approved subscription/API-key handling.',
    commercialUseAllowed: false,
    redistributionAllowed: true,
    requiresAttribution: true,
  );

  static const openMeteoMarineAttribution = EarthLayerAttribution(
    providerName: 'Open-Meteo Marine',
    sourceTitle: 'Marine API ocean current, wave, and sea-surface data',
    sourceUrl: 'https://open-meteo.com/en/docs/marine-weather-api',
    citation:
        'Provider-backed Open-Meteo Marine response normalized for educational Earth preview; not verified by Random Knights.',
  );

  static const openMeteoMarineSource = EarthProviderSource(
    id: 'open-meteo-marine-ocean-currents',
    name: 'Open-Meteo Marine Ocean Currents',
    access: EarthProviderSourceAccess.serverCached,
    sourceUrl: 'https://open-meteo.com/en/docs/marine-weather-api',
    attribution: openMeteoMarineAttribution,
    license: openMeteoMarineLicense,
    updateCadence:
        'Marine current/wave timeseries; low-volume guarded request with 30 minute runtime cache.',
    caveats: fixtureGuardrails,
    requiresServerBoundary: false,
    liveLookupEnabled: true,
  );

  static final fixtureFreshness = EarthLayerFreshness.previewFixture(
    cacheKey: 'fixture:earth-systems:open-meteo-marine:ocean-currents:java-sea',
    sourceUpdateCadence:
        'fixture only; live cadence is a guarded 30 minute runtime cache',
    lastRefreshLabel: 'Preview fixture generated for ocean-currents live slice',
  );

  static final sourceDefinition = EarthLayerSourceDefinition(
    layerId: 'ocean-currents',
    layerName: 'Ocean Currents Live',
    group: EarthLayerGroup.earthSystems,
    source: openMeteoMarineSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.point,
      EarthLayerSnapshotRecordType.path,
      EarthLayerSnapshotRecordType.metricSummary,
      EarthLayerSnapshotRecordType.eventMarker,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.motionLayer,
        label: 'Circulating current flow',
        summary:
            'Normalized current velocity/direction can drive the symbolic circulating motion cue.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.focusRegion,
        label: 'Focused ocean basin',
        summary:
            'Ocean snapshots focus a broad basin/region without precise marine geometry.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.rightSideSummary,
        label: 'Ocean systems summary',
        summary:
            'Right-side summary can show source, freshness, attribution, and caveats.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.contextPanelDetail,
        label: 'Ocean context panel',
        summary:
            'Context panel can show validity window, license, and health-neutral boundary.',
      ),
    ],
    freshnessPolicy: fixtureFreshness,
    safetyBoundaries: fixtureGuardrails,
    liveProviderEnabled: true,
  );

  static EarthLayerSnapshot fromFixture(
    EarthOceanCurrentsProviderFixture fixture, {
    EarthLayerFreshness? freshness,
    EarthLayerSnapshotConfidence confidence =
        EarthLayerSnapshotConfidence.fixture,
    EarthLayerAttribution? attribution,
    String? dataKind,
    String? precisionScope,
    String? geometryPolicy,
    List<String>? guardrailsOverride,
    List<String> additionalCaveats = const [
      'Open-Meteo-Marine Shaped Fixture',
    ],
  }) {
    final guardrailLabels = guardrailsOverride ?? fixtureGuardrails;
    final scope = EarthLayerSnapshotScope(
      regionId: fixture.regionId,
      regionLabel: fixture.regionLabel,
    );
    final snapshotFreshness = freshness ?? fixtureFreshness;
    final validWindow =
        '${_utcLabel(fixture.validFrom)} -> ${_utcLabel(fixture.validTo)}';

    return EarthLayerSnapshot(
      id: 'snapshot-${fixture.id}',
      layerId: sourceDefinition.layerId,
      layerGroup: sourceDefinition.group,
      sourceId: openMeteoMarineSource.id,
      scope: scope,
      capturedAt: fixture.capturedAt,
      validFrom: fixture.validFrom,
      validTo: fixture.validTo,
      metadata: EarthLayerSnapshotMetadata(
        freshness: snapshotFreshness,
        confidence: confidence,
        precisionScope:
            precisionScope ?? 'generalized coordinate and broad basin only',
        dataKind: dataKind ?? 'Open-Meteo-Marine-shaped fixture',
        geometryPolicy: geometryPolicy ??
            'generalized marker, symbolic circulating path, metric summaries',
        guardrails: guardrailLabels,
      ),
      attribution: attribution ?? openMeteoMarineAttribution,
      license: openMeteoMarineLicense,
      records: [
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-region',
          type: EarthLayerSnapshotRecordType.regionLabel,
          label: '${fixture.regionLabel} ocean-currents region',
          summary:
              'Broad basin/region routing label for the governed ocean-currents feed.',
          scope: scope,
          precisionLabel: 'broad region label',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.focusRegion,
              label: 'Focus mapped basin',
              summary: 'Focuses the existing globe region selection.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-point',
          type: EarthLayerSnapshotRecordType.point,
          label: 'Generalized ocean marker',
          summary:
              '${fixture.sourceLabel}; coordinate ${fixture.generalizedCoordinateLabel}; not a precise observation.',
          scope: scope,
          precisionLabel: 'generalized marker; no precise coordinate claim',
          valueLabel: fixture.seaSurfaceTempLabel,
          unitLabel: 'C',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.overlayMarker,
              label: 'Generalized ocean marker',
              summary:
                  'Overlay marker shows broad ocean context without raw geometry.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-flow',
          type: EarthLayerSnapshotRecordType.path,
          label: 'Symbolic current flow hint',
          summary:
              'Current velocity ${fixture.currentVelocityLabel} km/h at ${fixture.currentDirectionLabel}; symbolic circulating motion only.',
          scope: scope,
          precisionLabel: 'symbolic path only',
          valueLabel: fixture.currentVelocityLabel,
          unitLabel: 'km/h',
          pathLabels: const [
            'western basin cell',
            'central basin cell',
            'eastern basin cell',
          ],
          eventTimeLabel: validWindow,
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.motionLayer,
              label: 'Circulating flow layer',
              summary: 'Motion layer can use symbolic current emphasis.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-sst',
          type: EarthLayerSnapshotRecordType.metricSummary,
          label: 'Sea-surface temperature summary',
          summary:
              'Normalized sea-surface temperature; descriptive only, health/trend neutral.',
          scope: scope,
          precisionLabel: 'normalized metric only',
          valueLabel: fixture.seaSurfaceTempLabel,
          unitLabel: 'C',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.rightSideSummary,
              label: 'Sea-surface temperature',
              summary: 'Right panel can show the normalized temperature.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-wave-height',
          type: EarthLayerSnapshotRecordType.metricSummary,
          label: 'Wave height summary',
          summary:
              'Normalized wave height; descriptive only, health/trend neutral.',
          scope: scope,
          precisionLabel: 'normalized metric only',
          valueLabel: fixture.waveHeightLabel,
          unitLabel: 'm',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.rightSideSummary,
              label: 'Wave height',
              summary: 'Right panel can show the normalized wave height.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-ocean-currents-valid-window',
          type: EarthLayerSnapshotRecordType.eventMarker,
          label: 'Ocean-currents validity window',
          summary: 'Captured and valid-to labels for snapshot freshness only.',
          scope: scope,
          precisionLabel: 'snapshot time label only',
          eventTimeLabel: validWindow,
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.contextPanelDetail,
              label: 'Validity context',
              summary:
                  'Context panel can show captured and validity labels.',
            ),
          ],
          caveats: guardrailLabels,
        ),
      ],
      visualizationHints: sourceDefinition.defaultVisualizationHints,
      caveats: [
        ...guardrailLabels,
        ...additionalCaveats,
      ],
    );
  }

  static String _utcLabel(DateTime value) {
    return value.toUtc().toIso8601String().replaceFirst('.000Z', 'Z');
  }
}

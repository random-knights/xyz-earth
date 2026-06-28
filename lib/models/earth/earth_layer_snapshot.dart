enum EarthLayerGroup {
  earthSystems,
  environmental,
  humanActivity,
  projects,
  entities,
  intelligence,
}

extension EarthLayerGroupLabels on EarthLayerGroup {
  String get id {
    return switch (this) {
      EarthLayerGroup.earthSystems => 'earth-systems',
      EarthLayerGroup.environmental => 'environmental',
      EarthLayerGroup.humanActivity => 'human-activity',
      EarthLayerGroup.projects => 'projects',
      EarthLayerGroup.entities => 'entities',
      EarthLayerGroup.intelligence => 'intelligence',
    };
  }

  String get label {
    return switch (this) {
      EarthLayerGroup.earthSystems => 'Earth Systems',
      EarthLayerGroup.environmental => 'Environmental',
      EarthLayerGroup.humanActivity => 'Human Activity',
      EarthLayerGroup.projects => 'Projects',
      EarthLayerGroup.entities => 'Entities',
      EarthLayerGroup.intelligence => 'Intelligence',
    };
  }
}

enum EarthProviderSourceAccess {
  previewFixture,
  publicMetadata,
  serverCached,
  restricted,
}

extension EarthProviderSourceAccessLabels on EarthProviderSourceAccess {
  String get label {
    return switch (this) {
      EarthProviderSourceAccess.previewFixture => 'Preview Fixture',
      EarthProviderSourceAccess.publicMetadata => 'Public Metadata',
      EarthProviderSourceAccess.serverCached => 'Server Cached',
      EarthProviderSourceAccess.restricted => 'Restricted',
    };
  }
}

enum EarthLayerFreshnessState {
  fresh,
  stale,
  expired,
  unavailable,
  previewFixture,
}

extension EarthLayerFreshnessStateLabels on EarthLayerFreshnessState {
  String get label {
    return switch (this) {
      EarthLayerFreshnessState.fresh => 'Fresh',
      EarthLayerFreshnessState.stale => 'Stale',
      EarthLayerFreshnessState.expired => 'Expired',
      EarthLayerFreshnessState.unavailable => 'Unavailable',
      EarthLayerFreshnessState.previewFixture => 'Preview Fixture',
    };
  }
}

enum EarthLayerSnapshotConfidence {
  low,
  medium,
  high,
  unknown,
  fixture,
}

extension EarthLayerSnapshotConfidenceLabels on EarthLayerSnapshotConfidence {
  String get label {
    return switch (this) {
      EarthLayerSnapshotConfidence.low => 'low',
      EarthLayerSnapshotConfidence.medium => 'medium',
      EarthLayerSnapshotConfidence.high => 'high',
      EarthLayerSnapshotConfidence.unknown => 'unknown',
      EarthLayerSnapshotConfidence.fixture => 'preview fixture',
    };
  }
}

enum EarthLayerSnapshotRecordType {
  point,
  regionLabel,
  path,
  gridSummary,
  eventMarker,
  metricSummary,
}

extension EarthLayerSnapshotRecordTypeLabels on EarthLayerSnapshotRecordType {
  String get label {
    return switch (this) {
      EarthLayerSnapshotRecordType.point => 'point',
      EarthLayerSnapshotRecordType.regionLabel => 'region label',
      EarthLayerSnapshotRecordType.path => 'path',
      EarthLayerSnapshotRecordType.gridSummary => 'grid summary',
      EarthLayerSnapshotRecordType.eventMarker => 'event marker',
      EarthLayerSnapshotRecordType.metricSummary => 'metric summary',
    };
  }
}

enum EarthLayerVisualizationTarget {
  overlayMarker,
  motionLayer,
  focusRegion,
  timelineEvent,
  rightSideSummary,
  contextPanelDetail,
  layerControls,
}

extension EarthLayerVisualizationTargetLabels on EarthLayerVisualizationTarget {
  String get label {
    return switch (this) {
      EarthLayerVisualizationTarget.overlayMarker => 'overlay marker',
      EarthLayerVisualizationTarget.motionLayer => 'motion layer',
      EarthLayerVisualizationTarget.focusRegion => 'focus region',
      EarthLayerVisualizationTarget.timelineEvent => 'timeline event',
      EarthLayerVisualizationTarget.rightSideSummary => 'right-side summary',
      EarthLayerVisualizationTarget.contextPanelDetail =>
        'context panel detail',
      EarthLayerVisualizationTarget.layerControls => 'layer controls',
    };
  }
}

const earthLayerSnapshotPreviewGuardrails = [
  'Preview Fixture',
  'Preview Only',
  'Not Live Data',
  'No Live Provider Lookup',
  'Not Provider Verified',
  'No Verified Environmental Claims',
];

final class EarthLayerAttribution {
  const EarthLayerAttribution({
    required this.providerName,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.citation,
    this.requiredLabel = 'Attribution Required',
  });

  final String providerName;
  final String sourceTitle;
  final String? sourceUrl;
  final String citation;
  final String requiredLabel;

  String get displayLabel => '$providerName / $sourceTitle';

  List<String> get summaryLines {
    return [
      displayLabel,
      requiredLabel,
      citation,
      if (sourceUrl != null) sourceUrl!,
    ];
  }
}

final class EarthLayerLicense {
  const EarthLayerLicense({
    required this.label,
    required this.usageSummary,
    required this.commercialUseAllowed,
    required this.redistributionAllowed,
    required this.requiresAttribution,
    this.url,
  });

  final String label;
  final String? url;
  final String usageSummary;
  final bool commercialUseAllowed;
  final bool redistributionAllowed;
  final bool requiresAttribution;

  String get commercialUseLabel =>
      commercialUseAllowed ? 'commercial use allowed' : 'commercial use gated';

  String get redistributionLabel =>
      redistributionAllowed ? 'redistribution allowed' : 'redistribution gated';

  String get attributionLabel =>
      requiresAttribution ? 'attribution required' : 'attribution optional';

  String get summary => '$label / $commercialUseLabel / $redistributionLabel / '
      '$attributionLabel / $usageSummary';
}

final class EarthLayerFreshness {
  const EarthLayerFreshness({
    required this.state,
    required this.cacheKey,
    required this.ttl,
    required this.sourceUpdateCadence,
    required this.lastRefreshLabel,
    required this.providerCaveats,
  });

  factory EarthLayerFreshness.previewFixture({
    required String cacheKey,
    required String sourceUpdateCadence,
    required String lastRefreshLabel,
    List<String> providerCaveats = earthLayerSnapshotPreviewGuardrails,
  }) {
    return EarthLayerFreshness(
      state: EarthLayerFreshnessState.previewFixture,
      cacheKey: cacheKey,
      ttl: Duration.zero,
      sourceUpdateCadence: sourceUpdateCadence,
      lastRefreshLabel: lastRefreshLabel,
      providerCaveats: providerCaveats,
    );
  }

  final EarthLayerFreshnessState state;
  final String cacheKey;
  final Duration ttl;
  final String sourceUpdateCadence;
  final String lastRefreshLabel;
  final List<String> providerCaveats;

  bool get cacheable => cacheKey.trim().isNotEmpty;

  String get stateLabel => state.label;

  String get ttlLabel {
    if (ttl == Duration.zero) return 'no runtime ttl';
    if (ttl.inHours > 0) return '${ttl.inHours}h ttl';
    if (ttl.inMinutes > 0) return '${ttl.inMinutes}m ttl';
    return '${ttl.inSeconds}s ttl';
  }

  List<String> get summaryLines {
    return [
      'freshness: $stateLabel',
      'cache key: $cacheKey',
      'ttl: $ttlLabel',
      'source cadence: $sourceUpdateCadence',
      'last refresh: $lastRefreshLabel',
      ...providerCaveats,
    ];
  }
}

final class EarthProviderSource {
  const EarthProviderSource({
    required this.id,
    required this.name,
    required this.access,
    required this.attribution,
    required this.license,
    required this.updateCadence,
    required this.caveats,
    this.sourceUrl,
    this.requiresServerBoundary = true,
    this.liveLookupEnabled = false,
  });

  final String id;
  final String name;
  final EarthProviderSourceAccess access;
  final String? sourceUrl;
  final EarthLayerAttribution attribution;
  final EarthLayerLicense license;
  final String updateCadence;
  final List<String> caveats;
  final bool requiresServerBoundary;
  final bool liveLookupEnabled;

  bool get previewOnly =>
      access == EarthProviderSourceAccess.previewFixture || !liveLookupEnabled;

  List<String> get guardrailLabels {
    return [
      if (access == EarthProviderSourceAccess.previewFixture) 'Preview Fixture',
      if (previewOnly) 'Preview Only',
      if (!liveLookupEnabled) 'No Live Provider Lookup',
      if (requiresServerBoundary) 'Server Boundary Required',
      ...caveats,
    ];
  }
}

final class EarthLayerVisualizationHint {
  const EarthLayerVisualizationHint({
    required this.target,
    required this.label,
    required this.summary,
    this.enabled = true,
  });

  final EarthLayerVisualizationTarget target;
  final String label;
  final String summary;
  final bool enabled;

  String get targetLabel => target.label;

  String get displayLabel => '$targetLabel: $label';
}

final class EarthLayerSourceDefinition {
  const EarthLayerSourceDefinition({
    required this.layerId,
    required this.layerName,
    required this.group,
    required this.source,
    required this.supportedRecordTypes,
    required this.defaultVisualizationHints,
    required this.freshnessPolicy,
    required this.safetyBoundaries,
    this.liveProviderEnabled = false,
  });

  final String layerId;
  final String layerName;
  final EarthLayerGroup group;
  final EarthProviderSource source;
  final List<EarthLayerSnapshotRecordType> supportedRecordTypes;
  final List<EarthLayerVisualizationHint> defaultVisualizationHints;
  final EarthLayerFreshness freshnessPolicy;
  final List<String> safetyBoundaries;
  final bool liveProviderEnabled;

  String get groupLabel => group.label;

  bool get providerNeutral => !liveProviderEnabled;

  bool supportsRecordType(EarthLayerSnapshotRecordType type) {
    return supportedRecordTypes.contains(type);
  }

  bool mapsTo(EarthLayerVisualizationTarget target) {
    return defaultVisualizationHints.any(
      (hint) => hint.target == target && hint.enabled,
    );
  }
}

final class EarthLayerSnapshotScope {
  const EarthLayerSnapshotScope({
    this.regionId,
    this.regionLabel,
    this.entityId,
    this.entityLabel,
    this.projectId,
    this.projectLabel,
  });

  final String? regionId;
  final String? regionLabel;
  final String? entityId;
  final String? entityLabel;
  final String? projectId;
  final String? projectLabel;

  bool get hasRegion => regionLabel != null;
  bool get hasEntity => entityLabel != null;
  bool get hasProject => projectLabel != null;

  String get label {
    final parts = [
      if (entityLabel != null) 'entity: $entityLabel',
      if (projectLabel != null) 'project: $projectLabel',
      if (regionLabel != null) 'region: $regionLabel',
    ];
    if (parts.isEmpty) return 'global scope';
    return parts.join(' / ');
  }
}

final class EarthLayerSnapshotMetadata {
  const EarthLayerSnapshotMetadata({
    required this.freshness,
    required this.confidence,
    required this.precisionScope,
    required this.dataKind,
    required this.geometryPolicy,
    required this.guardrails,
  });

  final EarthLayerFreshness freshness;
  final EarthLayerSnapshotConfidence confidence;
  final String precisionScope;
  final String dataKind;
  final String geometryPolicy;
  final List<String> guardrails;

  String get freshnessLabel => freshness.stateLabel;

  String get confidenceLabel => confidence.label;

  String get sourceUpdateCadence => freshness.sourceUpdateCadence;

  List<String> get summaryLines {
    return [
      'confidence: $confidenceLabel',
      'precision: $precisionScope',
      'data kind: $dataKind',
      'geometry policy: $geometryPolicy',
      ...freshness.summaryLines,
      ...guardrails,
    ];
  }
}

final class EarthLayerSnapshotRecord {
  const EarthLayerSnapshotRecord({
    required this.id,
    required this.type,
    required this.label,
    required this.summary,
    required this.scope,
    required this.precisionLabel,
    required this.visualizationHints,
    this.valueLabel,
    this.unitLabel,
    this.pathLabels = const [],
    this.eventTimeLabel,
    this.caveats = earthLayerSnapshotPreviewGuardrails,
  });

  final String id;
  final EarthLayerSnapshotRecordType type;
  final String label;
  final String summary;
  final EarthLayerSnapshotScope scope;
  final String precisionLabel;
  final String? valueLabel;
  final String? unitLabel;
  final List<String> pathLabels;
  final String? eventTimeLabel;
  final List<EarthLayerVisualizationHint> visualizationHints;
  final List<String> caveats;

  String get typeLabel => type.label;

  String get valueSummary {
    final value = valueLabel;
    if (value == null) return label;
    final unit = unitLabel;
    return unit == null ? value : '$value $unit';
  }

  List<EarthLayerVisualizationTarget> get visualizationTargets {
    return [
      for (final hint in visualizationHints)
        if (hint.enabled) hint.target,
    ];
  }

  bool mapsTo(EarthLayerVisualizationTarget target) {
    return visualizationTargets.contains(target);
  }

  String get mappingLabel {
    if (visualizationHints.isEmpty) return 'no visualization mapping';
    return visualizationHints.map((hint) => hint.displayLabel).join(' | ');
  }
}

final class EarthLayerSnapshot {
  const EarthLayerSnapshot({
    required this.id,
    required this.layerId,
    required this.layerGroup,
    required this.sourceId,
    required this.scope,
    required this.capturedAt,
    required this.metadata,
    required this.attribution,
    required this.license,
    required this.records,
    required this.visualizationHints,
    required this.caveats,
    this.validFrom,
    this.validTo,
  });

  final String id;
  final String layerId;
  final EarthLayerGroup layerGroup;
  final String sourceId;
  final EarthLayerSnapshotScope scope;
  final DateTime capturedAt;
  final DateTime? validFrom;
  final DateTime? validTo;
  final EarthLayerSnapshotMetadata metadata;
  final EarthLayerAttribution attribution;
  final EarthLayerLicense license;
  final List<EarthLayerSnapshotRecord> records;
  final List<EarthLayerVisualizationHint> visualizationHints;
  final List<String> caveats;

  String get layerGroupLabel => layerGroup.label;

  String get confidenceLabel => metadata.confidenceLabel;

  String get freshnessLabel => metadata.freshnessLabel;

  bool get previewFixture =>
      metadata.freshness.state == EarthLayerFreshnessState.previewFixture;

  List<EarthLayerSnapshotRecord> recordsForType(
    EarthLayerSnapshotRecordType type,
  ) {
    return records.where((record) => record.type == type).toList(
          growable: false,
        );
  }

  List<EarthLayerSnapshotRecord> recordsForTarget(
    EarthLayerVisualizationTarget target,
  ) {
    return records.where((record) => record.mapsTo(target)).toList(
          growable: false,
        );
  }

  String get guardrailSummary {
    final labels = {
      ...metadata.guardrails,
      ...metadata.freshness.providerCaveats,
      ...caveats,
    };
    return labels.join(' | ');
  }
}

abstract final class EarthLayerSnapshotFixtures {
  static final DateTime capturedAt = DateTime.utc(2026, 6, 6, 12);

  static const fixtureLicense = EarthLayerLicense(
    label: 'Preview fixture license',
    usageSummary:
        'App-local deterministic fixture for schema tests and preview planning only.',
    commercialUseAllowed: false,
    redistributionAllowed: false,
    requiresAttribution: true,
  );

  static const weatherWindAttribution = EarthLayerAttribution(
    providerName: 'P21 Fixture',
    sourceTitle: 'Weather/Wind Preview Fixture',
    sourceUrl: null,
    citation: 'Deterministic fixture; not sourced from a live provider.',
  );

  static const wildfireForestAttribution = EarthLayerAttribution(
    providerName: 'P21 Fixture',
    sourceTitle: 'Wildfire/Forest Evidence Preview Fixture',
    sourceUrl: null,
    citation: 'Deterministic fixture; not sourced from a live provider.',
  );

  static const weatherWindSource = EarthProviderSource(
    id: 'fixture-weather-wind-preview',
    name: 'Weather/Wind Preview Fixture',
    access: EarthProviderSourceAccess.previewFixture,
    attribution: weatherWindAttribution,
    license: fixtureLicense,
    updateCadence: 'fixture only; no provider refresh',
    caveats: earthLayerSnapshotPreviewGuardrails,
    requiresServerBoundary: false,
  );

  static const wildfireForestSource = EarthProviderSource(
    id: 'fixture-wildfire-forest-evidence-preview',
    name: 'Wildfire/Forest Evidence Preview Fixture',
    access: EarthProviderSourceAccess.previewFixture,
    attribution: wildfireForestAttribution,
    license: fixtureLicense,
    updateCadence: 'fixture only; no provider refresh',
    caveats: earthLayerSnapshotPreviewGuardrails,
    requiresServerBoundary: false,
  );

  static final weatherWindFreshness = EarthLayerFreshness.previewFixture(
    cacheKey: 'fixture:earth-systems:weather-wind:indonesia',
    sourceUpdateCadence: 'fixture only; future provider cadence required',
    lastRefreshLabel: 'Preview fixture generated for P21.1',
  );

  static final wildfireForestFreshness = EarthLayerFreshness.previewFixture(
    cacheKey: 'fixture:environmental:wildfire-forest:amazon-basin',
    sourceUpdateCadence: 'fixture only; future evidence cadence required',
    lastRefreshLabel: 'Preview fixture generated for P21.1',
  );

  static final weatherWindDefinition = EarthLayerSourceDefinition(
    layerId: 'weather-wind-preview',
    layerName: 'Weather/Wind Preview',
    group: EarthLayerGroup.earthSystems,
    source: weatherWindSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.point,
      EarthLayerSnapshotRecordType.path,
      EarthLayerSnapshotRecordType.gridSummary,
      EarthLayerSnapshotRecordType.metricSummary,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.motionLayer,
        label: 'Synthetic flow handoff',
        summary:
            'Future provider-backed wind vectors can feed the existing motion layer.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.focusRegion,
        label: 'Focused broad region',
        summary:
            'Weather/wind fixture can focus a broad region without precise map data.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.rightSideSummary,
        label: 'Earth systems summary',
        summary:
            'Right-side intelligence can summarize source, freshness, and caveats.',
      ),
    ],
    freshnessPolicy: weatherWindFreshness,
    safetyBoundaries: earthLayerSnapshotPreviewGuardrails,
  );

  static final wildfireForestDefinition = EarthLayerSourceDefinition(
    layerId: 'wildfire-forest-evidence-preview',
    layerName: 'Wildfire/Forest Evidence Preview',
    group: EarthLayerGroup.environmental,
    source: wildfireForestSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.eventMarker,
      EarthLayerSnapshotRecordType.gridSummary,
      EarthLayerSnapshotRecordType.metricSummary,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.overlayMarker,
        label: 'Evidence marker',
        summary:
            'Future reviewed event summaries can become aggregate overlay markers.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.timelineEvent,
        label: 'Evidence timeline event',
        summary:
            'Future provider-backed evidence snapshots can feed timeline events.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.contextPanelDetail,
        label: 'Evidence detail',
        summary:
            'Context panel can show source readiness, caveats, and evidence gaps.',
      ),
    ],
    freshnessPolicy: wildfireForestFreshness,
    safetyBoundaries: earthLayerSnapshotPreviewGuardrails,
  );

  static final weatherWindSnapshot = EarthLayerSnapshot(
    id: 'snapshot-fixture-weather-wind-2026-06-06',
    layerId: weatherWindDefinition.layerId,
    layerGroup: weatherWindDefinition.group,
    sourceId: weatherWindSource.id,
    scope: const EarthLayerSnapshotScope(
      regionId: 'indonesia',
      regionLabel: 'Indonesia',
    ),
    capturedAt: capturedAt,
    validFrom: capturedAt,
    validTo: capturedAt.add(const Duration(hours: 6)),
    metadata: EarthLayerSnapshotMetadata(
      freshness: weatherWindFreshness,
      confidence: EarthLayerSnapshotConfidence.fixture,
      precisionScope: 'broad region only',
      dataKind: 'preview fixture',
      geometryPolicy: 'region labels, generalized marker, and synthetic path',
      guardrails: earthLayerSnapshotPreviewGuardrails,
    ),
    attribution: weatherWindAttribution,
    license: fixtureLicense,
    records: [
      const EarthLayerSnapshotRecord(
        id: 'weather-wind-region-indonesia',
        type: EarthLayerSnapshotRecordType.regionLabel,
        label: 'Indonesia weather/wind preview region',
        summary:
            'Broad region label for future Earth systems snapshot routing.',
        scope: EarthLayerSnapshotScope(
          regionId: 'indonesia',
          regionLabel: 'Indonesia',
        ),
        precisionLabel: 'broad region label',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.focusRegion,
            label: 'Focus Indonesia',
            summary: 'Focuses the existing broad-region preview state.',
          ),
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.contextPanelDetail,
            label: 'Context region',
            summary: 'Context panel can explain the fixture scope and caveats.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'weather-wind-marker-java-sea',
        type: EarthLayerSnapshotRecordType.point,
        label: 'Java Sea generalized marker',
        summary:
            'Generalized marker for preview-only Earth systems routing; not a precise observation.',
        scope: EarthLayerSnapshotScope(
          regionId: 'indonesia',
          regionLabel: 'Indonesia',
        ),
        precisionLabel: 'generalized marker; no raw coordinates',
        valueLabel: 'breezy',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.overlayMarker,
            label: 'Broad weather marker',
            summary:
                'Maps to an overlay marker without exposing precise provider geometry.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'weather-wind-synthetic-flow',
        type: EarthLayerSnapshotRecordType.path,
        label: 'Synthetic eastward wind flow',
        summary:
            'Fixture path label for future provider-backed motion handoff.',
        scope: EarthLayerSnapshotScope(
          regionId: 'indonesia',
          regionLabel: 'Indonesia',
        ),
        precisionLabel: 'symbolic path only',
        pathLabels: [
          'west Java Sea',
          'central Indonesia',
          'eastern archipelago',
        ],
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.motionLayer,
            label: 'Synthetic flow layer',
            summary:
                'Can feed existing Earth motion concepts without live vectors.',
          ),
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.timelineEvent,
            label: 'Snapshot motion interval',
            summary:
                'Timeline can label a snapshot interval without playback ownership.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'weather-wind-grid-summary',
        type: EarthLayerSnapshotRecordType.gridSummary,
        label: 'Low-resolution wind grid summary',
        summary:
            'Coarse grid summary placeholder for future cached provider vectors.',
        scope: EarthLayerSnapshotScope(
          regionId: 'indonesia',
          regionLabel: 'Indonesia',
        ),
        precisionLabel: 'coarse grid summary',
        valueLabel: '4 cells',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.rightSideSummary,
            label: 'Grid readiness summary',
            summary:
                'Right panel can summarize coarse provider readiness and caveats.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'weather-wind-speed-summary',
        type: EarthLayerSnapshotRecordType.metricSummary,
        label: 'Wind speed fixture summary',
        summary: 'Illustrative motion intensity metric for preview routing.',
        scope: EarthLayerSnapshotScope(
          regionId: 'indonesia',
          regionLabel: 'Indonesia',
        ),
        precisionLabel: 'illustrative metric only',
        valueLabel: '0.58',
        unitLabel: 'preview intensity',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.rightSideSummary,
            label: 'Motion intensity summary',
            summary:
                'Right panel can describe intensity without provider claims.',
          ),
        ],
      ),
    ],
    visualizationHints: weatherWindDefinition.defaultVisualizationHints,
    caveats: earthLayerSnapshotPreviewGuardrails,
  );

  static final wildfireForestSnapshot = EarthLayerSnapshot(
    id: 'snapshot-fixture-wildfire-forest-2026-06-06',
    layerId: wildfireForestDefinition.layerId,
    layerGroup: wildfireForestDefinition.group,
    sourceId: wildfireForestSource.id,
    scope: const EarthLayerSnapshotScope(
      regionId: 'amazon-basin',
      regionLabel: 'Amazon Basin',
    ),
    capturedAt: capturedAt,
    validFrom: capturedAt,
    validTo: capturedAt.add(const Duration(days: 1)),
    metadata: EarthLayerSnapshotMetadata(
      freshness: wildfireForestFreshness,
      confidence: EarthLayerSnapshotConfidence.fixture,
      precisionScope: 'broad region evidence summary only',
      dataKind: 'preview fixture',
      geometryPolicy: 'region labels, aggregate event marker, and summaries',
      guardrails: earthLayerSnapshotPreviewGuardrails,
    ),
    attribution: wildfireForestAttribution,
    license: fixtureLicense,
    records: [
      const EarthLayerSnapshotRecord(
        id: 'wildfire-forest-region-amazon',
        type: EarthLayerSnapshotRecordType.regionLabel,
        label: 'Amazon Basin evidence preview region',
        summary:
            'Broad region label for future wildfire and forest evidence routing.',
        scope: EarthLayerSnapshotScope(
          regionId: 'amazon-basin',
          regionLabel: 'Amazon Basin',
        ),
        precisionLabel: 'broad region label',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.focusRegion,
            label: 'Focus Amazon Basin',
            summary: 'Focuses a broad environmental evidence region.',
          ),
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.contextPanelDetail,
            label: 'Environmental context',
            summary:
                'Context panel can list source readiness and evidence gaps.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'wildfire-forest-event-cluster',
        type: EarthLayerSnapshotRecordType.eventMarker,
        label: 'Aggregate fire/forest evidence marker',
        summary:
            'Generalized evidence marker for future reviewed wildfire/forest snapshots.',
        scope: EarthLayerSnapshotScope(
          regionId: 'amazon-basin',
          regionLabel: 'Amazon Basin',
        ),
        precisionLabel: 'aggregate marker; no raw fire points',
        eventTimeLabel: 'fixture interval',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.overlayMarker,
            label: 'Aggregate evidence marker',
            summary: 'Can become a safe overlay marker after provider review.',
          ),
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.timelineEvent,
            label: 'Evidence snapshot event',
            summary:
                'Can become a timeline event without owning provider fetching.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'wildfire-forest-grid-summary',
        type: EarthLayerSnapshotRecordType.gridSummary,
        label: 'Forest evidence grid summary',
        summary:
            'Coarse evidence grid placeholder for future cached forest summaries.',
        scope: EarthLayerSnapshotScope(
          regionId: 'amazon-basin',
          regionLabel: 'Amazon Basin',
        ),
        precisionLabel: 'coarse grid summary',
        valueLabel: '3 evidence cells',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.rightSideSummary,
            label: 'Evidence readiness summary',
            summary:
                'Right panel can summarize evidence readiness and limitations.',
          ),
        ],
      ),
      const EarthLayerSnapshotRecord(
        id: 'wildfire-forest-risk-summary',
        type: EarthLayerSnapshotRecordType.metricSummary,
        label: 'Evidence readiness metric',
        summary:
            'Illustrative fixture metric for environmental evidence readiness.',
        scope: EarthLayerSnapshotScope(
          regionId: 'amazon-basin',
          regionLabel: 'Amazon Basin',
        ),
        precisionLabel: 'illustrative metric only',
        valueLabel: 'preview-ready',
        visualizationHints: [
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.rightSideSummary,
            label: 'Readiness state',
            summary: 'Right panel can show readiness without verified claims.',
          ),
          EarthLayerVisualizationHint(
            target: EarthLayerVisualizationTarget.contextPanelDetail,
            label: 'Evidence caveats',
            summary: 'Context panel can show fixture labels and provider gaps.',
          ),
        ],
      ),
    ],
    visualizationHints: wildfireForestDefinition.defaultVisualizationHints,
    caveats: earthLayerSnapshotPreviewGuardrails,
  );

  static final definitions = [
    weatherWindDefinition,
    wildfireForestDefinition,
  ];

  static final snapshots = [
    weatherWindSnapshot,
    wildfireForestSnapshot,
  ];
}

abstract final class EarthLayerWeatherWindPrototypePlan {
  static const guardrails = [
    'Provider Prototype Plan',
    'Preview Only',
    'No Live Provider Lookup',
    'Server Boundary Required',
    'Cache Before Provider',
    'Not Provider Verified',
    'No Verified Environmental Claims',
    'Commercial Terms Review Required',
  ];

  static const openMeteoLicense = EarthLayerLicense(
    label: 'Open-Meteo CC BY 4.0 data / commercial subscription gated',
    url: 'https://open-meteo.com/en/terms',
    usageSummary:
        'Free API is non-commercial and rate limited; production commercial app use requires approved subscription/API-key handling.',
    commercialUseAllowed: false,
    redistributionAllowed: true,
    requiresAttribution: true,
  );

  static const openMeteoAttribution = EarthLayerAttribution(
    providerName: 'Open-Meteo',
    sourceTitle: 'Weather Forecast API',
    sourceUrl: 'https://open-meteo.com/en/docs',
    citation:
        'Prototype candidate only; no live Open-Meteo request is enabled in app runtime.',
  );

  static const openMeteoSource = EarthProviderSource(
    id: 'open-meteo-weather-wind-prototype',
    name: 'Open-Meteo Weather/Wind Prototype Candidate',
    access: EarthProviderSourceAccess.serverCached,
    sourceUrl: 'https://open-meteo.com/en/docs',
    attribution: openMeteoAttribution,
    license: openMeteoLicense,
    updateCadence:
        'Forecast timeseries source; proposed server cache refresh every 30-60 minutes after approval.',
    caveats: guardrails,
    requiresServerBoundary: true,
  );

  static final weatherFreshnessPolicy = EarthLayerFreshness(
    state: EarthLayerFreshnessState.unavailable,
    cacheKey: 'planned:earth-systems:open-meteo:weather-summary',
    ttl: const Duration(minutes: 30),
    sourceUpdateCadence:
        'planned 30-60 minute server cache; provider cadence must be rechecked before implementation',
    lastRefreshLabel: 'Prototype plan only; no provider refresh',
    providerCaveats: guardrails,
  );

  static final windFreshnessPolicy = EarthLayerFreshness(
    state: EarthLayerFreshnessState.unavailable,
    cacheKey: 'planned:earth-systems:open-meteo:wind-flow',
    ttl: const Duration(minutes: 30),
    sourceUpdateCadence:
        'planned 30-60 minute server cache; provider cadence must be rechecked before implementation',
    lastRefreshLabel: 'Prototype plan only; no provider refresh',
    providerCaveats: guardrails,
  );

  static final weatherSourceDefinition = EarthLayerSourceDefinition(
    layerId: 'weather-provider-prototype',
    layerName: 'Weather Provider Prototype',
    group: EarthLayerGroup.earthSystems,
    source: openMeteoSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.point,
      EarthLayerSnapshotRecordType.gridSummary,
      EarthLayerSnapshotRecordType.metricSummary,
      EarthLayerSnapshotRecordType.eventMarker,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.overlayMarker,
        label: 'Generalized weather marker',
        summary:
            'Future normalized snapshots can show broad weather context without raw provider payloads.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.rightSideSummary,
        label: 'Weather source summary',
        summary:
            'Right-side summary can show source, last updated, confidence, and caveats.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.contextPanelDetail,
        label: 'Weather context panel',
        summary:
            'Top-left context can describe selected region, validity window, and source boundary.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.timelineEvent,
        label: 'Weather validity window',
        summary:
            'Timeline can label captured-at and valid-to intervals without claiming historical proof.',
      ),
    ],
    freshnessPolicy: weatherFreshnessPolicy,
    safetyBoundaries: guardrails,
  );

  static final windSourceDefinition = EarthLayerSourceDefinition(
    layerId: 'wind-provider-prototype',
    layerName: 'Wind Provider Prototype',
    group: EarthLayerGroup.earthSystems,
    source: openMeteoSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.path,
      EarthLayerSnapshotRecordType.gridSummary,
      EarthLayerSnapshotRecordType.metricSummary,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.motionLayer,
        label: 'Low-resolution wind flow',
        summary:
            'Future cached wind vectors can feed the existing globe flow layer.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.focusRegion,
        label: 'Focused wind region',
        summary:
            'Wind snapshots can focus a broad region without precise live movement.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.rightSideSummary,
        label: 'Wind source summary',
        summary:
            'Right-side summary can show source, last updated, confidence, and caveats.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.timelineEvent,
        label: 'Wind snapshot interval',
        summary:
            'Timeline can label snapshot validity without enabling playback claims.',
      ),
    ],
    freshnessPolicy: windFreshnessPolicy,
    safetyBoundaries: guardrails,
  );

  static final definitions = [
    weatherSourceDefinition,
    windSourceDefinition,
  ];

  static List<String> get summaryLines {
    return [
      'recommended provider: ${openMeteoSource.name}',
      'source access: ${openMeteoSource.access.label}',
      'server boundary: required',
      'weather layer: ${weatherSourceDefinition.layerId}',
      'wind layer: ${windSourceDefinition.layerId}',
      'cache policy: ${weatherFreshnessPolicy.ttlLabel}',
      'live provider lookup: disabled',
      ...guardrails,
    ];
  }
}

final class EarthWeatherWindProviderFixture {
  const EarthWeatherWindProviderFixture({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.validFrom,
    required this.validTo,
    required this.temperatureCelsius,
    required this.windSpeedKmh,
    required this.windDirectionDegrees,
    required this.relativeHumidityPercent,
    required this.pressureHpa,
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
  final double temperatureCelsius;
  final double windSpeedKmh;
  final int windDirectionDegrees;
  final int relativeHumidityPercent;
  final int pressureHpa;
  final String regionId;
  final String regionLabel;
  final String sourceLabel;
  final List<String> caveats;

  String get generalizedCoordinateLabel {
    return '${latitude.toStringAsFixed(1)}, ${longitude.toStringAsFixed(1)} '
        'generalized';
  }

  String get temperatureLabel => temperatureCelsius.toStringAsFixed(1);

  String get windSpeedLabel => windSpeedKmh.toStringAsFixed(1);

  String get windDirectionLabel => '$windDirectionDegrees deg';

  static final indonesiaPreview = EarthWeatherWindProviderFixture(
    id: 'fixture-open-meteo-shaped-indonesia-2026-06-06',
    latitude: -6.2,
    longitude: 106.8,
    capturedAt: EarthLayerSnapshotFixtures.capturedAt,
    validFrom: EarthLayerSnapshotFixtures.capturedAt,
    validTo: EarthLayerSnapshotFixtures.capturedAt.add(
      const Duration(hours: 6),
    ),
    temperatureCelsius: 29.4,
    windSpeedKmh: 18.2,
    windDirectionDegrees: 118,
    relativeHumidityPercent: 78,
    pressureHpa: 1008,
    regionId: 'indonesia',
    regionLabel: 'Indonesia',
    sourceLabel: 'Open-Meteo-shaped preview fixture',
    caveats: EarthWeatherWindSnapshotAdapter.guardrails,
  );
}

final class EarthWeatherWindCacheFixture {
  const EarthWeatherWindCacheFixture({
    required this.cacheKey,
    required this.ttl,
    required this.freshnessState,
    required this.lastRefreshLabel,
    required this.sourceUpdateCadence,
    required this.caveats,
  });

  final String cacheKey;
  final Duration ttl;
  final EarthLayerFreshnessState freshnessState;
  final String lastRefreshLabel;
  final String sourceUpdateCadence;
  final List<String> caveats;

  EarthLayerFreshness toFreshness() {
    return EarthLayerFreshness(
      state: freshnessState,
      cacheKey: cacheKey,
      ttl: ttl,
      sourceUpdateCadence: sourceUpdateCadence,
      lastRefreshLabel: lastRefreshLabel,
      providerCaveats: caveats,
    );
  }

  static const indonesiaPreview = EarthWeatherWindCacheFixture(
    cacheKey: 'fixture:earth-systems:open-meteo-shaped:weather-wind:indonesia',
    ttl: Duration(minutes: 30),
    freshnessState: EarthLayerFreshnessState.previewFixture,
    lastRefreshLabel:
        'Cache fixture generated for P21.3; no provider refresh occurred',
    sourceUpdateCadence:
        'simulated 30m cache cadence; future Open-Meteo cadence requires server approval',
    caveats: EarthWeatherWindSnapshotAdapter.guardrails,
  );
}

abstract final class EarthWeatherWindSnapshotAdapter {
  static const guardrails = [
    'Preview Fixture',
    'Preview Only',
    'Not Live Data',
    'No Live Provider Lookup',
    'Not Provider Verified',
    'No Verified Environmental Claims',
  ];

  static final cacheFixtureFreshness =
      EarthWeatherWindCacheFixture.indonesiaPreview.toFreshness();

  static final sourceDefinition = EarthLayerSourceDefinition(
    layerId: 'weather-wind-cache-fixture',
    layerName: 'Weather/Wind Cache Fixture Adapter',
    group: EarthLayerGroup.earthSystems,
    source: EarthLayerWeatherWindPrototypePlan.openMeteoSource,
    supportedRecordTypes: const [
      EarthLayerSnapshotRecordType.regionLabel,
      EarthLayerSnapshotRecordType.point,
      EarthLayerSnapshotRecordType.path,
      EarthLayerSnapshotRecordType.gridSummary,
      EarthLayerSnapshotRecordType.eventMarker,
      EarthLayerSnapshotRecordType.metricSummary,
    ],
    defaultVisualizationHints: const [
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.motionLayer,
        label: 'Globe flow layer hint',
        summary:
            'Fixture wind speed and direction can drive symbolic flow emphasis.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.overlayMarker,
        label: 'Generalized weather marker',
        summary:
            'Fixture point summary can render as a broad-region marker only.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.rightSideSummary,
        label: 'Weather/wind summary',
        summary:
            'Right-side summary can show normalized metrics and cache status.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.contextPanelDetail,
        label: 'Top-left context panel',
        summary:
            'Context panel can show source label, validity window, and caveats.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.layerControls,
        label: 'Bottom-left layer controls',
        summary:
            'Layer controls can show fixture readiness without provider state.',
      ),
      EarthLayerVisualizationHint(
        target: EarthLayerVisualizationTarget.timelineEvent,
        label: 'Timeline validity label',
        summary:
            'Timeline can show captured-at and valid-to labels without live data.',
      ),
    ],
    freshnessPolicy: cacheFixtureFreshness,
    safetyBoundaries: guardrails,
  );

  static final indonesiaPreviewSnapshot = fromFixture(
    EarthWeatherWindProviderFixture.indonesiaPreview,
    cache: EarthWeatherWindCacheFixture.indonesiaPreview,
  );

  static EarthLayerSnapshot fromFixture(
    EarthWeatherWindProviderFixture fixture, {
    EarthWeatherWindCacheFixture cache =
        EarthWeatherWindCacheFixture.indonesiaPreview,
    EarthLayerFreshness? freshness,
    EarthLayerSnapshotConfidence confidence =
        EarthLayerSnapshotConfidence.fixture,
    EarthLayerAttribution? attribution,
    String? dataKind,
    String? precisionScope,
    String? geometryPolicy,
    List<String>? guardrailsOverride,
    List<String> additionalCaveats = const [
      'Cache Fixture',
      'Open-Meteo Shaped Fixture',
    ],
  }) {
    final guardrailLabels = guardrailsOverride ?? guardrails;
    final scope = EarthLayerSnapshotScope(
      regionId: fixture.regionId,
      regionLabel: fixture.regionLabel,
    );
    final snapshotFreshness = freshness ?? cache.toFreshness();
    final validWindow =
        '${_utcLabel(fixture.validFrom)} -> ${_utcLabel(fixture.validTo)}';

    return EarthLayerSnapshot(
      id: 'snapshot-${fixture.id}',
      layerId: sourceDefinition.layerId,
      layerGroup: sourceDefinition.group,
      sourceId: EarthLayerWeatherWindPrototypePlan.openMeteoSource.id,
      scope: scope,
      capturedAt: fixture.capturedAt,
      validFrom: fixture.validFrom,
      validTo: fixture.validTo,
      metadata: EarthLayerSnapshotMetadata(
        freshness: snapshotFreshness,
        confidence: confidence,
        precisionScope: precisionScope ??
            'generalized fixture coordinate and broad region only',
        dataKind: dataKind ?? 'Open-Meteo-shaped cache fixture',
        geometryPolicy: geometryPolicy ??
            'generalized marker, symbolic flow path, coarse grid summary',
        guardrails: guardrailLabels,
      ),
      attribution: attribution ??
          EarthLayerWeatherWindPrototypePlan.openMeteoAttribution,
      license: EarthLayerWeatherWindPrototypePlan.openMeteoLicense,
      records: [
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-region',
          type: EarthLayerSnapshotRecordType.regionLabel,
          label: '${fixture.regionLabel} weather/wind cache fixture',
          summary:
              'Manual broad-region routing label for an Open-Meteo-shaped fixture.',
          scope: scope,
          precisionLabel: 'broad region label',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.focusRegion,
              label: 'Focus mapped region',
              summary: 'Focuses the existing globe region selection.',
            ),
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.layerControls,
              label: 'Layer control readiness',
              summary:
                  'Bottom-left controls can show preview fixture availability.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-point',
          type: EarthLayerSnapshotRecordType.point,
          label: 'Generalized weather marker',
          summary:
              '${fixture.sourceLabel}; coordinate ${fixture.generalizedCoordinateLabel}; not a precise observation.',
          scope: scope,
          precisionLabel: 'generalized marker; no precise coordinate claim',
          valueLabel: fixture.temperatureLabel,
          unitLabel: 'C',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.overlayMarker,
              label: 'Generalized weather marker',
              summary: 'Overlay marker can show fixture weather context only.',
            ),
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.contextPanelDetail,
              label: 'Fixture marker detail',
              summary:
                  'Top-left context can list fixture source and limitations.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-temperature',
          type: EarthLayerSnapshotRecordType.metricSummary,
          label: 'Temperature fixture summary',
          summary:
              'Normalized fixture temperature; not provider verified and not live.',
          scope: scope,
          precisionLabel: 'fixture metric only',
          valueLabel: fixture.temperatureLabel,
          unitLabel: 'C',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.rightSideSummary,
              label: 'Temperature summary',
              summary: 'Right panel can show normalized fixture temperature.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-humidity',
          type: EarthLayerSnapshotRecordType.metricSummary,
          label: 'Humidity fixture summary',
          summary:
              'Normalized fixture humidity; included for cache shape testing.',
          scope: scope,
          precisionLabel: 'fixture metric only',
          valueLabel: fixture.relativeHumidityPercent.toString(),
          unitLabel: '%',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.rightSideSummary,
              label: 'Humidity summary',
              summary: 'Right panel can show normalized fixture humidity.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-pressure',
          type: EarthLayerSnapshotRecordType.metricSummary,
          label: 'Pressure fixture summary',
          summary:
              'Normalized fixture pressure; included for cache shape testing.',
          scope: scope,
          precisionLabel: 'fixture metric only',
          valueLabel: fixture.pressureHpa.toString(),
          unitLabel: 'hPa',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.rightSideSummary,
              label: 'Pressure summary',
              summary: 'Right panel can show normalized fixture pressure.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-wind-flow',
          type: EarthLayerSnapshotRecordType.path,
          label: 'Symbolic wind flow hint',
          summary:
              'Fixture wind speed ${fixture.windSpeedLabel} km/h at ${fixture.windDirectionLabel}; symbolic motion only.',
          scope: scope,
          precisionLabel: 'symbolic path only',
          valueLabel: fixture.windSpeedLabel,
          unitLabel: 'km/h',
          pathLabels: const [
            'western Indonesia fixture cell',
            'central archipelago fixture cell',
            'eastern Indonesia fixture cell',
          ],
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.motionLayer,
              label: 'Globe flow layer',
              summary: 'Motion layer can use symbolic wind emphasis.',
            ),
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.timelineEvent,
              label: 'Wind fixture interval',
              summary: 'Timeline can label the fixture validity interval.',
            ),
          ],
          eventTimeLabel: validWindow,
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-grid',
          type: EarthLayerSnapshotRecordType.gridSummary,
          label: 'Coarse weather/wind grid summary',
          summary:
              'Four illustrative fixture cells summarize future cache-normalized grid output.',
          scope: scope,
          precisionLabel: 'coarse grid fixture',
          valueLabel: '4 cells',
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.motionLayer,
              label: 'Coarse grid motion source',
              summary:
                  'Motion can reference coarse grid readiness without vectors.',
            ),
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.layerControls,
              label: 'Grid readiness toggle label',
              summary: 'Layer controls can identify fixture grid readiness.',
            ),
          ],
          caveats: guardrailLabels,
        ),
        EarthLayerSnapshotRecord(
          id: '${fixture.regionId}-cache-fixture-valid-window',
          type: EarthLayerSnapshotRecordType.eventMarker,
          label: 'Weather/wind fixture validity window',
          summary:
              'Captured and valid-to labels for preview timeline wiring only.',
          scope: scope,
          precisionLabel: 'snapshot time label only',
          eventTimeLabel: validWindow,
          visualizationHints: const [
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.timelineEvent,
              label: 'Timeline label',
              summary:
                  'Timeline can display fixture validity without playback claims.',
            ),
            EarthLayerVisualizationHint(
              target: EarthLayerVisualizationTarget.contextPanelDetail,
              label: 'Validity context',
              summary:
                  'Top-left context can show fixture captured and validity labels.',
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

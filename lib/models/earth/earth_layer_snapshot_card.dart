import 'dart:convert';

import 'package:flutter/foundation.dart';

// GLOBE-POLISH (5) — the quick data-snapshot shown when a point marker is
// clicked on the globe. Carries ONLY governed published fields the renderer
// already exposed on the entity (value, units, caption, label) — never a raw
// provider payload. Flow layers (wind/ocean) have no pickable entities, so they
// can never produce a snapshot (the click exclusion is structural).

final class EarthLayerSnapshotCard {
  const EarthLayerSnapshotCard({
    required this.value,
    required this.units,
    required this.caption,
    this.label,
    this.count = 1,
    this.members = const [],
    this.searchQuery,
  });

  final double value;
  final String units;

  /// The governed honest caption (source + freshness, or the representative
  /// label) — surfaced verbatim.
  final String caption;

  /// Optional per-point label (e.g. a region/site name) if the point set
  /// published one.
  final String? label;

  /// Records this marker represents. >1 = a spatial CLUSTER (e.g. dense carbon
  /// projects collapsed to one dot); the snapshot then offers a "browse in Data
  /// View" path instead of a single record's value detail.
  final int count;

  /// Item 3: the governed labels of THIS clicked dot's own members (build-time
  /// embedded, capped). The card lists exactly these for a cluster, so a
  /// 2-member dot shows 2 — never a country rollup. Empty for a single record
  /// or a legacy (un-enriched) asset; the card then falls back to the persistent
  /// "Browse in Data View" footer. Also populated by the direct earth-DB search
  /// (item 2) to reuse the same generic record-list container.
  final List<String> members;

  /// Item 2: when set, this card is a DIRECT earth-DB SEARCH result (not a globe
  /// pick) — the popup shows the query + its matched [members] (or "No results
  /// found" when empty), reusing the same snapshot popup chrome.
  final String? searchQuery;

  bool get isCluster => count > 1;

  /// Builds a search-result card for the snapshot popup (item 2).
  factory EarthLayerSnapshotCard.search({
    required String query,
    required List<String> results,
  }) =>
      EarthLayerSnapshotCard(
        value: 0,
        units: '',
        caption: 'Direct search · earth datasets',
        count: results.length,
        members: results,
        searchQuery: query,
      );

  String get valueText {
    final v = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return units.isEmpty ? v : '$v $units';
  }

  static EarthLayerSnapshotCard? fromJson(Map<String, dynamic> json) {
    final value = json['value'];
    if (value is! num) return null;
    final label = json['label'];
    return EarthLayerSnapshotCard(
      value: value.toDouble(),
      units: (json['units'] as String?) ?? '',
      caption: (json['caption'] as String?) ?? '',
      label: label is String && label.isNotEmpty ? label : null,
      count: (json['count'] as num?)?.toInt() ?? 1,
      members: (json['members'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  static EarthLayerSnapshotCard? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {/* ignore malformed pick payloads */}
    return null;
  }
}

/// The currently shown marker snapshot (null = none). The web bridge sets it
/// from a globe pick event; the globe stage shows the card. A neutral seam so
/// neither the bridge nor the stage couples to the other.
abstract final class EarthPickedSnapshot {
  static final ValueNotifier<EarthLayerSnapshotCard?> notifier =
      ValueNotifier<EarthLayerSnapshotCard?>(null);
}

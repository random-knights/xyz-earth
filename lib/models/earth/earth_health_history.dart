import 'dart:convert';

/// Parsed `earth.healthhistory.v1` document — the rolling daily snapshots written
/// by the `earthHealthHistorySnapshot` function. Richer than the compact
/// `earth.healthscore.history.v1`: each day keeps the global headline, per-region
/// scores, per-DOMAIN global scores, and the global coverage, so the "Health
/// history" card can chart any domain and show how much of the methodology was
/// covered. History accrues live from [startedOn]; an absent/empty doc parses to
/// [empty] (the early "tracking started" state).
final class EarthHealthHistory {
  const EarthHealthHistory({
    required this.schema,
    required this.methodologyVersion,
    required this.startedOn,
    required this.points,
    required this.isLive,
  });

  static const schemaId = 'earth.healthhistory.v1';

  /// Default ship / track-start date (mirrors the function's HEALTH_HISTORY_STARTED_ON).
  static const defaultStartedOn = '2026-06-26';

  /// The empty history — no snapshots yet (pre-first-run / fail-soft state).
  static const empty = EarthHealthHistory(
    schema: schemaId,
    methodologyVersion: '',
    startedOn: defaultStartedOn,
    points: <EarthHealthHistoryPoint>[],
    isLive: false,
  );

  /// The global domain key — the headline score (distinct from the per-domain ids).
  static const globalKey = 'global';

  final String schema;
  final String methodologyVersion;
  final String? startedOn;

  /// Daily snapshots, ASCENDING by date ('YYYY-MM-DD').
  final List<EarthHealthHistoryPoint> points;

  /// True when loaded from the live doc (has at least one stored day).
  final bool isLive;

  bool get hasHistory => points.isNotEmpty;
  int get dayCount => points.length;
  EarthHealthHistoryPoint? get latest => points.isEmpty ? null : points.last;

  /// The domain ids seen across all points (e.g. air, land-cover, biodiversity,
  /// cryosphere, protected-areas, human), insertion-ordered from the latest day.
  List<String> get domainIds {
    final seen = <String>{};
    for (final p in points.reversed) {
      for (final k in p.domains.keys) {
        seen.add(k);
      }
    }
    return seen.toList();
  }

  factory EarthHealthHistory.fromJson(Map<String, dynamic> json) {
    final meta =
        (json['meta'] is Map ? json['meta'] as Map : const {}).cast<String, dynamic>();
    final raw = json['points'] is List ? json['points'] as List : const [];
    final parsed = <EarthHealthHistoryPoint>[];
    for (final p in raw) {
      if (p is Map) {
        final point =
            EarthHealthHistoryPoint.tryFromJson(p.cast<String, dynamic>());
        if (point != null) parsed.add(point);
      }
    }
    parsed.sort((a, b) => a.date.compareTo(b.date));
    final methodologyVersion = (json['methodologyVersion'] as String?) ??
        (meta['methodologyVersion'] as String?) ??
        (parsed.isNotEmpty ? parsed.last.methodologyVersion : '');
    return EarthHealthHistory(
      schema: (meta['schema'] as String?) ?? schemaId,
      methodologyVersion: methodologyVersion,
      startedOn: (json['startedOn'] as String?) ??
          (parsed.isNotEmpty ? parsed.first.date : defaultStartedOn),
      points: parsed,
      isLive: parsed.isNotEmpty,
    );
  }

  factory EarthHealthHistory.parse(String raw) =>
      EarthHealthHistory.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static String _dateKey(DateTime d) {
    final u = d.toUtc();
    final mm = u.month.toString().padLeft(2, '0');
    final dd = u.day.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-$mm-$dd';
  }

  static DateTime? _parseDate(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
    if (m == null) return null;
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// The latest stored point AT OR BEFORE [targetKey] (ascending scan), or null
  /// when the target predates the first stored day.
  EarthHealthHistoryPoint? _pointAtOrBefore(String targetKey) {
    EarthHealthHistoryPoint? best;
    for (final p in points) {
      if (p.date.compareTo(targetKey) <= 0) {
        best = p;
      } else {
        break;
      }
    }
    return best;
  }

  /// The stored point closest at-or-before ([latest] − [daysAgo] days), used as
  /// the baseline for a delta. Null when there is no such earlier day.
  EarthHealthHistoryPoint? pointDaysBefore(int daysAgo) {
    final last = latest;
    if (last == null || daysAgo <= 0) return last;
    final lastDate = _parseDate(last.date);
    if (lastDate == null) return null;
    final target = lastDate.subtract(Duration(days: daysAgo));
    return _pointAtOrBefore(_dateKey(target));
  }

  /// Current − baseline for [key] ('global' or a domain id) over [daysAgo] days.
  /// Null when there isn't enough history (no distinct earlier baseline) or the
  /// key is missing on either end — the UI then shows a dashed placeholder.
  double? delta(String key, int daysAgo) {
    final last = latest;
    if (last == null) return null;
    final baseline = pointDaysBefore(daysAgo);
    if (baseline == null || baseline.date == last.date) return null;
    final now = last.valueFor(key);
    final then = baseline.valueFor(key);
    if (now == null || then == null) return null;
    return now - then;
  }

  /// Today's delta (current − previous stored day) for [key].
  double? todayDelta(String key) => delta(key, 1);

  /// The (date, value) series for charting [key] across all points (skips days
  /// missing the key).
  List<({String date, double value})> series(String key) {
    final out = <({String date, double value})>[];
    for (final p in points) {
      final v = p.valueFor(key);
      if (v != null) out.add((date: p.date, value: v));
    }
    return out;
  }
}

/// One UTC day's rich snapshot.
final class EarthHealthHistoryPoint {
  const EarthHealthHistoryPoint({
    required this.date,
    required this.methodologyVersion,
    required this.global,
    required this.regions,
    required this.domains,
    required this.coverage,
  });

  final String date; // 'YYYY-MM-DD' (UTC)
  final String methodologyVersion;
  final double global;
  final Map<String, double> regions;
  final Map<String, double> domains;
  final double coverage; // 0..1

  /// Value for a chart key: 'global' → the headline, else the domain id.
  double? valueFor(String key) =>
      key == EarthHealthHistory.globalKey ? global : domains[key];

  static Map<String, double> _numberMap(Object? raw) {
    final out = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) out[k.toString()] = v.toDouble();
      });
    }
    return out;
  }

  static EarthHealthHistoryPoint? tryFromJson(Map<String, dynamic> j) {
    final date = j['date'];
    final global = j['global'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        global is! num) {
      return null;
    }
    final coverage = j['coverage'];
    return EarthHealthHistoryPoint(
      date: date,
      methodologyVersion: (j['methodologyVersion'] as String?) ?? '',
      global: global.toDouble(),
      regions: _numberMap(j['regions']),
      domains: _numberMap(j['domains']),
      coverage: coverage is num ? coverage.toDouble() : 0,
    );
  }
}

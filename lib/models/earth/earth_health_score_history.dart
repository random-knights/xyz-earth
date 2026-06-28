import 'dart:convert';

import 'package:xyz_earth/models/earth/earth_time.dart';

/// Parsed `earth.healthscore.history.v1` document — the rolling daily snapshots
/// of the Global Health Score written (piggybacked) by earthHealthScoreRefresh.
/// The client maps the selected timeline window to a target date and reads that
/// day's snapshot; windows older than the first stored day honestly read
/// "building history" until enough days accrue from the feature's ship date.
///
/// Each day is COMPACT — the global headline + per-region scores only (no
/// subScores) — so the history doc stays tiny. Fail-soft: an absent/empty doc
/// parses to [empty] and every past window reads "building history".
final class EarthHealthScoreHistory {
  const EarthHealthScoreHistory({
    required this.schema,
    required this.days,
    required this.firstDate,
    required this.lastDate,
    required this.isLive,
  });

  static const schemaId = 'earth.healthscore.history.v1';

  /// An empty history — no snapshots yet (the pre-deploy / fail-soft state).
  static const empty = EarthHealthScoreHistory(
    schema: schemaId,
    days: <EarthHealthScoreDay>[],
    firstDate: null,
    lastDate: null,
    isLive: false,
  );

  final String schema;

  /// Daily snapshots, ASCENDING by date ('YYYY-MM-DD').
  final List<EarthHealthScoreDay> days;
  final String? firstDate;
  final String? lastDate;

  /// True when loaded from the live history doc (has at least one stored day).
  final bool isLive;

  bool get hasHistory => days.isNotEmpty;

  factory EarthHealthScoreHistory.fromJson(Map<String, dynamic> json) {
    final meta = ((json['meta'] as Map?) ?? const {}).cast<String, dynamic>();
    final raw = (json['days'] as List?) ?? const [];
    final parsed = <EarthHealthScoreDay>[];
    for (final d in raw) {
      final day = EarthHealthScoreDay.tryFromJson(
        (d as Map).cast<String, dynamic>(),
      );
      if (day != null) parsed.add(day);
    }
    parsed.sort((a, b) => a.date.compareTo(b.date));
    return EarthHealthScoreHistory(
      schema: (meta['schema'] as String?) ?? schemaId,
      days: parsed,
      firstDate: (meta['firstDate'] as String?) ??
          (parsed.isNotEmpty ? parsed.first.date : null),
      lastDate: (meta['lastDate'] as String?) ??
          (parsed.isNotEmpty ? parsed.last.date : null),
      isLive: parsed.isNotEmpty,
    );
  }

  factory EarthHealthScoreHistory.parse(String raw) =>
      EarthHealthScoreHistory.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Days-ago offset for a timeline window, or null for windows that carry no
  /// history (forecast / unknown). 'Now' is today (0).
  static int? daysAgoForWindow(EarthTimeWindow window) => switch (window.id) {
        'now' => 0,
        'last-24-hours' => 1,
        'last-7-days' => 7,
        'last-30-days' => 30,
        'this-year' => 365,
        _ => null,
      };

  static String _dateKey(DateTime d) {
    final u = d.toUtc();
    final mm = u.month.toString().padLeft(2, '0');
    final dd = u.day.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-$mm-$dd';
  }

  /// The snapshot for [window] relative to [asOf] (default: now, UTC): the latest
  /// stored day AT OR BEFORE the window's target date. Returns null when the
  /// target predates the first stored day (still "building history") or the
  /// window carries no history (forecast/unknown).
  EarthHealthScoreDay? dayForWindow(EarthTimeWindow window, {DateTime? asOf}) {
    final daysAgo = daysAgoForWindow(window);
    if (daysAgo == null || days.isEmpty) return null;
    final now = (asOf ?? DateTime.now()).toUtc();
    final target = DateTime.utc(now.year, now.month, now.day)
        .subtract(Duration(days: daysAgo));
    final targetKey = _dateKey(target);
    EarthHealthScoreDay? best;
    for (final d in days) {
      if (d.date.compareTo(targetKey) <= 0) {
        best = d;
      } else {
        break; // ascending — no later day can be <= target
      }
    }
    return best;
  }

  /// True when [window] resolves to a real stored snapshot (vs "building
  /// history"). 'Now' is always available once any history exists.
  bool hasHistoryFor(EarthTimeWindow window, {DateTime? asOf}) =>
      dayForWindow(window, asOf: asOf) != null;

  /// Global headline score for [window], or null (building history / no data).
  double? globalForWindow(EarthTimeWindow window, {DateTime? asOf}) =>
      dayForWindow(window, asOf: asOf)?.global;

  /// Region score for [window], or null (building history / region absent).
  double? regionForWindow(
    EarthTimeWindow window,
    String regionId, {
    DateTime? asOf,
  }) =>
      dayForWindow(window, asOf: asOf)?.regions[regionId];
}

/// One UTC day's compact score snapshot.
final class EarthHealthScoreDay {
  const EarthHealthScoreDay({
    required this.date,
    required this.global,
    required this.regions,
  });

  final String date; // 'YYYY-MM-DD' (UTC)
  final double global;
  final Map<String, double> regions;

  static EarthHealthScoreDay? tryFromJson(Map<String, dynamic> j) {
    final date = j['date'];
    final global = j['global'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        global is! num) {
      return null;
    }
    final regions = <String, double>{};
    final rs = j['regions'];
    if (rs is Map) {
      rs.forEach((k, v) {
        if (v is num) regions[k.toString()] = v.toDouble();
      });
    }
    return EarthHealthScoreDay(
      date: date,
      global: global.toDouble(),
      regions: regions,
    );
  }
}

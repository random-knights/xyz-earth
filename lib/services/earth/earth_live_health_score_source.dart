import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xyz_earth/models/earth/earth_live_health_score.dart';

/// Source of the parsed `earth.healthscore.v1` document for the live Global
/// Health Score UI. Loaded once Dart-side; the gauge recomputes the displayed
/// view from it on every earth+ filter (no refetch).
abstract interface class EarthLiveHealthScoreSource {
  Future<EarthLiveHealthScore> load();
}

/// Loads a bundled, representative `earth.healthscore.v1` document. `isLive`
/// stays false so the UI labels it representative until the live grid binds.
final class StaticAssetHealthScoreSource implements EarthLiveHealthScoreSource {
  const StaticAssetHealthScoreSource({this.assetPath = defaultAsset});

  static const defaultAsset =
      'assets/earth/score/health-score-representative-v1.json';

  final String assetPath;

  @override
  Future<EarthLiveHealthScore> load() async =>
      EarthLiveHealthScore.parse(await rootBundle.loadString(assetPath));
}

typedef EarthHealthScoreFetcher = Future<String> Function(Uri url);

/// Reads the live `earth/score/health-score.json` written by the
/// earthHealthScoreRefresh scheduled function as PRIMARY, FAIL-SOFT to the
/// bundled representative document. Until the function is deployed + has run,
/// the fetch fails and the representative doc is used (honesty preserved).
final class LiveStorageHealthScoreSource implements EarthLiveHealthScoreSource {
  const LiveStorageHealthScoreSource({
    this.liveUrl = defaultLiveUrl,
    this.fallback = const StaticAssetHealthScoreSource(),
    this.fetcher,
  });

  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/score/health-score.json';

  final String liveUrl;
  final EarthLiveHealthScoreSource fallback;
  final EarthHealthScoreFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live health score HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthLiveHealthScore> load() async {
    try {
      final doc = EarthLiveHealthScore.parse(await _fetch(Uri.parse(liveUrl)));
      if (doc.regions.isEmpty && doc.global.subScores.isEmpty) {
        throw const FormatException('empty live health score');
      }
      return doc;
    } catch (_) {
      return fallback.load();
    }
  }
}

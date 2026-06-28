import 'package:http/http.dart' as http;
import 'package:xyz_earth/models/earth/earth_health_score_history.dart';

/// Source of the parsed `earth.healthscore.history.v1` document (the Global
/// Health Score's rolling daily snapshots) for the timeline UI.
abstract interface class EarthHealthScoreHistorySource {
  Future<EarthHealthScoreHistory> load();
}

typedef EarthHealthScoreHistoryFetcher = Future<String> Function(Uri url);

/// Reads the live `earth/score/health-score-history.json` written by
/// earthHealthScoreRefresh. There is NO bundled history (it accrues live from
/// the feature's ship date), so the fail-soft fallback is an EMPTY history —
/// every past timeline window then honestly reads "building history" until the
/// refresher has been deployed and accrued days.
final class LiveStorageHealthScoreHistorySource
    implements EarthHealthScoreHistorySource {
  const LiveStorageHealthScoreHistorySource({
    this.liveUrl = defaultLiveUrl,
    this.fetcher,
  });

  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/score/health-score-history.json';

  final String liveUrl;
  final EarthHealthScoreHistoryFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('health score history HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthHealthScoreHistory> load() async {
    try {
      final doc =
          EarthHealthScoreHistory.parse(await _fetch(Uri.parse(liveUrl)));
      return doc.hasHistory ? doc : EarthHealthScoreHistory.empty;
    } catch (_) {
      return EarthHealthScoreHistory.empty;
    }
  }
}

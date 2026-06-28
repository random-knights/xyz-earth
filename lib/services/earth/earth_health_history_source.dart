import 'package:http/http.dart' as http;
import 'package:xyz_earth/models/earth/earth_health_history.dart';

/// Source of the parsed `earth.healthhistory.v1` document (the rich daily
/// Health-history snapshots) for the "Health history" card.
abstract interface class EarthHealthHistorySource {
  Future<EarthHealthHistory> load();
}

typedef EarthHealthHistoryFetcher = Future<String> Function(Uri url);

/// Reads the live `earth/score/health-history.json` written daily by the
/// `earthHealthHistorySnapshot` function. There is NO bundled history (it accrues
/// live from the ship date), so the fail-soft fallback is an EMPTY history — the
/// card then reads "tracking started …" until days accrue.
final class LiveStorageHealthHistorySource implements EarthHealthHistorySource {
  const LiveStorageHealthHistorySource({
    this.liveUrl = defaultLiveUrl,
    this.fetcher,
  });

  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/score/health-history.json';

  final String liveUrl;
  final EarthHealthHistoryFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('health history HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthHealthHistory> load() async {
    try {
      final doc = EarthHealthHistory.parse(await _fetch(Uri.parse(liveUrl)));
      return doc.hasHistory ? doc : EarthHealthHistory.empty;
    } catch (_) {
      return EarthHealthHistory.empty;
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// LIVE-READY MANIFEST — one source of truth for which Earth live-grid objects
/// are actually deployed, so the live field sources can SKIP the fetch for an
/// undeployed object instead of spamming the console with a 403 (they already
/// fail-soft to the bundled representative, but the failed request still logs).
///
/// ONE check, memoized: the manifest is loaded once (bundled
/// `assets/earth/live-ready.json`, optionally overridden by a Storage object when
/// `checkStorage` is true) and cached for the app's lifetime.
///
/// EXCLUDE-list semantics: every live object is fetched UNLESS its path appears
/// in `notReady` — so newly-deployed or brand-new layers are never hidden; only
/// explicitly-undeployed objects are gated. FAIL-OPEN: if the manifest can't load
/// at all, nothing is gated (zero behaviour change — live fetches proceed).
///
/// To update as refreshers deploy: either edit the bundled asset (ship), or set
/// `checkStorage: true` and upload `earth/manifest/live-ready.json` (dynamic, no
/// app ship).
class EarthLiveReadyManifest {
  EarthLiveReadyManifest._();

  static final EarthLiveReadyManifest instance = EarthLiveReadyManifest._();

  static const bundledAsset = 'assets/earth/live-ready.json';
  static const storageManifestUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/manifest/live-ready.json';

  Set<String> _notReady = const <String>{};
  Future<void>? _loading;

  /// Whether [liveUrl] should be fetched (its object is believed deployed).
  /// Returns true (fetch) for anything not explicitly listed `notReady`, and
  /// true for everything if the manifest failed to load (fail-open).
  Future<bool> isReady(String liveUrl) async {
    await _ensureLoaded();
    for (final path in _notReady) {
      if (path.isNotEmpty && liveUrl.contains(path)) return false;
    }
    return true;
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    var notReady = const <String>{};
    var checkStorage = false;
    try {
      final m = jsonDecode(await rootBundle.loadString(bundledAsset))
          as Map<String, dynamic>;
      notReady = _readNotReady(m);
      checkStorage = m['checkStorage'] == true;
    } catch (_) {
      // Fail-open: a missing/malformed bundled manifest gates nothing.
    }
    if (checkStorage) {
      try {
        final resp = await http
            .get(Uri.parse(storageManifestUrl))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          notReady = _readNotReady(
            jsonDecode(resp.body) as Map<String, dynamic>,
          );
        }
      } catch (_) {
        // Keep the bundled default on any Storage-manifest failure.
      }
    }
    _notReady = notReady;
  }

  static Set<String> _readNotReady(Map<String, dynamic> m) {
    final list = m['notReady'];
    if (list is! List) return const <String>{};
    return list.whereType<String>().where((s) => s.isNotEmpty).toSet();
  }

  /// Test seam: inject the manifest without touching rootBundle / network.
  @visibleForTesting
  void debugSetNotReady(Set<String> notReady) {
    _notReady = notReady;
    _loading = Future<void>.value();
  }

  /// Test seam: reset so the next [isReady] reloads from the bundle.
  @visibleForTesting
  void debugReset() {
    _notReady = const <String>{};
    _loading = null;
  }
}

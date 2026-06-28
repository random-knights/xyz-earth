import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xyz_earth/models/earth/earth_flow_field.dart';
import 'package:xyz_earth/services/earth/earth_live_ready_manifest.dart';

/// Source of the global wind [EarthWindGrid] for the flow-field renderer.
///
/// Phase 1a is a STATIC governed asset (a representative climatology, honestly
/// labeled "not current conditions"). Phase 1b adds a NOAA-GFS-backed source
/// that emits the IDENTICAL [EarthWindGrid] shape — repointing the source is
/// the only change; the bridge, JS renderer, and UI are untouched.
abstract interface class EarthWindFieldSource {
  Future<EarthWindGrid> load();
}

/// Loads the bundled, public-domain representative wind grid. No network, no
/// provider, no secret — `isLive` stays false (research honesty).
final class StaticAssetWindFieldSource implements EarthWindFieldSource {
  const StaticAssetWindFieldSource({this.assetPath = defaultAsset});

  static const defaultAsset =
      'assets/earth/wind/wind-representative-climatology-v1.json';

  final String assetPath;

  @override
  Future<EarthWindGrid> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return EarthWindGrid.fromJson(json);
  }
}

/// Phase 2 — loads the bundled, public-domain (CC0) representative
/// ocean-current grid. Same [EarthWindGrid] u/v contract as wind, so the SAME
/// particle renderer animates it (a distinct palette is chosen by the renderer
/// from the frame's flow kind). No network, no secret — `isLive` stays false.
///
/// LIVE fast-follow (NOT built this pass — static first, mirroring wind): an
/// OSCAR (or equivalent public gridded ocean-current source) scheduled function
/// can emit this exact contract and drop in via a future live-ocean source with
/// ZERO renderer changes.
final class StaticAssetOceanFieldSource implements EarthWindFieldSource {
  const StaticAssetOceanFieldSource({this.assetPath = defaultAsset});

  static const defaultAsset =
      'assets/earth/ocean/ocean-representative-currents-v1.json';

  final String assetPath;

  @override
  Future<EarthWindGrid> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return EarthWindGrid.fromJson(json);
  }
}

/// Waves — loads the bundled, public-domain (U.S. Government) representative
/// ocean-wave grid: a REAL dated NOAA WaveWatch III (ww3_global) snapshot
/// coarsened to 5° by tooling/scripts/build_earth_waves_representative.py
/// (significant wave height → magnitude, peak direction → heading). Same
/// [EarthWindGrid] u/v contract as wind/ocean, so the SAME particle renderer
/// animates it (palette chosen by the renderer from flowKind='waves'). No
/// network, no secret — `isLive` stays false.
final class StaticAssetWavesFieldSource implements EarthWindFieldSource {
  const StaticAssetWavesFieldSource({this.assetPath = defaultAsset});

  static const defaultAsset =
      'assets/earth/waves/waves-representative-72x37-v1.json';

  final String assetPath;

  @override
  Future<EarthWindGrid> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return EarthWindGrid.fromJson(json);
  }
}

/// Fetches the live function-side URL and returns the response body.
typedef EarthWindGridFetcher = Future<String> Function(Uri url);

/// Phase 1b — LIVE NOAA-GFS wind, fetched from the `earthWindGfsRefresh`
/// scheduled function's cached output (Cloud Storage, public-domain processed
/// grid: NO key, NO secret, NO raw imagery).
///
/// FAIL-SAFE: ANY failure — the function not deployed yet, 404, CORS, network,
/// or a malformed/empty grid — falls back to the static representative grid, so
/// the wind field NEVER regresses. When the function is deployed and has run
/// (and the bucket allows the app origin), the app auto-upgrades to live
/// current-conditions with NO further code change — the whole point of the
/// static-first contract.
final class LiveGfsWindFieldSource implements EarthWindFieldSource {
  const LiveGfsWindFieldSource({
    this.liveUrl = defaultLiveUrl,
    this.fallback = const StaticAssetWindFieldSource(),
    this.fetcher,
  });

  /// Public URL of the GFS-derived grid written by `earthWindGfsRefresh`
  /// (Cloud Storage bucket of project `randomknights-xyz`). Until the function
  /// is deployed + has run (and bucket CORS allows the rand0m.ai origin), this
  /// request fails and the static representative grid is used instead.
  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/wind/gfs-live-grid.json';

  final String liveUrl;
  final EarthWindFieldSource fallback;
  final EarthWindGridFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live wind grid HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthWindGrid> load() async {
    // Skip the live fetch (use the representative) when the manifest marks this
    // object undeployed — no console 403, same result as the catch below.
    if (!await EarthLiveReadyManifest.instance.isReady(liveUrl)) {
      return fallback.load();
    }
    try {
      final raw = await _fetch(Uri.parse(liveUrl));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final grid = EarthWindGrid.fromJson(json);
      if (grid.cellCount <= 0) {
        throw const FormatException('empty live wind grid');
      }
      return grid;
    } catch (_) {
      return fallback.load();
    }
  }
}

/// Phase 2 — LIVE OSCAR ocean currents, fetched from the `earthOceanOscarRefresh`
/// scheduled function's cached output (Cloud Storage, public-domain processed
/// grid: NO key, NO secret). MIRRORS [LiveGfsWindFieldSource] for the ocean
/// flow layer — same [EarthWindGrid] contract, so the renderer animates it via
/// kind='ocean' under the existing land/sea mask (ocean-only).
///
/// FAIL-SAFE: ANY failure — the function not deployed yet, 404, CORS, network,
/// or a malformed/empty grid — falls back to the static representative ocean
/// grid, so the ocean field NEVER regresses. When the function is deployed and
/// has run (and the bucket allows the app origin), the app auto-upgrades to
/// live current-conditions with NO further code change — and the grid's live
/// meta (isLive/liveReady) flips the Data View label representative -> live.
final class LiveOscarOceanFieldSource implements EarthWindFieldSource {
  const LiveOscarOceanFieldSource({
    this.liveUrl = defaultLiveUrl,
    this.fallback = const StaticAssetOceanFieldSource(),
    this.fetcher,
  });

  /// Public URL of the OSCAR-derived grid written by `earthOceanOscarRefresh`
  /// (Cloud Storage bucket of project `randomknights-xyz`). Until the function
  /// is deployed + has run (and bucket CORS allows the rand0m.ai origin), this
  /// request fails and the static representative ocean grid is used instead.
  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/ocean/oscar-live-grid.json';

  final String liveUrl;
  final EarthWindFieldSource fallback;
  final EarthWindGridFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live ocean grid HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthWindGrid> load() async {
    // Skip the live fetch (use the representative) when the manifest marks this
    // object undeployed — no console 403, same result as the catch below.
    if (!await EarthLiveReadyManifest.instance.isReady(liveUrl)) {
      return fallback.load();
    }
    try {
      final raw = await _fetch(Uri.parse(liveUrl));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final grid = EarthWindGrid.fromJson(json);
      if (grid.cellCount <= 0) {
        throw const FormatException('empty live ocean grid');
      }
      return grid;
    } catch (_) {
      return fallback.load();
    }
  }
}

/// LIVE NOAA WaveWatch III waves, fetched from a future `earthWavesRefresh`
/// scheduled function's cached output (Cloud Storage, public-domain processed
/// grid: NO key, NO secret). MIRRORS [LiveOscarOceanFieldSource] for the waves
/// flow layer — same [EarthWindGrid] contract, animated via flowKind='waves'
/// under the existing ocean land/sea mask.
///
/// FAIL-SAFE: ANY failure — the function not deployed yet, 404, CORS, network,
/// or a malformed/empty grid — falls back to the static representative waves
/// grid (a REAL dated WW3 snapshot), so the waves field NEVER regresses. When
/// the function deploys + runs (and the bucket allows the app origin), the app
/// auto-upgrades to live with NO further code change.
final class LiveWavesFieldSource implements EarthWindFieldSource {
  const LiveWavesFieldSource({
    this.liveUrl = defaultLiveUrl,
    this.fallback = const StaticAssetWavesFieldSource(),
    this.fetcher,
  });

  /// Public URL of the WW3-derived grid written by `earthWavesRefresh` (Cloud
  /// Storage bucket of project `randomknights-xyz`). Until the function is
  /// deployed + has run (and bucket CORS allows the app origin), this request
  /// fails and the static representative waves grid is used instead.
  static const defaultLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/waves/ww3-live-grid.json';

  final String liveUrl;
  final EarthWindFieldSource fallback;
  final EarthWindGridFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live waves grid HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthWindGrid> load() async {
    // Skip the live fetch (use the representative) when the manifest marks this
    // object undeployed — no console 403, same result as the catch below.
    if (!await EarthLiveReadyManifest.instance.isReady(liveUrl)) {
      return fallback.load();
    }
    try {
      final raw = await _fetch(Uri.parse(liveUrl));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final grid = EarthWindGrid.fromJson(json);
      if (grid.cellCount <= 0) {
        throw const FormatException('empty live waves grid');
      }
      return grid;
    } catch (_) {
      return fallback.load();
    }
  }
}

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';
import 'package:xyz_earth/services/earth/earth_live_ready_manifest.dart';

/// Source of an [EarthScalarGrid] for the scalar/heatmap renderer. The grid is
/// loaded Dart-side and pushed to the renderer via the bridge (mirroring the
/// wind/ocean flow-grid pattern) — the JS renderer never fetches it.
abstract interface class EarthScalarFieldSource {
  Future<EarthScalarGrid> load();
}

/// Source of an [EarthPointSet] for the point/marker renderer. Same Dart-side
/// load + bridge-push pattern as the scalar source.
abstract interface class EarthPointSetSource {
  Future<EarthPointSet> load();
}

/// Loads a bundled, public-domain representative point set (wildfire,
/// biodiversity). No network, no secret — `isLive` stays false so the Data View
/// labels it representative (data-binding honesty).
final class StaticAssetPointSetSource implements EarthPointSetSource {
  const StaticAssetPointSetSource({required this.assetPath});

  /// Representative wildfire detections (land domain, `fire` palette).
  static const wildfireAsset =
      'assets/earth/points/wildfire-representative-v1.json';

  /// Representative biodiversity richness (land domain, `mag` palette).
  static const biodiversityAsset =
      'assets/earth/points/biodiversity-representative-v1.json';

  /// Batch-2 representative point sets (land domain).
  static const glaciersAsset =
      'assets/earth/points/glaciers-representative-v1.json';
  static const carbonOffsetAsset =
      'assets/earth/points/carbon-offset-berkeley-v2026-04.json';

  /// Spatially CLUSTERED Berkeley VCM carbon points (dense ~2° cells collapsed
  /// to one count-sized dot) — what the globe renders. ~643 dots vs 5,934, so it
  /// loads fast and dense metro blobs read as a single larger dot. The full
  /// per-project set ([carbonOffsetAsset]) backs the Data View project browser.
  static const clusteredCarbonOffsetAsset =
      'assets/earth/points/carbon-offset-clustered-v2026-04.json';

  /// Earth impact-players CLUSTERED point sets (earth.pointset.v1, built by
  /// tooling/scripts/build_earth_pointsets.py from the impact workbooks; dense
  /// regions collapsed to count-sized dots). Static, no live feed.
  /// species-threatened = IUCN Red List (CR/EN/VU) located via GBIF (CC BY-NC).
  static const speciesThreatenedAsset =
      'assets/earth/points/species-threatened-clustered-v1.json';

  /// businesses-footprint = top emitters' operating sites (Climate TRACE,
  /// CC BY 4.0), sized by attributed CO2e.
  static const businessesFootprintAsset =
      'assets/earth/points/businesses-footprint-clustered-v1.json';

  /// datacenters = PeeringDB facilities + a small curated announced set (CC-BY).
  static const datacentersAsset =
      'assets/earth/points/datacenters-clustered-v1.json';

  /// industrial-sites = Climate TRACE v6 industrial emitters (CC BY 4.0), sized
  /// by annual CO2e.
  static const industrialSitesAsset =
      'assets/earth/points/industrial-sites-clustered-v1.json';

  /// protected-areas-points = Wikidata/WDPA exact protected-area points (CC0).
  /// ADDITIVE to (distinct from) the existing `protected-areas` SCALAR layer.
  static const protectedAreasPointsAsset =
      'assets/earth/points/protected-areas-points-clustered-v1.json';

  /// power-plants = WRI Global Power Plant Database v1.3.0 (CC BY 4.0); exact
  /// plant coordinates with fuel type + capacity (MW).
  static const powerPlantsAsset =
      'assets/earth/points/power-plants-clustered-v1.json';

  /// extraction-sites = Maus et al. global mining polygons v2 (PANGAEA, CC BY
  /// 4.0); polygon centroids sized by mined area (km²).
  static const extractionSitesAsset =
      'assets/earth/points/extraction-sites-clustered-v1.json';

  /// flights = ambient airborne-aircraft positions (OpenSky ADS-B), bundled
  /// representative for offline/fail-safe. Identity-stripped (lat/lon/value
  /// only); rendered non-interactive + decimated as ambient flow.
  static const flightsAsset =
      'assets/earth/points/flights-representative-v1.json';

  /// boats = ambient vessel activity (Global Fishing Watch aggregated fishing
  /// effort), bundled representative for offline/fail-safe. Identity-FREE
  /// (lat/lon/value only); rendered non-interactive teal DIAMOND dots.
  static const boatsAsset =
      'assets/earth/points/boats-representative-v1.json';

  /// environmental-nonprofits = US environmental nonprofits (IRS Exempt
  /// Organizations BMF located via US Census ZCTA Gazetteer ZIP centroids;
  /// value = log10 annual revenue USD). Representative offline sample AGGREGATED
  /// to coarse ZIP-code-area centroids - identity-free (org counts, never named
  /// organizations). The app ships an empty pending fallback; xyz-earth ships a
  /// representative so the keyless boot always renders the layer.
  static const environmentalNonprofitsAsset =
      'assets/earth/points/environmental-nonprofits-representative-v1.json';

  final String assetPath;

  @override
  Future<EarthPointSet> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return EarthPointSet.fromJson(json);
  }
}

/// LIVE point set: reads an App scheduled-function point snapshot from Cloud
/// Storage as PRIMARY (FIRMS wildfire / GBIF biodiversity), FAIL-SAFE to the
/// bundled representative set. Until the function has run the fetch fails and
/// the representative set is used (data-binding honesty preserved). Mirrors
/// [LiveStorageScalarFieldSource].
final class LiveStoragePointSetSource implements EarthPointSetSource {
  const LiveStoragePointSetSource({
    required this.liveUrl,
    required this.fallback,
    this.fetcher,
  });

  static const _base =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/';

  /// FIRMS wildfire detections (point snapshot written by the App refresher).
  static const wildfireLiveUrl = '${_base}earth/wildfires/wildfire-points.json';

  /// GBIF biodiversity occurrences (coarse, suppression-guarded snapshot).
  static const biodiversityLiveUrl =
      '${_base}earth/biodiversity/biodiversity-points.json';

  /// Batch-2 point live snapshots. Glaciers ships live from the App (e6da040);
  /// VCM/carbon-offset reads its (future) App snapshot and fail-soft to the
  /// representative set until the App ships it (App callout).
  static const glaciersLiveUrl = '${_base}earth/glaciers/glacier-points.json';
  static const carbonOffsetLiveUrl =
      '${_base}earth/carbon-offset/vcm-points.json';

  /// flights = live airborne-aircraft positions written by the GH-Actions
  /// OpenSky relay (identity-stripped public ADS-B; lat/lon + ground-speed).
  static const flightsLiveUrl = '${_base}earth/flights/flight-points.json';

  /// boats = live vessel activity written by the GH-Actions Global Fishing
  /// Watch relay (aggregated apparent fishing effort; identity-free lat/lon +
  /// activity hours). Fail-soft to the bundled representative until populated.
  static const boatsLiveUrl = '${_base}earth/boats/boat-points.json';

  /// power-plants = future WRI GPPD point snapshot; representative-first until a
  /// refresher writes it (gated notReady in live-ready.json, so no 403).
  static const powerPlantsLiveUrl =
      '${_base}earth/power-plants/power-plant-points.json';

  /// extraction-sites = future Maus mining-polygon point snapshot;
  /// representative-first until a refresher writes it (gated notReady).
  static const extractionSitesLiveUrl =
      '${_base}earth/extraction/extraction-points.json';

  final String liveUrl;
  final EarthPointSetSource fallback;
  final EarthScalarGridFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live point set HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthPointSet> load() async {
    // Skip the live fetch (use the representative directly) when the manifest
    // marks this object undeployed — avoids a console 403 with no behaviour
    // change (the fallback is what the catch below would return anyway).
    if (!await EarthLiveReadyManifest.instance.isReady(liveUrl)) {
      return fallback.load();
    }
    try {
      final raw = await _fetch(Uri.parse(liveUrl));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final set = EarthPointSet.fromJson(json);
      if (set.pointCount <= 0) {
        throw const FormatException('empty live point set');
      }
      return set;
    } catch (_) {
      return fallback.load();
    }
  }
}

/// Wraps a point-set source and renders the result as an AMBIENT, non-trackable
/// mobility layer (flights / boats): the loaded set is marked non-interactive
/// (no per-point click/readout) and decimated to at most [maxPoints] so it reads
/// as flow, not followable targets. The governance lock for live-position
/// layers (identity is already absent from the model).
final class AmbientPointSetSource implements EarthPointSetSource {
  const AmbientPointSetSource({required this.inner, this.maxPoints = 1500});

  final EarthPointSetSource inner;
  final int maxPoints;

  @override
  Future<EarthPointSet> load() async =>
      (await inner.load()).ambient(maxPoints: maxPoints);
}

/// Loads a bundled, public-domain representative scalar grid (e.g. the analytic
/// air-quality field). No network, no provider, no secret — `isLive` stays false
/// so the Data View labels it representative (data-binding honesty).
final class StaticAssetScalarFieldSource implements EarthScalarFieldSource {
  const StaticAssetScalarFieldSource({required this.assetPath});

  /// The representative air-quality (US AQI) grid (land domain, `aqi` palette).
  static const airQualityAsset =
      'assets/earth/scalar/air-quality-representative-72x37-v1.json';

  /// Representative surface PM2.5 grid (global domain, `aqi` palette) — a real
  /// CAMS snapshot coarsened to 5°. The live upgrade reads the earth-worker
  /// CAMS grid via [LiveStorageScalarFieldSource.particulatesLiveUrl].
  static const particulatesAsset =
      'assets/earth/scalar/particulates-representative-72x37-v1.json';

  /// Representative surface NO₂ grid (global domain, `mag` palette) — a real
  /// CAMS snapshot coarsened to 5°. The live upgrade reads the earth-worker
  /// CAMS grid via [LiveStorageScalarFieldSource.chemistryLiveUrl].
  static const chemistryAsset =
      'assets/earth/scalar/chemistry-representative-72x37-v1.json';

  /// Representative forest-cover grid (land domain, `veg` palette).
  static const forestAsset =
      'assets/earth/scalar/forest-representative-72x37-v1.json';

  /// Representative human-density grid. Item 8: upgraded to a FINE 360x180 (1°)
  /// population-density model flagged `choropleth` so it renders as a crisp,
  /// stepped choropleth (aqi green->red) instead of a coarse `mag` blob.
  static const humanDensityAsset =
      'assets/earth/scalar/human-density-representative-360x180-v2.json';

  /// Representative ABSOLUTE sea-surface-temperature grid (ocean domain,
  /// `thermal` palette, full -2..32 °C scale). The live upgrade reads the App
  /// SST grid (NOAA OISST V2.1) via
  /// [LiveStorageScalarFieldSource.sstLiveUrl] (representative-first).
  static const sstAsset =
      'assets/earth/scalar/sst-representative-72x37-v1.json';

  /// Representative SST ANOMALY grid (ocean domain, -2..4 °C). The representative
  /// is the climatological mean → zero anomaly; the live NOAA OISST SSTA grid
  /// ([LiveStorageScalarFieldSource.sstaLiveUrl]) carries the real anomaly.
  static const sstaAsset =
      'assets/earth/scalar/ssta-representative-72x37-v1.json';

  /// Representative Bleaching Alert Area grid (ocean domain, 0-4 alert levels) —
  /// a REAL dated NOAA Coral Reef Watch 7-day-max snapshot coarsened to 5° (like
  /// the CAMS particulates representative). Live via
  /// [LiveStorageScalarFieldSource.baaLiveUrl] once a refresher ships.
  static const baaAsset =
      'assets/earth/scalar/baa-representative-72x37-v1.json';

  /// Batch-2 representative scalar grids (land domain).
  static const carbonAsset =
      'assets/earth/scalar/carbon-representative-72x37-v1.json';
  static const protectedAreasAsset =
      'assets/earth/scalar/protected-areas-representative-72x37-v1.json';
  static const treeTimeAsset =
      'assets/earth/scalar/tree-time-representative-72x37-v1.json';

  /// NEW atmosphere overlays (excluded from the score), representative→live.
  /// CAPE = GFS convective instability (J/kg). Live via
  /// [LiveStorageScalarFieldSource.capeLiveUrl] once a GFS refresher ships.
  static const capeAsset =
      'assets/earth/scalar/cape-representative-72x37-v1.json';

  /// Dust AOD@550nm (CAMS, dimensionless). Live via [dustAodLiveUrl].
  static const dustAodAsset =
      'assets/earth/scalar/dust-aod-representative-72x37-v1.json';

  /// Misery index = NWS apparent feels-like °C (heat index ⊕ wind chill) from
  /// GFS 2m temp/humidity/10m wind. Live via [miseryIndexLiveUrl].
  static const miseryIndexAsset =
      'assets/earth/scalar/misery-index-representative-72x37-v1.json';

  final String assetPath;

  @override
  Future<EarthScalarGrid> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return EarthScalarGrid.fromJson(json);
  }
}

/// Fetches a function-side cached scalar grid URL and returns the response body.
typedef EarthScalarGridFetcher = Future<String> Function(Uri url);

/// LIVE fast-follow scaffold: reads a scheduled-function cached scalar grid from
/// Cloud Storage as PRIMARY (mirroring [LiveGfsWindFieldSource]), FAIL-SAFE to a
/// static representative grid. Until a refresh function exists + has run, the
/// fetch fails and the representative grid is used (honesty preserved). Wired
/// only when a layer's live grid function ships.
final class LiveStorageScalarFieldSource implements EarthScalarFieldSource {
  const LiveStorageScalarFieldSource({
    required this.liveUrl,
    required this.fallback,
    this.fetcher,
  });

  /// The App SST grid in Cloud Storage (`earth/sst/sst-grid.json`), written by
  /// the `earthSstRefresh` scheduled function. Until that function is deployed
  /// and has run, the fetch fails and the representative ocean grid is used
  /// (data-binding honesty preserved). Mirrors [LiveGfsWindFieldSource].
  static const sstLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/sst/sst-grid.json';

  /// SST ANOMALY grid — written ALONGSIDE the absolute grid by the same
  /// `earthSstRefresh` (one deploy ships both); representative-first until then.
  static const sstaLiveUrl =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/'
      'earth/ssta/ssta-grid.json';

  /// Storage base for the App-written scheduled-function grids.
  static const _base =
      'https://storage.googleapis.com/randomknights-xyz.firebasestorage.app/';

  /// App live scalar grids (written by the scheduled refreshers). Each
  /// fail-safes to its bundled representative grid until the function has run.
  static const airQualityLiveUrl = '${_base}earth/air-quality/air-quality-grid.json';

  /// CAMS surface PM2.5 grid written by the earth-worker Cloud Run Job
  /// (`earth/particulates/particulates-grid.json`). Until the worker is deployed
  /// and has run, the fetch fails and the representative grid is used.
  static const particulatesLiveUrl =
      '${_base}earth/particulates/particulates-grid.json';

  /// CAMS surface NO₂ grid written by the earth-worker Cloud Run Job
  /// (`earth/chemistry/chemistry-grid.json`); representative until it runs.
  static const chemistryLiveUrl =
      '${_base}earth/chemistry/chemistry-grid.json';
  static const forestLiveUrl = '${_base}earth/forest/forest-grid.json';
  static const humanDensityLiveUrl = '${_base}earth/human-density/human-density-grid.json';
  static const humanModificationLiveUrl = '${_base}earth/human-modification/ghm-grid.json';

  /// Batch-2 scalar live grids. Carbon ships live from the App refresher
  /// (e6da040). Protected-areas / tree-time read their (future) App grids and
  /// fail-soft to the representative grid until the App ships them (App callout).
  static const carbonLiveUrl = '${_base}earth/carbon/carbon-grid.json';
  static const protectedAreasLiveUrl =
      '${_base}earth/protected-areas/protected-areas-grid.json';
  static const treeTimeLiveUrl = '${_base}earth/tree-time/tree-time-grid.json';

  /// NOAA Coral Reef Watch Bleaching Alert Area grid (`earth/baa/baa-grid.json`).
  /// Until an `earthBaaRefresh` function writes it, the fetch fails and the REAL
  /// dated representative snapshot is used (data-binding honesty preserved).
  static const baaLiveUrl = '${_base}earth/baa/baa-grid.json';

  /// NEW atmosphere overlays — App refresher grids (representative-first until
  /// they ship). CAPE/misery-index off the GFS feed; dust-aod off the CAMS pipe.
  static const capeLiveUrl = '${_base}earth/cape/cape-grid.json';
  static const dustAodLiveUrl = '${_base}earth/dust-aod/dust-aod-grid.json';
  static const miseryIndexLiveUrl =
      '${_base}earth/misery-index/misery-index-grid.json';

  final String liveUrl;
  final EarthScalarFieldSource fallback;
  final EarthScalarGridFetcher? fetcher;

  Future<String> _fetch(Uri url) async {
    final f = fetcher;
    if (f != null) return f(url);
    final resp = await http.get(url).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('live scalar grid HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  @override
  Future<EarthScalarGrid> load() async {
    // Skip the live fetch (use the representative directly) when the manifest
    // marks this object undeployed — avoids a console 403 with no behaviour
    // change (the fallback is what the catch below would return anyway).
    if (!await EarthLiveReadyManifest.instance.isReady(liveUrl)) {
      return fallback.load();
    }
    try {
      final raw = await _fetch(Uri.parse(liveUrl));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final grid = EarthScalarGrid.fromJson(json);
      if (grid.cellCount <= 0) {
        throw const FormatException('empty live scalar grid');
      }
      return grid;
    } catch (_) {
      return fallback.load();
    }
  }
}

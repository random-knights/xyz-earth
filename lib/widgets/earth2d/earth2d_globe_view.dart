// lib/widgets/earth2d/earth2d_globe_view.dart
//
// 2D-canvas globe view (web) — the north-star renderer behind the OFF-by-default
// kEarth2dRendererEnabled flag. Mounted ONLY by [EarthRendererToggle]; the toggle
// keeps exactly one renderer active, so this and the Cesium view never run at the
// same time.
//
// INTEGRATION SHAPE (mirrors EarthCesiumGlobeView): this view takes the SAME
// ID-based inputs the Cesium view takes (animate/overlay/annotation layer ids +
// stageVisible/reducedMotion/hd + My-Location) and OWNS its own renderer-agnostic
// [EarthFrameResolver] (constructed from the SAME *Source seams the Cesium view
// uses). It calls `resolver.load(...)` in initState (mounted-guarded kind
// callbacks), and on each build / relevant change resolves the scalar / flow /
// point frame for the CURRENT layer ids and feeds them to the disjoint
// `window.__earth2d` JS bridge. Two resolver instances (one per renderer) is fine
// — only the active renderer's resolver ever loads.
//
// BOUNDARY: new file. Consumes Agent-A models + the EarthFrameResolver + the
// EarthOverlayScaleChannel.active notifier READ-ONLY; never edits them.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:xyz_earth/models/earth/earth_layer_snapshot_card.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';
import 'package:xyz_earth/services/earth/earth_frame_resolver.dart';
import 'package:xyz_earth/services/earth/earth_scalar_field_source.dart';
import 'package:xyz_earth/services/earth/earth_satellite_point_source.dart';
import 'package:xyz_earth/services/earth/earth_wind_field_source.dart';
import 'package:xyz_earth/services/earth2d/earth2d_bridge.dart';
import 'package:xyz_earth/services/earth2d/earth2d_bridge_factory.dart';
import 'package:xyz_earth/services/earth2d/earth2d_region_geometry.dart';
// Read-only use of the Earth agent's PUBLISHED scale notifier (not an edit): the
// filter-panel scale bar listens to it, so republishing from the 2D view gives
// chrome parity with zero chrome changes. The toggle keeps the renderers
// mutually exclusive, so only one ever drives this notifier.
import 'package:xyz_earth/globe/earth_overlay_scale_channel.dart';

/// 2D-canvas globe view (web). Hosts an [HtmlElementView] whose div the
/// `window.__earth2d` shim fills with a `<canvas>` + d3-geo renderer, then drives
/// it from frames resolved by an owned [EarthFrameResolver] for the current
/// layer ids. Default-OFF behind the flag.
class Earth2dGlobeView extends StatefulWidget {
  const Earth2dGlobeView({
    super.key,
    this.animateLayerId,
    this.overlayLayerId,
    this.annotationLayerId,
    this.projectionId = 'orthographic',
    this.reducedMotion = false,
    this.stageVisible = true,
    this.hd = false,
    this.spin = false,
    this.inspectEnabled = true,
    this.overlayOpen = false,
    this.selectedRegionId = 'global',
    this.regionLaserActive = false,
    this.myLocationLat,
    this.myLocationLon,
    // Same source seams the Cesium view uses (identical defaults), so the 2D
    // renderer resolves byte-identical frames. The toggle keeps exactly one
    // renderer active, so only the live renderer's resolver ever loads.
    this.windFieldSource = const LiveGfsWindFieldSource(),
    this.oceanFieldSource = const LiveOscarOceanFieldSource(),
    this.wavesFieldSource = const LiveWavesFieldSource(),
    this.airQualityScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.airQualityLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.airQualityAsset,
      ),
    ),
    this.particulatesScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.particulatesLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.particulatesAsset,
      ),
    ),
    this.chemistryScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.chemistryLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.chemistryAsset,
      ),
    ),
    // NEW atmosphere overlays (excluded from the score), representative→live.
    this.capeScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.capeLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.capeAsset,
      ),
    ),
    this.dustAodScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.dustAodLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.dustAodAsset,
      ),
    ),
    this.miseryIndexScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.miseryIndexLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.miseryIndexAsset,
      ),
    ),
    this.forestScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.forestLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.forestAsset,
      ),
    ),
    this.humanDensityScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.humanDensityLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.humanDensityAsset,
      ),
    ),
    this.humanModificationScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.humanModificationLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.humanDensityAsset,
      ),
    ),
    this.sstScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.sstLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.sstAsset,
      ),
    ),
    this.sstaScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.sstaLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.sstaAsset,
      ),
    ),
    this.baaScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.baaLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.baaAsset,
      ),
    ),
    this.carbonScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.carbonLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.carbonAsset,
      ),
    ),
    this.protectedAreasScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.protectedAreasLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.protectedAreasAsset,
      ),
    ),
    this.treeTimeScalarSource = const LiveStorageScalarFieldSource(
      liveUrl: LiveStorageScalarFieldSource.treeTimeLiveUrl,
      fallback: StaticAssetScalarFieldSource(
        assetPath: StaticAssetScalarFieldSource.treeTimeAsset,
      ),
    ),
    this.wildfirePointSource = const LiveStoragePointSetSource(
      liveUrl: LiveStoragePointSetSource.wildfireLiveUrl,
      fallback: StaticAssetPointSetSource(
        assetPath: StaticAssetPointSetSource.wildfireAsset,
      ),
    ),
    this.biodiversityPointSource = const LiveStoragePointSetSource(
      liveUrl: LiveStoragePointSetSource.biodiversityLiveUrl,
      fallback: StaticAssetPointSetSource(
        assetPath: StaticAssetPointSetSource.biodiversityAsset,
      ),
    ),
    this.glacierPointSource = const LiveStoragePointSetSource(
      liveUrl: LiveStoragePointSetSource.glaciersLiveUrl,
      fallback: StaticAssetPointSetSource(
        assetPath: StaticAssetPointSetSource.glaciersAsset,
      ),
    ),
    this.carbonOffsetPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.clusteredCarbonOffsetAsset,
    ),
    // Earth impact-players point verticals (clustered earth.pointset.v1, static
    // ingest; mirror of the Cesium view so both renderers show the layers).
    // protected-areas-points is ADDITIVE — leaves the `protected-areas` scalar
    // layer (read by the health score) untouched.
    this.speciesThreatenedPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.speciesThreatenedAsset,
    ),
    this.businessesFootprintPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.businessesFootprintAsset,
    ),
    this.datacentersPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.datacentersAsset,
    ),
    this.industrialSitesPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.industrialSitesAsset,
    ),
    this.protectedAreasPointsPointSource = const StaticAssetPointSetSource(
      assetPath: StaticAssetPointSetSource.protectedAreasPointsAsset,
    ),
    // Anthroposphere annotation verticals (WRI power plants + Maus extraction):
    // live-storage source with a representative fallback, so they flip live
    // with NO client change once a refresher writes the snapshot.
    this.powerPlantsPointSource = const LiveStoragePointSetSource(
      liveUrl: LiveStoragePointSetSource.powerPlantsLiveUrl,
      fallback: StaticAssetPointSetSource(
        assetPath: StaticAssetPointSetSource.powerPlantsAsset,
      ),
    ),
    this.extractionSitesPointSource = const LiveStoragePointSetSource(
      liveUrl: LiveStoragePointSetSource.extractionSitesLiveUrl,
      fallback: StaticAssetPointSetSource(
        assetPath: StaticAssetPointSetSource.extractionSitesAsset,
      ),
    ),
    // Ambient airborne aircraft (OpenSky ADS-B): live, fail-safe to bundled
    // representative; non-interactive + decimated flow dots.
    this.flightsPointSource = const AmbientPointSetSource(
      inner: LiveStoragePointSetSource(
        liveUrl: LiveStoragePointSetSource.flightsLiveUrl,
        fallback: StaticAssetPointSetSource(
          assetPath: StaticAssetPointSetSource.flightsAsset,
        ),
      ),
    ),
    // Ambient vessel activity (Global Fishing Watch): live, fail-safe to bundled
    // representative; non-interactive teal diamond dots.
    this.boatsPointSource = const AmbientPointSetSource(
      inner: LiveStoragePointSetSource(
        liveUrl: LiveStoragePointSetSource.boatsLiveUrl,
        fallback: StaticAssetPointSetSource(
          assetPath: StaticAssetPointSetSource.boatsAsset,
        ),
      ),
    ),
    // Ambient satellite orbit bands + named satellites (Space mode).
    this.satellitesPointSource = const SatellitePointSetSource(),
  });

  /// Slice 3 composite slots (same ids the Cesium view takes). Flow slot
  /// (wind / ocean-currents); null = off.
  final String? animateLayerId;

  /// Scalar overlay slot (one of the scalar layers); null = off.
  final String? overlayLayerId;

  /// Point annotation slot (one of the point layers); null = off.
  final String? annotationLayerId;

  /// Active 2D projection (one of Earth2dProjections.ids).
  final String projectionId;

  /// MediaQuery reduced-motion — folds into every frame's motion budget.
  final bool reducedMotion;

  /// Whether the globe stage is on-screen; suspends the render loop off-stage.
  final bool stageVisible;

  /// HD toggle — raises the flow-field particle budget.
  final bool hd;

  /// Rotate toggle — gently auto-spins the globe (earth+ Control row).
  final bool spin;

  /// Item A — Target Lat/Long: when true a globe click drops a lat/long + flow
  /// readout at the point; when false clicks are inert. Default true.
  final bool inspectEnabled;

  /// Whether ANY earth+ overlay box (score/summary/context/filters) is open. While
  /// true the 2D globe's USER camera input (wheel-zoom + drag) is frozen at the
  /// shim, so scrolling inside the box can't zoom/rotate the globe underneath —
  /// parity with the Cesium view's overlayOpen → setCameraInputsEnabled(false).
  final bool overlayOpen;

  /// Region focus (same id the Cesium view takes). Non-global → eased-rotate to
  /// the region centroid + (when [regionLaserActive]) a region laser. Sourced
  /// from the Dart-owned [kEarth2dRegionCentroids] (parity with Cesium).
  final String selectedRegionId;

  /// Explicit-selection laser gate (mirrors the Cesium view): the laser draws
  /// only when true. A programmatic focus (rotate-on-load / restored filters)
  /// rotates WITHOUT a laser.
  final bool regionLaserActive;

  /// My-Location coords (when My Location is the active region + geolocation has
  /// resolved); null otherwise. Drives the neon dot + rotate-to-location.
  final double? myLocationLat;
  final double? myLocationLon;

  /// Source seams (identical defaults to EarthCesiumGlobeView).
  final EarthWindFieldSource windFieldSource;
  final EarthWindFieldSource oceanFieldSource;
  final EarthWindFieldSource wavesFieldSource;
  final EarthScalarFieldSource airQualityScalarSource;
  final EarthScalarFieldSource particulatesScalarSource;
  final EarthScalarFieldSource chemistryScalarSource;
  final EarthScalarFieldSource capeScalarSource;
  final EarthScalarFieldSource dustAodScalarSource;
  final EarthScalarFieldSource miseryIndexScalarSource;
  final EarthScalarFieldSource forestScalarSource;
  final EarthScalarFieldSource humanDensityScalarSource;
  final EarthScalarFieldSource humanModificationScalarSource;
  final EarthScalarFieldSource sstScalarSource;
  final EarthScalarFieldSource sstaScalarSource;
  final EarthScalarFieldSource baaScalarSource;
  final EarthScalarFieldSource carbonScalarSource;
  final EarthScalarFieldSource protectedAreasScalarSource;
  final EarthScalarFieldSource treeTimeScalarSource;
  final EarthPointSetSource wildfirePointSource;
  final EarthPointSetSource biodiversityPointSource;
  final EarthPointSetSource glacierPointSource;
  final EarthPointSetSource carbonOffsetPointSource;
  final EarthPointSetSource speciesThreatenedPointSource;
  final EarthPointSetSource businessesFootprintPointSource;
  final EarthPointSetSource datacentersPointSource;
  final EarthPointSetSource industrialSitesPointSource;
  final EarthPointSetSource flightsPointSource;
  final EarthPointSetSource boatsPointSource;
  final EarthPointSetSource satellitesPointSource;
  final EarthPointSetSource protectedAreasPointsPointSource;
  final EarthPointSetSource powerPlantsPointSource;
  final EarthPointSetSource extractionSitesPointSource;

  @override
  State<Earth2dGlobeView> createState() => _Earth2dGlobeViewState();
}

class _Earth2dGlobeViewState extends State<Earth2dGlobeView> {
  static int _seq = 0;
  late final String _viewType = 'earth2d-view-${_seq++}';
  late final Earth2dBridge _bridge = createEarth2dBridge(viewType: _viewType);
  bool _attached = false;

  /// Renderer-agnostic frame resolver — owns the governed wind/ocean/scalar/point
  /// storage and resolves the per-layer frames. Constructed from the SAME source
  /// seams the Cesium view uses (mirrors that construction exactly).
  late final EarthFrameResolver _resolver;

  /// Dedup guards — only re-push a frame to the bridge when its signature
  /// changes (mirrors the Cesium view's _syncSig/_scalarSig/_pointSig).
  String? _syncSig;
  String? _scalarSig;
  String? _pointSig;

  @override
  void initState() {
    super.initState();
    // Register the platform-view factory NOW (before the first build renders
    // HtmlElementView(viewType: _viewType)) — otherwise Flutter creates the
    // platform view before its factory exists and throws unregistered_view_type
    // (the disappearing-2D-globe bug). The post-frame attach() is the shim hook.
    _bridge.registerView();
    _resolver = EarthFrameResolver(
      windFieldSource: widget.windFieldSource,
      oceanFieldSource: widget.oceanFieldSource,
      wavesFieldSource: widget.wavesFieldSource,
      scalarSources: {
        'air-quality': widget.airQualityScalarSource,
        'particulates': widget.particulatesScalarSource,
        'chemistry': widget.chemistryScalarSource,
        'cape': widget.capeScalarSource,
        'dust-aod': widget.dustAodScalarSource,
        'misery-index': widget.miseryIndexScalarSource,
        'forest': widget.forestScalarSource,
        'human-encroachment': widget.humanDensityScalarSource,
        'human-modification': widget.humanModificationScalarSource,
        'sst': widget.sstScalarSource,
        'ssta': widget.sstaScalarSource,
        'baa': widget.baaScalarSource,
        'carbon': widget.carbonScalarSource,
        'protected-areas': widget.protectedAreasScalarSource,
        'tree-time': widget.treeTimeScalarSource,
      },
      pointSources: {
        'wildfires': widget.wildfirePointSource,
        'biodiversity-habitat': widget.biodiversityPointSource,
        'glaciers': widget.glacierPointSource,
        'carbon-offset-projects': widget.carbonOffsetPointSource,
        'species-threatened': widget.speciesThreatenedPointSource,
        'businesses-footprint': widget.businessesFootprintPointSource,
        'datacenters': widget.datacentersPointSource,
        'industrial-sites': widget.industrialSitesPointSource,
        'protected-areas-points': widget.protectedAreasPointsPointSource,
        'power-plants': widget.powerPlantsPointSource,
        'extraction-sites': widget.extractionSitesPointSource,
        'flights': widget.flightsPointSource,
        'boats': widget.boatsPointSource,
        'satellites': widget.satellitesPointSource,
      },
    );
    // Publish the scale-bar value scale immediately (chrome is independent of
    // the canvas attaching / the grid loading — republished as data lands).
    _publishOverlayScale();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _attached = await _bridge.attach(_viewType);
      if (!mounted || !_attached) return;
      _bridge.setProjection(widget.projectionId);
      _bridge.setSpin(widget.spin);
      _bridge.setInspectEnabled(widget.inspectEnabled);
      // Item A: publish any flow grids that loaded before attach as probe
      // channels (later loads re-push via onFlowLoaded).
      _pushProbeGrids();
      // Freeze user camera input if an overlay box is already open at attach.
      _bridge.setInteractive(!widget.overlayOpen);
      // Marker click snapshots: forward the governed snapshot JSON the shim
      // emits (CustomEvent 'earth2d-pick') to the SAME notifier the Cesium path
      // feeds, parsed by the SAME card model — identical card chrome, no edits.
      _bridge.setOnPick((raw) {
        if (!mounted) return;
        EarthPickedSnapshot.notifier.value =
            raw.isEmpty ? null : EarthLayerSnapshotCard.tryParse(raw);
      });
      // Push whatever has resolved so far (deduped); load() callbacks below
      // re-push each slot as its data lands.
      _pushScalar();
      _pushFlow();
      _pushPoint();
      // Region focus / laser / my-location (item 4 + 5). Mirrors the Cesium
      // view: rotate to the region centroid, laser only when explicitly active,
      // neon dot at My Location.
      _pushRegion();
      _pushMyLocation();
      if (!widget.stageVisible) _bridge.suspend();
    });
    _loadGrids();
  }

  Future<void> _loadGrids() async {
    // Concurrent, fail-closed preload delegated to the resolver; as each source
    // resolves we re-push exactly that slot (mirrors the Cesium view's per-kind
    // setState + _syncXField interleave). setState rebuilds so the resolved
    // overlay scale is republished too.
    await _resolver.load(
      onFlowLoaded: () {
        if (!mounted) return;
        setState(() {});
        _pushFlow();
        // Item A: re-publish the inspect probe channels as each flow grid lands.
        _pushProbeGrids();
      },
      onScalarLoaded: () {
        if (!mounted) return;
        setState(() {});
        _pushScalar();
      },
      onPointLoaded: () {
        if (!mounted) return;
        setState(() {});
        _pushPoint();
      },
    );
  }

  /// Resolves the SCALAR frame for the current overlay slot, republishes the
  /// scale-bar value scale (slice-5a parity), and pushes the frame to the bridge
  /// (deduped). No-op if not attached yet (the post-frame attach pushes once).
  void _pushScalar() {
    final frame = _resolver.scalarFrameFor(
      widget.overlayLayerId ?? '',
      stageVisible: widget.stageVisible,
      reducedMotion: widget.reducedMotion,
    );
    EarthOverlayScaleChannel.active.value = frame.active
        ? EarthOverlayScale.fromGrid(
            frame.grid!,
            paletteOverride: frame.paletteOverride,
          )
        : null;
    if (!_attached) return;
    final sig = '${widget.overlayLayerId}|${frame.active}|'
        '${frame.grid?.vintage ?? '-'}';
    if (sig == _scalarSig) return;
    _scalarSig = sig;
    _bridge.syncScalarField(frame);
  }

  /// Resolves the FLOW frame for the current animate slot + motion budget and
  /// pushes it to the bridge (deduped).
  void _pushFlow() {
    final frame = _resolver.flowFrameFor(
      widget.animateLayerId ?? '',
      stageVisible: widget.stageVisible,
      reducedMotion: widget.reducedMotion,
      hd: widget.hd,
    );
    if (!_attached) return;
    final grid = frame.flowGrid;
    final sig = '${widget.animateLayerId}|${frame.animate}|'
        '${grid?.vintage ?? '-'}|hd${widget.hd}';
    if (sig == _syncSig) return;
    _syncSig = sig;
    _bridge.syncFlowField(frame);
  }

  /// Item A — Target Lat/Long: push the wind/current/wave PROBE grids so the
  /// click-to-inspect readout can sample all applicable channels independent of
  /// which one is animating (wind over land + ocean; current/waves ocean-only).
  void _pushProbeGrids() {
    if (!_attached) return;
    final payload = <String, dynamic>{
      'wind': _resolver.windProbeGrid?.toBridgeJson(),
      'ocean': _resolver.oceanProbeGrid?.toBridgeJson(),
      'waves': _resolver.wavesProbeGrid?.toBridgeJson(),
    };
    _bridge.setProbeGrids(jsonEncode(payload));
  }

  /// Resolves the POINT frame for the current annotation slot and pushes it to
  /// the bridge (deduped).
  void _pushPoint() {
    final frame = _resolver.pointFrameFor(
      widget.annotationLayerId ?? '',
      stageVisible: widget.stageVisible,
      reducedMotion: widget.reducedMotion,
    );
    if (!_attached) return;
    final sig = '${widget.annotationLayerId}|${frame.active}|'
        '${frame.pointSet?.pointCount ?? 0}';
    if (sig == _pointSig) return;
    _pointSig = sig;
    _bridge.syncPointField(frame);
  }

  /// Region focus (item 4): eased-rotate to the region centroid and set the
  /// laser gate. Global / unknown region clears the focus (no rotate, no laser).
  /// Centroid lat/lon come from the Dart-owned geometry, not the Cesium shim.
  void _pushRegion() {
    if (!_attached) return;
    final c = earth2dRegionCentroid(widget.selectedRegionId);
    _bridge.setRegion(
      regionId: widget.selectedRegionId,
      centroidLat: c?.lat,
      centroidLon: c?.lon,
      rotate: true,
    );
    _bridge.setLaser(widget.regionLaserActive);
  }

  /// My-Location (item 5): neon dot at the resolved coords + rotate-to-location;
  /// null coords clear the dot.
  void _pushMyLocation() {
    if (!_attached) return;
    _bridge.setMyLocation(
      lat: widget.myLocationLat,
      lon: widget.myLocationLon,
      rotate: true,
    );
  }

  /// Filter-chrome parity: republish the active scalar overlay's value scale to
  /// the SAME notifier the scale-bar chrome listens to (mirrors the Cesium
  /// view's slice-5a publish). Used before attach / before the grid loads; once
  /// attached, [_pushScalar] keeps it current.
  void _publishOverlayScale() {
    final frame = _resolver.scalarFrameFor(
      widget.overlayLayerId ?? '',
      stageVisible: widget.stageVisible,
      reducedMotion: widget.reducedMotion,
    );
    EarthOverlayScaleChannel.active.value = frame.active
        ? EarthOverlayScale.fromGrid(
            frame.grid!,
            paletteOverride: frame.paletteOverride,
          )
        : null;
  }

  @override
  void didUpdateWidget(covariant Earth2dGlobeView old) {
    super.didUpdateWidget(old);
    if (old.projectionId != widget.projectionId && _attached) {
      _bridge.setProjection(widget.projectionId);
    }
    if (old.spin != widget.spin && _attached) {
      _bridge.setSpin(widget.spin);
    }
    if (old.inspectEnabled != widget.inspectEnabled && _attached) {
      _bridge.setInspectEnabled(widget.inspectEnabled);
    }
    if (old.overlayOpen != widget.overlayOpen && _attached) {
      // Lock/unlock the globe's user camera input the instant an overlay box
      // opens/closes (parity with the Cesium view).
      _bridge.setInteractive(!widget.overlayOpen);
    }
    // Any slot / budget change re-resolves + re-pushes the affected frames.
    // _pushScalar always runs so the overlay scale stays current even before
    // attach (the chrome listens regardless of the canvas).
    final slotsChanged = old.overlayLayerId != widget.overlayLayerId ||
        old.annotationLayerId != widget.annotationLayerId ||
        old.animateLayerId != widget.animateLayerId ||
        old.reducedMotion != widget.reducedMotion ||
        old.hd != widget.hd ||
        old.stageVisible != widget.stageVisible;
    if (slotsChanged) {
      _pushScalar();
      _pushFlow();
      _pushPoint();
    }
    // Region change → re-focus (rotate) + reset the laser gate. A laser-only
    // change (toggle on an unchanged region) flips the laser WITHOUT re-rotating
    // (mirrors the Cesium view's laser-on-unchanged-region path).
    if (old.selectedRegionId != widget.selectedRegionId) {
      _pushRegion();
    } else if (old.regionLaserActive != widget.regionLaserActive && _attached) {
      _bridge.setLaser(widget.regionLaserActive);
    }
    if (old.myLocationLat != widget.myLocationLat ||
        old.myLocationLon != widget.myLocationLon) {
      _pushMyLocation();
    }
    if (old.stageVisible != widget.stageVisible && _attached) {
      widget.stageVisible ? _bridge.resume() : _bridge.suspend();
    }
  }

  @override
  void dispose() {
    // Clear our published scale (the Cesium view republishes on remount).
    EarthOverlayScaleChannel.active.value = null;
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The platform view exists only on web; the non-web branch is unreachable in
    // production (the Noop bridge never attaches) but keeps tests honest.
    if (!kIsWeb) {
      return const SizedBox.expand(
        key: Key('earth2d-stage-noweb'),
      );
    }
    return HtmlElementView(
      key: Key('earth2d-stage-$_viewType'),
      viewType: _viewType,
    );
  }
}

// lib/services/earth/earth_frame_resolver.dart
//
// RENDERER-AGNOSTIC FRAME RESOLUTION. Extracts the layer-id -> resolved-frame
// logic out of the Cesium View State so BOTH the Cesium globe and the future
// 2D canvas renderer can consume the SAME frames from one source of truth.
//
// This is a PLAIN Dart object (no Flutter State / BuildContext): it owns the
// governed grid + point-set storage, loads it once from the injected *Source
// seams (fail-closed per source), and resolves the scalar / flow / point frame
// for a given catalog layer id. The CALLER (a renderer view) decides WHEN to
// push the frame to its bridge, applies its own dedup/motion-budget gating, and
// owns the controller — the resolver never touches a renderer.
//
// Behavior parity: the resolve bodies here are byte-for-byte the same selection
// + budget + palette logic the Cesium State previously inlined, MINUS the
// controller push and the per-renderer dedup signatures (those stay in the
// view). Returns the same `.empty`/blank frame the old code returned when a
// layer is not of that render-kind or its grid has not loaded yet.

import 'package:xyz_earth/models/earth/earth_flow_field.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';
import 'package:xyz_earth/models/earth/earth_sphere_taxonomy.dart';
import 'package:xyz_earth/services/earth/earth_scalar_field_source.dart';
import 'package:xyz_earth/services/earth/earth_wind_field_source.dart';

/// Notified when a single source resolves during [EarthFrameResolver.load], so
/// the owning view can re-sync exactly the slot that gained data (mirrors the
/// per-source `setState` + `_syncXField()` the State previously did inline).
typedef EarthFrameResolverKindCallback = void Function();

class EarthFrameResolver {
  EarthFrameResolver({
    required EarthWindFieldSource windFieldSource,
    required EarthWindFieldSource oceanFieldSource,
    required EarthWindFieldSource wavesFieldSource,
    required Map<String, EarthScalarFieldSource> scalarSources,
    required Map<String, EarthPointSetSource> pointSources,
  })  : _windFieldSource = windFieldSource,
        _oceanFieldSource = oceanFieldSource,
        _wavesFieldSource = wavesFieldSource,
        _scalarSources = scalarSources,
        _pointSources = pointSources;

  final EarthWindFieldSource _windFieldSource;
  final EarthWindFieldSource _oceanFieldSource;
  final EarthWindFieldSource _wavesFieldSource;
  final Map<String, EarthScalarFieldSource> _scalarSources;
  final Map<String, EarthPointSetSource> _pointSources;

  /// The governed wind + ocean + waves grids, loaded once. Null until loaded
  /// (fail-closed: a load failure simply means no field for that layer — the
  /// globe is unaffected).
  EarthWindGrid? _windGrid;
  EarthWindGrid? _oceanGrid;
  EarthWindGrid? _wavesGrid;

  /// The governed scalar grids by catalog layer id, loaded once (fail-closed:
  /// a load failure simply means no heatmap for that layer; globe unaffected).
  final Map<String, EarthScalarGrid> _scalarGrids = {};

  /// The governed point sets by catalog layer id, loaded once (fail-closed).
  final Map<String, EarthPointSet> _pointSets = {};

  /// Read-only view of the loaded scalar grids (for renderer-side pre-warming).
  Map<String, EarthScalarGrid> get scalarGrids =>
      Map.unmodifiable(_scalarGrids);

  /// Item A — the loaded flow grids as PROBE channels for the click-to-inspect
  /// readout, independent of which one is animating. Null until loaded.
  EarthWindGrid? get windProbeGrid => _windGrid;
  EarthWindGrid? get oceanProbeGrid => _oceanGrid;
  EarthWindGrid? get wavesProbeGrid => _wavesGrid;

  /// PRELOAD every layer's data CONCURRENTLY so nothing waits behind the others.
  /// Each source is fail-closed independently (never throws, never affects the
  /// renderer). As each source resolves it stores the grid and fires the
  /// matching [onFlowLoaded]/[onScalarLoaded]/[onPointLoaded] callback so the
  /// caller can re-sync exactly that slot — identical to the previous
  /// per-source `setState` + `_syncXField()` interleave. [onComplete] fires once
  /// every source has settled (where the old code ran `_prewarmScalars`).
  Future<void> load({
    EarthFrameResolverKindCallback? onFlowLoaded,
    EarthFrameResolverKindCallback? onScalarLoaded,
    EarthFrameResolverKindCallback? onPointLoaded,
    EarthFrameResolverKindCallback? onComplete,
  }) async {
    await Future.wait<void>([
      (() async {
        try {
          final grid = await _windFieldSource.load();
          _windGrid = grid;
          onFlowLoaded?.call();
        } catch (_) {/* no wind field */}
      })(),
      (() async {
        try {
          final grid = await _oceanFieldSource.load();
          _oceanGrid = grid;
          onFlowLoaded?.call();
        } catch (_) {/* no ocean field */}
      })(),
      (() async {
        try {
          final grid = await _wavesFieldSource.load();
          _wavesGrid = grid;
          onFlowLoaded?.call();
        } catch (_) {/* no waves field */}
      })(),
      for (final entry in _scalarSources.entries)
        (() async {
          try {
            final grid = await entry.value.load();
            _scalarGrids[entry.key] = grid;
            onScalarLoaded?.call();
          } catch (_) {/* no heatmap for this scalar layer */}
        })(),
      for (final entry in _pointSources.entries)
        (() async {
          try {
            final ps = await entry.value.load();
            _pointSets[entry.key] = ps;
            onPointLoaded?.call();
          } catch (_) {/* no markers for this point layer */}
        })(),
    ]);
    onComplete?.call();
  }

  /// Resolves the SCALAR (heatmap) frame for [layerId]. Domain masking is
  /// enforced renderer-side; a non-scalar layer or an unloaded grid yields a
  /// blank ([EarthScalarFrame] with no grid → inactive). Mirrors the old
  /// `_syncScalarField` resolve body MINUS the controller push and the
  /// `activeOverlayScale` publish (renderer-side concerns the caller owns).
  ///
  /// [stageVisible]/[reducedMotion] fold into [EarthScalarFrame.active] exactly
  /// as before. The canonical per-layer palette ([EarthScalarLayerPalettes]) is
  /// applied so each scalar layer stays visually distinct.
  EarthScalarFrame scalarFrameFor(
    String layerId, {
    required bool stageVisible,
    required bool reducedMotion,
  }) {
    final isScalar = EarthAnimatedLayerIds.renderKindFor(layerId) ==
        EarthLayerRenderKind.scalar;
    final grid = isScalar ? _scalarGrids[layerId] : null;
    final active = grid != null && stageVisible && !reducedMotion;
    final paletteOverride = EarthScalarLayerPalettes.of(layerId);
    return EarthScalarFrame(
      grid: grid,
      active: active,
      paletteOverride: paletteOverride,
    );
  }

  /// Resolves the FLOW frame for [layerId] + motion budget. Wind grid attaches
  /// only when Wind is selected; ocean grid only when Ocean-currents is
  /// selected; any other layer yields [EarthFlowFieldFrame.empty]. Mirrors the
  /// old `_syncFlowField` resolve body MINUS the controller push.
  EarthFlowFieldFrame flowFrameFor(
    String layerId, {
    required bool stageVisible,
    required bool reducedMotion,
    required bool hd,
  }) {
    final windGrid = layerId == EarthFlowFieldLayerIds.wind ? _windGrid : null;
    final oceanGrid =
        layerId == EarthFlowFieldLayerIds.oceanCurrents ? _oceanGrid : null;
    final wavesGrid =
        layerId == EarthFlowFieldLayerIds.waves ? _wavesGrid : null;
    return EarthFlowFieldFrame.resolve(
      selectedLayerId: layerId,
      budget: EarthFlowFieldMotionBudget(
        stageVisible: stageVisible,
        reducedMotion: reducedMotion,
        dragging: false,
      ),
      windGrid: windGrid,
      oceanGrid: oceanGrid,
      wavesGrid: wavesGrid,
      hd: hd,
    );
  }

  /// Resolves the POINT frame for [layerId]. Domain masking is renderer-side; a
  /// non-point layer or an unloaded set yields a blank ([EarthPointFrame] with
  /// no set → inactive). Mirrors the old `_syncPointField` resolve body MINUS
  /// the controller push.
  EarthPointFrame pointFrameFor(
    String layerId, {
    required bool stageVisible,
    required bool reducedMotion,
  }) {
    // LOCKDOWN: a parked "coming soon" layer (satellites) NEVER builds a point
    // set or an orbital render — a stale /satellites/ URL or saved selection
    // degrades to no annotation, not a crash.
    if (EarthLayerSlotResolver.isComingSoon(layerId)) {
      return EarthPointFrame.empty;
    }
    final isPoint = EarthAnimatedLayerIds.renderKindFor(layerId) ==
        EarthLayerRenderKind.point;
    var ps = isPoint ? _pointSets[layerId] : null;
    // T1 (E): client-side per-layer display reskins (glaciers→light-blue 'ice'
    // dots, flights→triangle markers), independent of the data feed.
    if (ps != null) {
      final pal = EarthPointLayerDisplay.paletteFor(layerId);
      final shape = EarthPointLayerDisplay.shapeFor(layerId);
      final render = EarthPointLayerDisplay.renderModeFor(layerId);
      if (pal != null || shape != null || render != null) {
        ps = ps.withDisplay(
            paletteId: pal, markerShape: shape, renderMode: render);
      }
    }
    final active = ps != null && stageVisible && !reducedMotion;
    return EarthPointFrame(pointSet: ps, active: active);
  }
}

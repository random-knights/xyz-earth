import 'package:xyz_earth/models/earth/earth_flow_field.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';

/// READ-ONLY consumer bridge for the 2D-canvas renderer.
///
/// Mirrors the Cesium bridge's sync surface but targets the DISJOINT
/// `window.__earth2d` JS shim + `web/earth2d_*.js` renderers. It consumes the
/// SAME resolved frames the Cesium view consumes (selection + motion budget
/// already applied Dart-side) and never imports or edits an Agent-A file.
abstract interface class Earth2dBridge {
  /// Register the platform-view factory for this view's type. MUST be called
  /// SYNCHRONOUSLY before the `HtmlElementView` is first built (i.e. in
  /// initState), otherwise Flutter creates the platform view before the factory
  /// exists and throws `unregistered_view_type`. Idempotent. No-op on the VM.
  void registerView();

  /// Ask the JS shim to attach a canvas to the (now-mounted) host div. Call in a
  /// post-frame callback, AFTER [registerView] + the first build. Returns true
  /// once the renderer is live.
  Future<bool> attach(String hostId);

  /// Switch projection (one of Earth2dProjections.ids).
  void setProjection(String projectionId);

  /// Toggle the gentle auto-spin (the earth+ Rotate control). No-op on the VM.
  void setSpin(bool spin);

  /// Item A — Target Lat/Long: gate the click-to-inspect lat/long + flow
  /// readout. When false a globe click does nothing (no ring/readout). Default
  /// enabled. No-op on the VM.
  void setInspectEnabled(bool enabled);

  /// Item A — Target Lat/Long: the wind/current/wave PROBE grids the readout
  /// samples, independent of the active animate slot. [payloadJson] is
  /// `{"wind": grid|null, "ocean": grid|null, "waves": grid|null}` where each
  /// grid is an [EarthWindGrid.toBridgeJson]. Wind reads over land + ocean;
  /// current/waves are sampled over ocean only. No-op on the VM.
  void setProbeGrids(String payloadJson);

  /// Freeze/unfreeze USER camera input (wheel-zoom + drag) on the 2D globe while
  /// an earth+ overlay box is open, so scrolling inside the box can't zoom/rotate
  /// the globe underneath (parity with the Cesium bridge's
  /// setCameraInputsEnabled; the native-canvas wheel bypasses the Flutter freeze
  /// barrier). Programmatic rotate/spin/region focus stay live. No-op on the VM.
  void setInteractive(bool interactive);

  /// Subscribe to marker click snapshots. The JS shim emits a `window`
  /// `CustomEvent('earth2d-pick')` carrying the governed snapshot JSON (the same
  /// shape the Cesium path delivers via `earth-layer-pick`); the bridge forwards
  /// the raw payload string (empty = cleared) so the view can parse + publish it
  /// to the shared `EarthPickedSnapshot.notifier`. No-op on the VM stub (no
  /// markers to click). Pass null to unsubscribe.
  void setOnPick(void Function(String rawSnapshotJson)? onPick);

  void syncScalarField(EarthScalarFrame frame);
  void syncFlowField(EarthFlowFieldFrame frame);
  void syncPointField(EarthPointFrame frame);

  /// Focus a region: eased-rotate the 2D globe to the region centroid (when
  /// [rotate]) and remember the centroid for the region laser. Pass a null
  /// centroid (global / unknown region) to clear the focus — no rotate, no
  /// laser. lat/lon come from the Dart-owned `kEarth2dRegionCentroids`, never
  /// the Cesium shim. No-op on the VM stub.
  void setRegion({
    required String regionId,
    double? centroidLat,
    double? centroidLon,
    bool rotate = true,
  });

  /// Toggle the region laser WITHOUT moving the camera (the earth+ Laser
  /// control). The laser draws only for a non-global focused region.
  void setLaser(bool on);

  /// Place a neon my-location dot at [lat]/[lon] and (when [rotate]) eased-rotate
  /// to it. Pass null lat/lon to clear. No-op on the VM stub.
  void setMyLocation({double? lat, double? lon, bool rotate = false});

  /// Motion budget: stop/start the render loop when hidden.
  void suspend();
  void resume();

  void dispose();
}

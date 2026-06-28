import 'package:xyz_earth/models/earth/earth_flow_field.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';

import 'earth2d_bridge.dart';

/// Non-web (VM / tests) no-op bridge. The 2D renderer is browser-only; on the
/// VM every call is a safe no-op so widget tests can build the toggle.
Earth2dBridge createEarth2dBridge({required String viewType}) =>
    _NoopEarth2dBridge();

final class _NoopEarth2dBridge implements Earth2dBridge {
  @override
  void registerView() {}
  @override
  Future<bool> attach(String hostId) async => false;
  @override
  void setProjection(String projectionId) {}
  @override
  void setSpin(bool spin) {}
  @override
  void setInspectEnabled(bool enabled) {}
  @override
  void setProbeGrids(String payloadJson) {}
  @override
  void setInteractive(bool interactive) {}
  @override
  void setOnPick(void Function(String rawSnapshotJson)? onPick) {}
  @override
  void syncScalarField(EarthScalarFrame frame) {}
  @override
  void syncFlowField(EarthFlowFieldFrame frame) {}
  @override
  void syncPointField(EarthPointFrame frame) {}
  @override
  void setRegion({
    required String regionId,
    double? centroidLat,
    double? centroidLon,
    bool rotate = true,
  }) {}
  @override
  void setLaser(bool on) {}
  @override
  void setMyLocation({double? lat, double? lon, bool rotate = false}) {}
  @override
  void suspend() {}
  @override
  void resume() {}
  @override
  void dispose() {}
}

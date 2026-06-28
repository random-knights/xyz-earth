import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:xyz_earth/models/earth/earth_flow_field.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';
import 'package:web/web.dart' as web;

import 'earth2d_bridge.dart';

/// Browser bridge for the 2D-canvas renderer. Mirrors earth_cesium_bridge_web:
/// registers the platform-view factory once (the registry is GLOBAL and
/// re-registering a viewType throws), then drives the disjoint `window.__earth2d`
/// JS shim which attaches a `<canvas>` over the host div and runs the d3-geo +
/// Canvas2D renderers (web/earth2d_*.js). Every interop call is fail-closed.
Earth2dBridge createEarth2dBridge({required String viewType}) =>
    _Earth2dWebBridge(viewType);

@JS('window')
external JSObject get _window;

final class _Earth2dWebBridge implements Earth2dBridge {
  _Earth2dWebBridge(this._viewType);

  final String _viewType;

  // Per-viewType (NOT per-instance): a new bridge is built on every Earth
  // re-mount, and registerViewFactory throws on a duplicate viewType.
  static final Set<String> _registeredViewTypes = <String>{};

  /// Post-mount attach grace (mirrors earth_cesium_bridge_web attachViewer): the
  /// HtmlElementView host div must be CONNECTED to the document before the 2D
  /// shim can build its canvas into it. The post-frame attach routinely beats
  /// Flutter connecting the platform view, so poll a bounded number of frames.
  static const _attachWait = Duration(milliseconds: 100);
  static const _attachWaitAttempts = 30; // ~3s ceiling

  /// The `earth2d-pick` window listener (mirrors the Cesium bridge's
  /// `_pickListener`); null until [setOnPick] subscribes. Removed on null /
  /// dispose so a torn-down view leaves no dangling listener.
  JSFunction? _pickListener;

  String get _hostId => 'earth2d-host-$_viewType';

  JSObject? get _shim => _window.getProperty('__earth2d'.toJS) as JSObject?;

  @override
  void registerView() {
    if (_registeredViewTypes.contains(_viewType)) return;
    // Register SYNCHRONOUSLY (in initState) so the factory exists before Flutter
    // builds HtmlElementView(viewType: _viewType) — otherwise the platform view
    // is created with an unregistered type and throws. Mirrors the Cesium path,
    // which registers before attach.
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final host = web.HTMLDivElement()
        ..id = _hostId
        ..setAttribute('data-earth-renderer', 'earth2d');
      host.style
        ..width = '100%'
        ..height = '100%'
        ..backgroundColor = '#000000';
      return host as JSObject;
    });
    _registeredViewTypes.add(_viewType);
  }

  @override
  Future<bool> attach(String hostId) async {
    // Defensive: ensure the factory is registered even if the caller skipped the
    // initState registerView (idempotent).
    registerView();
    final shim = _shim;
    if (shim == null) return false;
    // Retry until the host div is connected and the shim builds its canvas.
    // Without this the single post-frame call hits the div before Flutter
    // connects it -> 'no-element' -> a permanently black 2D globe. Mirrors the
    // Cesium attachViewer poll: retry on 'no-element', bail on 'no-d3'/'error'.
    for (var attempt = 0; attempt < _attachWaitAttempts; attempt++) {
      String result;
      try {
        result =
            (shim.callMethod<JSString>('attach'.toJS, _hostId.toJS)).toDart;
      } catch (_) {
        return false; // interop threw — fail-closed
      }
      if (result == 'attached') return true;
      if (result == 'no-element') {
        // Host not connected to the DOM yet — wait a frame and retry.
        await Future<void>.delayed(_attachWait);
        continue;
      }
      // 'no-d3' / 'error' / unknown — a genuine failure (the shim only exists
      // once d3 has loaded, so 'no-d3' here means d3 truly failed). Bail.
      return false;
    }
    return false; // attach-timeout: host element never connected to the DOM
  }

  void _sync(String renderer, String payload) {
    try {
      _shim?.callMethod<JSAny?>(
        'sync'.toJS,
        _hostId.toJS,
        renderer.toJS,
        payload.toJS,
      );
    } catch (_) {}
  }

  @override
  void setProjection(String projectionId) {
    try {
      _shim?.callMethod<JSAny?>(
        'setProjection'.toJS,
        _hostId.toJS,
        projectionId.toJS,
      );
    } catch (_) {}
  }

  @override
  void setSpin(bool spin) {
    try {
      _shim?.callMethod<JSAny?>('setSpin'.toJS, _hostId.toJS, spin.toJS);
    } catch (_) {}
  }

  @override
  void setInspectEnabled(bool enabled) {
    try {
      _shim?.callMethod<JSAny?>(
          'setInspectEnabled'.toJS, _hostId.toJS, enabled.toJS);
    } catch (_) {}
  }

  @override
  void setProbeGrids(String payloadJson) {
    try {
      _shim?.callMethod<JSAny?>(
          'setProbeGrids'.toJS, _hostId.toJS, payloadJson.toJS);
    } catch (_) {}
  }

  @override
  void setInteractive(bool interactive) {
    try {
      _shim?.callMethod<JSAny?>(
        'setInteractive'.toJS,
        _hostId.toJS,
        interactive.toJS,
      );
    } catch (_) {}
  }

  @override
  void setOnPick(void Function(String rawSnapshotJson)? onPick) {
    // Always clear any prior subscription first (idempotent re-subscribe).
    final prior = _pickListener;
    if (prior != null) {
      try {
        web.window.removeEventListener('earth2d-pick', prior);
      } catch (_) {}
      _pickListener = null;
    }
    if (onPick == null) return;
    void handler(web.Event event) {
      try {
        final raw = (event as web.CustomEvent).detail.dartify();
        if (raw is String) onPick(raw);
      } catch (_) {/* ignore malformed pick events */}
    }

    final listener = handler.toJS;
    _pickListener = listener;
    try {
      web.window.addEventListener('earth2d-pick', listener);
    } catch (_) {
      _pickListener = null;
    }
  }

  @override
  void syncScalarField(EarthScalarFrame frame) =>
      _sync('scalar', jsonEncode(frame.toBridgeJson()));

  @override
  void syncFlowField(EarthFlowFieldFrame frame) {
    final grid = frame.flowGrid;
    _sync(
      'flow',
      jsonEncode({
        'animate': frame.animate,
        'kind': frame.flowKind ?? 'wind',
        'hd': frame.hd,
        if (grid != null) 'label': grid.label,
        if (grid != null) 'grid': grid.toBridgeJson(),
      }),
    );
  }

  @override
  void syncPointField(EarthPointFrame frame) =>
      _sync('point', jsonEncode(frame.toBridgeJson()));

  @override
  void setRegion({
    required String regionId,
    double? centroidLat,
    double? centroidLon,
    bool rotate = true,
  }) {
    try {
      final isGlobal =
          regionId == 'global' || centroidLat == null || centroidLon == null;
      _shim?.callMethod<JSAny?>(
        'setRegion'.toJS,
        _hostId.toJS,
        jsonEncode({
          'id': regionId,
          'global': isGlobal,
          if (!isGlobal) 'centroidLat': centroidLat,
          if (!isGlobal) 'centroidLon': centroidLon,
          'rotate': rotate,
        }).toJS,
      );
    } catch (_) {}
  }

  @override
  void setLaser(bool on) {
    try {
      _shim?.callMethod<JSAny?>('setLaser'.toJS, _hostId.toJS, on.toJS);
    } catch (_) {}
  }

  @override
  void setMyLocation({double? lat, double? lon, bool rotate = false}) {
    try {
      _shim?.callMethod<JSAny?>(
        'setMyLocation'.toJS,
        _hostId.toJS,
        (lat == null || lon == null)
            ? 'null'.toJS
            : jsonEncode({'lat': lat, 'lon': lon, 'rotate': rotate}).toJS,
      );
    } catch (_) {}
  }

  @override
  void suspend() {
    try {
      _shim?.callMethod<JSAny?>('suspend'.toJS, _hostId.toJS);
    } catch (_) {}
  }

  @override
  void resume() {
    try {
      _shim?.callMethod<JSAny?>('resume'.toJS, _hostId.toJS);
    } catch (_) {}
  }

  @override
  void dispose() {
    setOnPick(null);
    try {
      _shim?.callMethod<JSAny?>('detach'.toJS, _hostId.toJS);
    } catch (_) {}
  }
}

// Conditional bridge factory, mirroring earth_cesium_bridge_factory.dart. On web
// (dart.library.js_interop) the real canvas bridge is used; everywhere else the
// no-op stub. No secrets cross this boundary — the 2D renderer reads only the
// already-governed frames.
export 'earth2d_bridge_stub.dart'
    if (dart.library.js_interop) 'earth2d_bridge_web.dart';

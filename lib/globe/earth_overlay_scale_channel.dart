import 'package:flutter/foundation.dart';

import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';

/// Standalone replacement for the single static notifier the 2D globe view used
/// to read off `EarthCesiumGlobeView`. In the private app that class also hosted
/// the Cesium 3D renderer; the keyless viewer is `earth2d`-only, so we keep just
/// the published overlay-scale channel and drop the entire Cesium subtree (which
/// also dropped the `envied` secrets file it transitively imported).
///
/// The active scalar OVERLAY's value scale for the globe scale-bar / value key;
/// null when no scalar overlay is rendering. Updated by the mounted globe view
/// on every scalar sync (value-equal, so it only fires on a real change).
abstract final class EarthOverlayScaleChannel {
  static final ValueNotifier<EarthOverlayScale?> active =
      ValueNotifier<EarthOverlayScale?>(null);
}

/// Feature flag for the 2D-canvas Earth renderer (north-star track).
///
/// Default OFF. While false, [EarthRendererToggle] renders the existing Cesium
/// view UNCHANGED — the lane is fully file-disjoint and has zero runtime effect.
/// Flip locally for device-pass via `--dart-define=EARTH2D_RENDERER=true`;
/// promote to a Remote Config key for runtime owner control at productionization.
library;

const bool kEarth2dRendererEnabled =
    bool.fromEnvironment('EARTH2D_RENDERER', defaultValue: false);

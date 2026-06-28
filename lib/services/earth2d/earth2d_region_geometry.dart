// lib/services/earth2d/earth2d_region_geometry.dart
//
// Region focus geometry (centroids) for the 2D-canvas renderer.
//
// The 2D globe rotates to a region + draws a region laser on the SAME
// `selectedRegionId` the Cesium view consumes. The Cesium path keeps its region
// centroids in the web/index.html shim (REGION_CENTROIDS); per the lane rules we
// do NOT copy that JS array out of the shim — instead this Dart-owned model is
// the source of truth, and the centroid lat/lon is passed to the 2D shim through
// the bridge (Earth2dBridge.setRegion). The values are common-knowledge
// continent/macro-region centres and are kept parity-matched with the Cesium
// REGION_CENTROIDS so selecting a region focuses the SAME place on both
// renderers.
//
// Ideally this lives on the shared `EarthRegion` model, but that is outside the
// earth2d lane's edit boundary; this earth2d-owned map is the pragmatic seam.
// `global` (and any unknown id) has no centroid → no rotate, no laser.

/// A region focus centroid in degrees.
class Earth2dRegionCentroid {
  const Earth2dRegionCentroid(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Region centroids keyed by `EarthRegionIds` value (kebab-case). Parity-matched
/// with the Cesium shim's REGION_CENTROIDS. `global` is intentionally absent.
const Map<String, Earth2dRegionCentroid> kEarth2dRegionCentroids = {
  'north-america': Earth2dRegionCentroid(40, -100),
  'south-america': Earth2dRegionCentroid(-15, -60),
  'europe': Earth2dRegionCentroid(50, 10),
  'africa': Earth2dRegionCentroid(2, 20),
  'middle-east': Earth2dRegionCentroid(25, 45),
  'asia': Earth2dRegionCentroid(30, 100),
  'oceania': Earth2dRegionCentroid(-25, 135),
  'arctic': Earth2dRegionCentroid(75, 0),
  'antarctic': Earth2dRegionCentroid(-75, 0),
};

/// The centroid for [regionId], or null for `global` / unknown (no focus).
Earth2dRegionCentroid? earth2dRegionCentroid(String? regionId) =>
    regionId == null ? null : kEarth2dRegionCentroids[regionId];

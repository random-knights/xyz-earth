// Nullschool-parity slice 4 — filter taxonomy contracts.
//
// EarthProjection     : projection enum; ortho-only until slice 3 compositing.
// EarthSphere         : the 6 Earth spheres that scope the
//                       Animate/Overlay/Annotation slot menus. A sphere does NOT
//                       itself render — it filters available options.
// EarthLayerSlot      : the three renderer slots (animate/overlay/annotation).
// EarthLayerSlotResolver: renderKind→slot, backed by EarthAnimatedLayerIds.
// EarthGlobeSlotDescriptor: multi-slot bridge descriptor accepted by the
//                       globe/renderer bridge. Slice 4 fires ONE slot (single-
//                       active via singleActiveLayerId). Slice 3 removes that
//                       getter and renders all slots simultaneously.

import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';

// ── Projection ───────────────────────────────────────────────────────────────

/// Globe projection. Orthographic is the only built option; additional
/// projections (stereographic, equirectangular) are future Pro scope.
enum EarthProjection { orthographic }

extension EarthProjectionLabel on EarthProjection {
  String get label => 'Orthographic';
}

/// One selectable 2D-globe projection preset. Ids are in LOCK-STEP with
/// web/earth2d_projections.js (the d3-geo registry the 2D renderer injects).
class EarthGlobeProjection {
  const EarthGlobeProjection(this.id, this.label, {this.globe = true});

  /// Matches an id in Earth2dProjections.ids (web/earth2d_projections.js).
  final String id;
  final String label;

  /// Limb/disc projection (orthographic-like) vs a full-frame world map.
  final bool globe;
}

/// The 2D-renderer projections, split by where they belong (owner directive):
/// the EARTH-VIEW globe offers the globe-style pair (orthographic default +
/// stereographic, which fills the viewport like nullschool); every OTHER preset
/// drives the DATA-VIEW region locator. 3D (Cesium) ignores the choice — it is
/// always a perspective globe. Ids are lock-step with web/earth2d_projections.js.
abstract final class EarthGlobeProjections {
  /// Default Earth-View globe projection.
  static const String defaultId = 'orthographic';

  /// Default Data-View locator projection — a FLAT world map (owner directive:
  /// the GLOBE projections orthographic/stereographic are Earth-View ONLY; the
  /// Data View uses flat projections). Natural Earth is the prettiest default.
  static const String defaultLocatorId = 'natural-earth';

  /// Earth-View 2D globe projections (globe-style only).
  static const List<EarthGlobeProjection> earthView = [
    EarthGlobeProjection('orthographic', 'Orthographic'),
    EarthGlobeProjection('stereographic', 'Stereographic'),
  ];

  /// Data-View region-locator projections — FLAT world maps only (owner: the
  /// globe/disc projections are Earth-View-only; the Data View shows the same
  /// base-map quality in flat projections, no overlays/animations/annotations).
  static const List<EarthGlobeProjection> locator = [
    EarthGlobeProjection('natural-earth', 'Natural Earth', globe: false),
    EarthGlobeProjection('equirectangular', 'Equirectangular', globe: false),
    EarthGlobeProjection('mercator', 'Mercator', globe: false),
    EarthGlobeProjection('conic-conformal', 'Conic Conformal', globe: false),
  ];

  static const List<EarthGlobeProjection> all = [...earthView, ...locator];

  static bool isValid(String id) => all.any((p) => p.id == id);
  static bool isEarthViewId(String id) => earthView.any((p) => p.id == id);
  static bool isLocatorId(String id) => locator.any((p) => p.id == id);

  /// True for a limb/disc (globe-style) projection — the locator renders these
  /// as a round globe disc in a square box, the rest as a flat 2:1 world map.
  static bool isGlobeId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first).globe;

  static String labelFor(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first).label;
}

// ── Sphere ───────────────────────────────────────────────────────────────────

/// The 6 classical Earth spheres. A sphere scopes which layer ids appear in the
/// Animate/Overlay/Annotation slot menus. A sphere does NOT itself render, and
/// it NEVER moves the health score (the gauge always shows the region composite).
///
/// (Formerly EarthNullschoolMode — 5 IA groups + Space. Old URL slugs are
/// aliased in earth_tab.dart's _sphereFromSlug: ocean→hydrosphere,
/// human-footprint→geosphere, space→anthroposphere.)
enum EarthSphere {
  atmosphere,
  hydrosphere,
  cryosphere,
  geosphere,
  biosphere,
  anthroposphere,
}

extension EarthSphereDetails on EarthSphere {
  String get label => switch (this) {
        EarthSphere.atmosphere => 'Atmosphere',
        EarthSphere.hydrosphere => 'Hydrosphere',
        EarthSphere.cryosphere => 'Cryosphere',
        EarthSphere.geosphere => 'Geosphere',
        EarthSphere.biosphere => 'Biosphere',
        EarthSphere.anthroposphere => 'Anthroposphere',
      };

  /// A one-line, plain-English description of what the sphere covers — shown
  /// AFTER the sphere name + a colon in the Category block at the top of the
  /// Score Summary + Data View (e.g. `Atmosphere: <description>`).
  String get description => switch (this) {
        EarthSphere.atmosphere =>
          'air and weather, covering wind, air quality, storms, and aircraft.',
        EarthSphere.hydrosphere =>
          'oceans and freshwater, covering currents, waves, sea-surface '
              'temperature, and vessels.',
        EarthSphere.cryosphere =>
          'ice and snow, covering glaciers, sea ice, and mass-balance trends.',
        EarthSphere.geosphere =>
          'land and terrain, covering forests, tree cover, soil, and wildfire.',
        EarthSphere.biosphere =>
          'living systems, covering biodiversity, threatened species, and '
              'protected areas.',
        EarthSphere.anthroposphere =>
          'the human footprint, covering cities, industry, energy, agriculture, '
              'and satellites.',
      };

  /// The sphere a HEALTH-SCORE SIGNAL (domain id) belongs to — the SINGLE SOURCE
  /// for the signal→sphere mapping reused by the filter legend, the Score
  /// Summary "Health Signals", and the Data View "How score is derived". Accepts
  /// the score's domain ids (air, land-cover, ocean[-acidification], cryosphere,
  /// biodiversity, conservation, human, fire) + a few aliases.
  static EarthSphere forSignal(String signalId) => switch (signalId) {
        'air' || 'air-quality' || 'particulates' || 'chemistry' =>
          EarthSphere.atmosphere,
        'ocean' ||
        'ocean-warming' ||
        'ocean-acidification' ||
        'sst' ||
        'ssta' =>
          EarthSphere.hydrosphere,
        'cryosphere' || 'glaciers' => EarthSphere.cryosphere,
        'land-cover' ||
        'forest' ||
        'tree-time' ||
        'fire' ||
        'wildfire' ||
        'wildfires' =>
          EarthSphere.geosphere,
        'biodiversity' || 'conservation' || 'protected-areas' =>
          EarthSphere.biosphere,
        'human' || 'human-encroachment' => EarthSphere.anthroposphere,
        _ => EarthSphere.atmosphere,
      };

  /// Layer ids that belong to this sphere (scopes the slot menus). Display-only:
  /// membership decides which layers render ENABLED vs disabled in the panel; it
  /// never moves the health score. Withheld scalars (protected-areas, tree-time)
  /// and points (biodiversity-habitat) stay in their sphere for [forLayer] but
  /// never surface in the picker (see EarthLayerSlotResolver withheld sets).
  Set<String> get layerIds => switch (this) {
        EarthSphere.atmosphere => const {
            'wind', 'air-quality', 'particulates', 'chemistry',
            'cape', 'dust-aod', 'misery-index',
            // Ambient airborne-aircraft positions (mobility lane).
            'flights',
          },
        EarthSphere.hydrosphere => const {
            'ocean-currents', 'waves', 'sst', 'ssta', 'baa',
            // Ambient vessel activity (mobility lane).
            'boats',
          },
        EarthSphere.cryosphere => const {'glaciers'},
        EarthSphere.geosphere => const {
            'forest',
            'tree-time',
            'wildfires',
          },
        EarthSphere.biosphere => const {
            // Wikidata/WDPA protected-area POINT vertical + the `protected-areas`
            // scalar (withheld from the overlay picker) + IUCN/GBIF threatened
            // species + the biodiversity-habitat aggregate (folded into Protected
            // Areas, withheld from the annotation picker).
            'protected-areas',
            'protected-areas-points',
            'species-threatened',
            'biodiversity-habitat',
          },
        EarthSphere.anthroposphere => const {
            'human-encroachment',
            'carbon-offset-projects',
            'businesses-footprint',
            'datacenters',
            'industrial-sites',
            // WRI power plants + Maus mining/extraction sites.
            'power-plants',
            'extraction-sites',
            // Ambient satellite orbit bands + named satellites (CelesTrak TLEs,
            // client-propagated).
            'satellites',
          },
      };

  /// The sphere that best fits a given layer id. Falls back to [atmosphere].
  static EarthSphere forLayer(String layerId) {
    for (final sphere in EarthSphere.values) {
      if (sphere.layerIds.contains(layerId)) return sphere;
    }
    return EarthSphere.atmosphere;
  }
}

// ── Slot ─────────────────────────────────────────────────────────────────────

/// The three renderer slots surfaced in the nullschool filter panel.
enum EarthLayerSlot { animate, overlay, annotation }

extension EarthLayerSlotLabel on EarthLayerSlot {
  String get label => switch (this) {
        EarthLayerSlot.animate => 'Animate',
        EarthLayerSlot.overlay => 'Overlay',
        EarthLayerSlot.annotation => 'Annotation',
      };
}

// ── Slot resolver ─────────────────────────────────────────────────────────────

/// Maps a layer id to the renderer slot it belongs to (via renderKind).
abstract final class EarthLayerSlotResolver {
  static EarthLayerSlot? slotFor(String layerId) {
    final kind = EarthAnimatedLayerIds.renderKindFor(layerId);
    return switch (kind) {
      EarthLayerRenderKind.flow => EarthLayerSlot.animate,
      EarthLayerRenderKind.scalar => EarthLayerSlot.overlay,
      EarthLayerRenderKind.point => EarthLayerSlot.annotation,
      null => null,
    };
  }

  /// Ordered layer ids for a given (mode, slot) pair — the layers ENABLED for
  /// that mode. Alphabetical within the mode's layer set.
  static List<String> layerIdsForModeSlot(
    EarthSphere sphere,
    EarthLayerSlot slot,
  ) {
    final ids = sphere.layerIds
        .where((id) => slotFor(id) == slot)
        .toList()
      ..sort();
    return ids;
  }

  /// Overlay ids WITHHELD from the earth+ picker (data-honesty, BATCH A #9):
  /// scalar layers that would render as a dishonest blob until real, properly-
  /// scaled grids back them. `tree-time` is DERIVED from a representative CO₂
  /// field (its values span only ~82–89 on a 0–100 scale → a near-uniform wash);
  /// `protected-areas` is a representative WDPA-style coverage model (isLive
  /// false; values 4–55 on a 0–100 scale → washed out). Per the owner's rule —
  /// "never render a synthetic blob as a data overlay" — they stay out of the
  /// selectable overlay list. They REMAIN in [EarthAnimatedLayerIds.scalar]
  /// (renderKind / health-score bindings) and in the Data View Layers roster;
  /// only the overlay picker hides them. Drop an id from this set the moment a
  /// real grid (isLive) ships for it.
  static const Set<String> overlayPickerWithheld = {
    'protected-areas',
    'tree-time',
  };

  /// Item 5: point layers WITHHELD from the annotation picker. `biodiversity-
  /// habitat` is no longer a standalone selectable dot layer — its representative
  /// richness points are folded INTO the Protected Areas annotation as larger,
  /// alt-colour dots (build-time merge). It REMAINS in [EarthAnimatedLayerIds.
  /// point] (renderKind / health-score / governance bindings untouched); only the
  /// annotation picker hides it.
  static const Set<String> annotationPickerWithheld = {
    'biodiversity-habitat',
  };

  /// LOCKDOWN: layers PARKED as "coming soon" — still shown in the picker but as
  /// a DISABLED, non-selectable chip, HARD-GUARDED out of the render pipeline
  /// (no point set / no orbital render), and stripped from saved + URL state.
  /// `satellites`' orbital renderer is parked for a post-launch rebuild (it could
  /// throw + white-screen on reload). It REMAINS in [EarthAnimatedLayerIds.point]
  /// + the registry/governance/Data-View bindings; only selection + render are
  /// disabled here. Drop an id from this set when its renderer is relaunched.
  static const Set<String> comingSoon = {
    'satellites',
  };

  static bool isComingSoon(String layerId) => comingSoon.contains(layerId);

  /// ALL built layer ids for a slot, mode-independent (the slot's render-kind
  /// set). The filter panel shows all of these so the user sees every available
  /// filter without hunting through modes; ones not valid for the active mode
  /// render DISABLED (see [layerIdsForModeSlot] for the enabled subset). The
  /// overlay slot additionally drops [overlayPickerWithheld] (synthetic blobs).
  static List<String> allLayerIdsForSlot(EarthLayerSlot slot) {
    final set = switch (slot) {
      EarthLayerSlot.animate => EarthAnimatedLayerIds.flow,
      EarthLayerSlot.overlay => EarthAnimatedLayerIds.scalar,
      EarthLayerSlot.annotation => EarthAnimatedLayerIds.point,
    };
    final ids = set.toList()..sort();
    if (slot == EarthLayerSlot.overlay) {
      ids.removeWhere(overlayPickerWithheld.contains);
    }
    if (slot == EarthLayerSlot.annotation) {
      ids.removeWhere(annotationPickerWithheld.contains);
    }
    return ids;
  }
}

// ── Multi-slot bridge descriptor ─────────────────────────────────────────────

/// Describes which layer is active in each renderer slot. Accepted by the
/// globe bridge so slice 3 (simultaneous compositing) is a small follow-on:
/// slice 3 removes [singleActiveLayerId] and fires all non-null slots at once.
///
/// Slice 4 single-active contract: only ONE slot is non-null at a time;
/// [singleActiveLayerId] returns the first non-null (animate > overlay >
/// annotation). The bridge uses this as the single active layer id.
final class EarthGlobeSlotDescriptor {
  const EarthGlobeSlotDescriptor({
    this.animateLayerId,
    this.overlayLayerId,
    this.annotationLayerId,
  });

  static const empty = EarthGlobeSlotDescriptor();

  /// Flow slot — wind or ocean-currents.
  final String? animateLayerId;

  /// Scalar overlay slot — one of the 7 scalar layers.
  final String? overlayLayerId;

  /// Point annotation slot — one of the 4 point layers.
  final String? annotationLayerId;

  /// Slice-4 single-active layer: first non-null slot wins (animate > overlay >
  /// annotation). Returns null when all slots are off.
  /// Slice 3 removes this getter; the bridge renders all slots simultaneously.
  String? get singleActiveLayerId =>
      animateLayerId ?? overlayLayerId ?? annotationLayerId;

  bool get isEmpty =>
      animateLayerId == null &&
      overlayLayerId == null &&
      annotationLayerId == null;

  EarthGlobeSlotDescriptor withAnimate(String? id) =>
      EarthGlobeSlotDescriptor(
        animateLayerId: id,
        overlayLayerId: overlayLayerId,
        annotationLayerId: annotationLayerId,
      );

  EarthGlobeSlotDescriptor withOverlay(String? id) =>
      EarthGlobeSlotDescriptor(
        animateLayerId: animateLayerId,
        overlayLayerId: id,
        annotationLayerId: annotationLayerId,
      );

  EarthGlobeSlotDescriptor withAnnotation(String? id) =>
      EarthGlobeSlotDescriptor(
        animateLayerId: animateLayerId,
        overlayLayerId: overlayLayerId,
        annotationLayerId: id,
      );

  @override
  bool operator ==(Object other) =>
      other is EarthGlobeSlotDescriptor &&
      other.animateLayerId == animateLayerId &&
      other.overlayLayerId == overlayLayerId &&
      other.annotationLayerId == annotationLayerId;

  @override
  int get hashCode =>
      Object.hash(animateLayerId, overlayLayerId, annotationLayerId);
}

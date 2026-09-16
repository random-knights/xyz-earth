@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xyz_earth/models/earth/earth_scalar_grid.dart';

/// Parity guard for the globe layer catalog.
///
/// The private app (random-knights/ruok) is the upstream source of truth for the
/// globe layer set; this package mirrors it. Before this guard existed the
/// mirror could drift SILENTLY - a layer (environmental-nonprofits) landed in
/// the app and this package's catalog + bundled assets simply fell behind, with
/// nothing catching it. The health score already had a drift guard
/// (test/score_asset_drift_guard_test.dart); the layer catalog had none.
///
/// Mechanism (justified): a checked-in manifest, earth-layer-catalog.manifest.json,
/// pins the app's layer registry. This package is PUBLIC and KEYLESS and cannot
/// reach the private app at CI time, so a live read of the app registry is not
/// available - the manifest is a pinned mirror, kept current by the same manual
/// sync as the score guard. The guard makes the mirror enforceable: it fails
/// when the app's layer set (the manifest) contains a layer this package does
/// not represent, and it fails if the package represents a layer the manifest
/// does not list. So the moment someone records an app addition in the manifest,
/// CI stays red until the package either ships the layer or explicitly defers it
/// in pendingPortFromApp.
///
/// Proven both directions:
///  - remove a layer from represented -> the package still has it -> RED.
///  - add an app layer to appRegistry without representing/deferring it -> RED.
void main() {
  final file = File('earth-layer-catalog.manifest.json');
  final manifest =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  List<String> ids(Object? v) =>
      (v as List).cast<String>().toList()..sort();

  Set<String> represented() {
    final r = manifest['represented'] as Map<String, dynamic>;
    return {...ids(r['flow']), ...ids(r['scalar']), ...ids(r['point'])};
  }

  test('manifest exists and is a real catalog manifest', () {
    expect(file.existsSync(), isTrue,
        reason: 'earth-layer-catalog.manifest.json is missing');
    expect(manifest['represented'], isA<Map<String, dynamic>>());
    expect(manifest['appRegistry'], isA<List<dynamic>>());
  });

  test('represented set exactly equals the package layer registry per slot', () {
    final r = manifest['represented'] as Map<String, dynamic>;
    expect(ids(r['flow']).toSet(), EarthAnimatedLayerIds.flow,
        reason: 'manifest.represented.flow drifted from EarthAnimatedLayerIds.flow');
    expect(ids(r['scalar']).toSet(), EarthAnimatedLayerIds.scalar,
        reason: 'manifest.represented.scalar drifted from EarthAnimatedLayerIds.scalar');
    expect(ids(r['point']).toSet(), EarthAnimatedLayerIds.point,
        reason: 'manifest.represented.point drifted from EarthAnimatedLayerIds.point '
            '- add the layer to the manifest AND ship its asset/catalog together, '
            'or remove it from both');
    // The union is the whole registry: no represented layer is unbuilt, and no
    // built layer is unlisted. This is the assertion the prove-it edit trips.
    expect(represented(), EarthAnimatedLayerIds.all,
        reason: 'represented layer set != EarthAnimatedLayerIds.all');
  });

  test('every app-registry layer is either represented or explicitly deferred',
      () {
    final app = ids(manifest['appRegistry']).toSet();
    final pending = ((manifest['pendingPortFromApp'] as List)
            .cast<Map<String, dynamic>>())
        .map((e) => e['id'] as String)
        .toSet();

    // The mirror is complete: appRegistry == represented + pending. Recording a
    // new app layer in appRegistry (a sync) forces it into represented (ship it)
    // or pendingPortFromApp (defer it) - it cannot vanish.
    expect(represented().union(pending), app,
        reason: 'appRegistry is not fully accounted for: every app layer must be '
            'in represented (shipped here) or pendingPortFromApp (deferred with '
            'a reason). Unaccounted: ${app.difference(represented().union(pending))}');

    // Deferred layers must be genuinely absent from the package - so a stale
    // deferral (a layer that HAS since been ported) fails and must be cleaned up.
    for (final id in pending) {
      expect(EarthAnimatedLayerIds.all.contains(id), isFalse,
          reason: 'pendingPortFromApp lists "$id" but the package now represents '
              'it - move it into represented and drop it from pendingPortFromApp');
    }
    // Deferred and represented are disjoint.
    expect(represented().intersection(pending), isEmpty,
        reason: 'a layer is both represented and pendingPortFromApp');
  });

  /// The sync METADATA is part of the mirror. A manifest can be in perfect
  /// parity and still be untrustworthy if nobody can tell when it was last
  /// checked, or against which app commit. Added 2026-09-16 after a re-sync
  /// found the layer sets identical but the recorded date two months old and a
  /// deferral reason that was simply wrong.
  group('the sync record is usable', () {
    test('syncedFromAppAt is an ISO date and syncedFromAppSha is a real sha',
        () {
      final at = manifest['syncedFromAppAt'];
      expect(at, isA<String>(),
          reason: 'syncedFromAppAt is missing: the mirror cannot say when it '
              'was last checked');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(at as String), isTrue,
          reason: 'syncedFromAppAt must be YYYY-MM-DD, got "$at"');

      final sha = manifest['syncedFromAppSha'];
      expect(sha, isA<String>(),
          reason: 'syncedFromAppSha is missing: a date alone does not say '
              'WHICH app registry was mirrored');
      expect(RegExp(r'^[0-9a-f]{7,40}$').hasMatch(sha as String), isTrue,
          reason: 'syncedFromAppSha must be a hex commit sha, got "$sha"');
    });

    test('appRegistry is sorted and free of duplicates', () {
      final raw = (manifest['appRegistry'] as List).cast<String>();
      expect(raw.toSet().length, raw.length,
          reason: 'appRegistry lists a layer id twice');
      final sorted = [...raw]..sort();
      expect(raw, sorted,
          reason: 'appRegistry must stay sorted so a hand sync produces a '
              'readable diff instead of a shuffled list');
    });

    test('every deferral carries a reason and a trackedSince date', () {
      final pending =
          (manifest['pendingPortFromApp'] as List).cast<Map<String, dynamic>>();
      for (final entry in pending) {
        final id = entry['id'];
        expect(id, isA<String>());
        final reason = entry['reason'];
        expect(reason, isA<String>(),
            reason: 'pendingPortFromApp entry "$id" has no reason, so the gap '
                'is silent again');
        expect((reason as String).trim().length, greaterThan(40),
            reason: 'pendingPortFromApp entry "$id" needs a reason someone can '
                'act on, not a placeholder');
        final since = entry['trackedSince'];
        expect(since, isA<String>(),
            reason: 'pendingPortFromApp entry "$id" has no trackedSince, so '
                'nobody can see how long it has been deferred');
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(since as String),
            isTrue,
            reason: 'trackedSince for "$id" must be YYYY-MM-DD, got "$since"');
      }
    });
  });

  test('every bundled point asset declared in the manifest exists on disk', () {
    final assets = manifest['bundledPointAssets'] as Map<String, dynamic>;
    for (final entry in assets.entries) {
      if (entry.key.startsWith('_')) continue; // skip _note
      final layerId = entry.key;
      final path = entry.value as String;
      expect(EarthAnimatedLayerIds.point.contains(layerId), isTrue,
          reason: 'bundledPointAssets lists "$layerId" which is not a point layer');
      expect(File(path).existsSync(), isTrue,
          reason: 'bundled point asset for "$layerId" is missing: $path');
    }
    // The layer this PR added must be present with its bundled representative.
    expect(assets.containsKey('environmental-nonprofits'), isTrue);
    expect(
        File(assets['environmental-nonprofits'] as String).existsSync(), isTrue);
  });
}

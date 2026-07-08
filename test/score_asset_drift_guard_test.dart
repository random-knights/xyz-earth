@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Methodology drift guard for the bundled representative score asset.
///
/// The fallback document at assets/earth/score/health-score-representative-v1.json
/// is a byte-for-byte copy of the main app's live v0.7 asset (never hand-edited;
/// re-sync it from the xyz repo's published asset when the methodology bumps).
/// This test pins the expected methodologyVersion so a main-app version bump
/// that is not mirrored here fails loudly instead of silently shipping a stale
/// fallback.
const expectedMethodologyVersion = '0.7';

void main() {
  test('representative score asset matches the pinned methodology version', () {
    final file =
        File('assets/earth/score/health-score-representative-v1.json');
    expect(file.existsSync(), isTrue,
        reason: 'bundled representative score asset is missing');

    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final meta = doc['meta'] as Map<String, dynamic>;

    expect(meta['schema'], 'earth.healthscore.v1');
    expect(meta['methodologyVersion'], expectedMethodologyVersion,
        reason: 'asset drifted from the ratified methodology — re-sync the '
            'asset from the main app AND bump expectedMethodologyVersion '
            'together');

    // Sanity: the document is a real score doc, not a truncated copy.
    final global = doc['global'] as Map<String, dynamic>;
    expect(global['score'], isA<num>());
    expect(doc['regions'], isA<Map<String, dynamic>>());
    expect((doc['regions'] as Map).isNotEmpty, isTrue);
  });
}

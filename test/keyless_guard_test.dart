@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Provable-keyless gate. Scans the source tree (lib/, web/, pubspec) for the
/// markers that would mean a secret, an auth dependency, or a private package
/// crept back in. This test is the standing guard behind the repo's promise:
/// the app builds and runs with NO keys, NO auth, NO Firebase SDK, NO private
/// deps. If you must add a network read, it is a plain public HTTPS GET.
void main() {
  // Substrings that must never appear in tracked source.
  const forbidden = <String>[
    'apiKey',
    'api_key',
    'firebaseConfig',
    'package:firebase_core',
    'package:firebase_auth',
    'package:cloud_functions',
    'package:firebase_app_check',
    'package:google_sign_in',
    'package:envied',
    'service_account',
    'serviceAccount',
    'BEGIN PRIVATE KEY',
    'git@github-', // private git SSH deps
    'AIza', // Google API key prefix
  ];

  // Files/dirs that legitimately discuss these tokens (this test + docs).
  bool isSelfOrDoc(String path) =>
      path.endsWith('keyless_guard_test.dart') ||
      path.toLowerCase().endsWith('.md');

  const textExt = {'.dart', '.yaml', '.yml', '.json', '.html', '.js', '.md'};
  bool isText(String path) =>
      textExt.any((e) => path.toLowerCase().endsWith(e));

  Iterable<File> tracked() sync* {
    for (final dir in ['lib', 'web', 'test']) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final e in d.listSync(recursive: true)) {
        if (e is File && isText(e.path)) yield e;
      }
    }
    final p = File('pubspec.yaml');
    if (p.existsSync()) yield p;
  }

  test('no secrets, auth SDKs, or private deps in the tree', () {
    final hits = <String>[];
    for (final f in tracked()) {
      if (isSelfOrDoc(f.path)) continue;
      // Skip minified vendor bundles (d3/topojson) — large + public domain.
      if (f.path.contains('vendor')) continue;
      final text = f.readAsStringSync();
      for (final needle in forbidden) {
        if (text.contains(needle)) {
          hits.add('${f.path}: "$needle"');
        }
      }
    }
    expect(hits, isEmpty, reason: 'Forbidden tokens found:\n${hits.join('\n')}');
  });

  test('pubspec has zero git/private dependencies', () {
    final text = File('pubspec.yaml').readAsStringSync();
    expect(text.contains('git:'), isFalse, reason: 'no git: deps allowed');
    expect(text.contains('rk_'), isFalse, reason: 'no private rk_ deps allowed');
    expect(text.contains('firebase'), isFalse,
        reason: 'no firebase deps allowed');
  });
}

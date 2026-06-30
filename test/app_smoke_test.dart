import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xyz_earth/models/earth/earth_health_history.dart';
import 'package:xyz_earth/models/earth/earth_live_health_score.dart';
import 'package:xyz_earth/services/earth/earth_live_health_score_source.dart';
import 'package:xyz_earth/widgets/earth/earth_health_history_row.dart';
import 'package:xyz_earth/widgets/earth/earth_score_rings.dart';

/// Chrome-level smoke tests. These pump the score/history widgets in isolation
/// rather than the whole app: mounting the live globe would fire its async
/// source loads (network → bundled fallback) and leak pending timers that make a
/// settle hang. The keyless-boot proof (the representative parses + renders) is
/// covered directly below.
void main() {
  testWidgets('Global score ring renders the score + label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: EarthGlobalScoreRing(score: 72.0, label: 'Global'),
          ),
        ),
      ),
    );
    expect(find.text('72.0'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);
  });

  testWidgets('Health-history row builds from injected (offline) data', (
    tester,
  ) async {
    // Inject history so the row never touches the network.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EarthHealthHistoryRow(history: EarthHealthHistory.empty),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EarthHealthHistoryRow), findsOneWidget);
    expect(find.text('Health history'), findsOneWidget);
  });

  test('Bundled representative health score parses (keyless cold boot)', () async {
    // The representative is what an offline/keyless cold boot displays — it must
    // parse and yield a sane global score with isLive == false.
    TestWidgetsFlutterBinding.ensureInitialized();
    final EarthLiveHealthScore doc =
        await const StaticAssetHealthScoreSource().load();
    expect(doc.isLive, isFalse);
    expect(doc.global.score, inInclusiveRange(0, 100));
  });
}

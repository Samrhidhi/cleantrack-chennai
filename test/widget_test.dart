// Widget tests for CleanTrack Chennai.
// Run with:  flutter test test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cleantrack_chennai/main.dart';

void main() {
  testWidgets('app shows the loading screen, then the home screen',
      (tester) async {
    await tester.pumpWidget(const CleanTrackApp());
    expect(find.text('Loading demo data...'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('RUN FULL DEMO'), findsOneWidget);
    expect(find.text('Live end-to-end demo'), findsOneWidget);
  });

  testWidgets('IoT sensor screen: "Force overflow" sets the bin to 100%',
      (tester) async {
    await tester.pumpWidget(const CleanTrackApp());
    await tester.pump(const Duration(seconds: 1));

    final bin = store.binById('CHN-ANN-01')!; // seeded at 25%
    navKey.currentState!
        .push(MaterialPageRoute(builder: (_) => SensorScreen(binId: bin.id)));
    await tester.pumpAndSettle();

    final button = find.text('Force overflow');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(bin.fill, 100);
  });

  testWidgets('RUN FULL DEMO completes all 11 steps end to end',
      (tester) async {
    await tester.pumpWidget(const CleanTrackApp());
    await tester.pump(const Duration(seconds: 1));

    runFullDemo();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(store.demoStep, 11);
    expect(store.demoRunning, isFalse);

    final c = store.byId('CT-2026-1004')!; // Elaya Street complaint
    expect(c.status, Status.verified);
    expect(c.citizenFeedback, 'confirmed');
    expect(store.binById('CHN-TND-01')!.fill, 0);
  });
}

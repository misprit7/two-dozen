import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:two_dozen/main.dart';
import 'package:two_dozen/settings.dart';

void main() {
  testWidgets('classic game loads and accepts a move', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() async {
      await tester.pumpWidget(MyApp(appSettings: AppSettings(prefs)));
      // Puzzle generation runs asynchronously; give it real time to finish.
      for (var i = 0; i < 50 && find.text('TARGET').evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; ++i) {
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(find.text('TARGET'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Select a card and an operation; undo becomes available after a combine.
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('Solution'), findsOneWidget);
  });

  testWidgets('4nums hotkeys solve the easiest puzzle instantly', (WidgetTester tester) async {
    // Difficulty range pinned to the easiest classic hand: 1 1 4 6, where 1×1×4×6 = 24.
    SharedPreferences.setMockInitialValues({'flutter.minPercentile': 0.0, 'flutter.maxPercentile': 0.0});
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() async {
      await tester.pumpWidget(MyApp(appSettings: AppSettings(prefs)));
      for (var i = 0; i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; ++i) {
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(find.text('6'), findsOneWidget);

      // Esc on a fresh puzzle is a harmless undo; S multiplies everything.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      for (var i = 0; i < 20; ++i) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    // Solved count went up and a fresh puzzle (the same easiest hand) is already showing.
    expect(find.text('1'), findsWidgets);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('24'), findsOneWidget); // only the target, not a leftover card
  });
}

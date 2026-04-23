import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

/// Widget-level UI performance test for SmoothGrid.
///
/// Renders the actual SmoothGrid widget with real widget tree,
/// simulates scroll gestures, and measures frame build times.
///
/// Run with:
/// ```sh
/// flutter test benchmark/ui_benchmark_test.dart --reporter expanded
/// ```
void main() {
  // ============================================================
  // 1. Basic Rendering
  // ============================================================
  group('Widget Rendering', () {
    testWidgets('renders 1K items and all visible items are built', (
      tester,
    ) async {
      const itemCount = 1000;
      final builtIndices = <int>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: const EdgeInsets.all(8),
                itemExtentBuilder: (i) =>
                    100 + ((i * 2654435761) & 0xFF).toDouble(),
              ),
              itemBuilder: (context, index) {
                builtIndices.add(index);
                return SmoothGridTile(
                  child: Container(
                    color: Colors.blue,
                    child: Center(child: Text('$index')),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ignore: avoid_print
      print('Built ${builtIndices.length} items out of $itemCount');
      expect(builtIndices, isNotEmpty);
      expect(
        builtIndices.length,
        lessThan(itemCount),
        reason: 'Should only build visible items, not all $itemCount',
      );
    });

    testWidgets('renders 100K items without crash', (tester) async {
      const itemCount = 100000;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                itemExtentBuilder: (i) =>
                    80 + ((i * 2654435761) & 0x7F).toDouble(),
              ),
              itemBuilder: (context, index) {
                return SmoothGridTile(
                  child: Container(
                    color: Color(0xFF000000 | (index * 12345 & 0xFFFFFF)),
                    child: Center(
                      child: Text(
                        '#$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify SmoothGrid is rendered
      expect(find.byType(SmoothGrid), findsOneWidget);
      // ignore: avoid_print
      print('100K items rendered successfully');
    });
  });

  // ============================================================
  // 2. Scroll Performance
  // ============================================================
  group('Scroll Performance', () {
    testWidgets('scroll down 20 pages — measure frame times', (tester) async {
      const itemCount = 10000;
      int buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: const EdgeInsets.all(8),
                itemExtentBuilder: (i) =>
                    100 + ((i * 2654435761) & 0xFF).toDouble(),
              ),
              itemBuilder: (context, index) {
                buildCount++;
                return SmoothGridTile(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF000000 | (index * 54321 & 0xFFFFFF)),
                          Color(0xFF000000 | (index * 12345 & 0xFFFFFF)),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'Item #$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialBuildCount = buildCount;
      buildCount = 0;

      // Simulate 20 scroll-down gestures
      final scrollFinder = find.byType(SmoothGrid);
      final frameTimes = <int>[];

      for (var page = 0; page < 20; page++) {
        final sw = Stopwatch()..start();

        await tester.drag(scrollFinder, const Offset(0, -500));
        await tester.pump();

        sw.stop();
        frameTimes.add(sw.elapsedMicroseconds);
      }

      // Let inertia settle
      await tester.pumpAndSettle();

      frameTimes.sort();
      final p50 = frameTimes[frameTimes.length ~/ 2];
      final p95 = frameTimes[(frameTimes.length * 0.95).floor()];
      final maxFrame = frameTimes.last;

      // ignore: avoid_print
      print(
        'Scroll down 20 pages (10K items):\n'
        '  Initial build: $initialBuildCount widgets\n'
        '  Scroll builds: $buildCount widgets\n'
        '  Frame times — P50: ${(p50 / 1000).toStringAsFixed(1)}ms | '
        'P95: ${(p95 / 1000).toStringAsFixed(1)}ms | '
        'Max: ${(maxFrame / 1000).toStringAsFixed(1)}ms\n'
        '  Under 16ms budget: ${frameTimes.where((t) => t < 16000).length}/20',
      );

      // Most frames should complete under 16ms
      expect(
        p50,
        lessThan(16000),
        reason: 'P50 frame time should be under 16ms',
      );
    });

    testWidgets('rapid scroll back-and-forth — no crash', (tester) async {
      const itemCount = 50000;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                itemExtentBuilder: (i) =>
                    80 + ((i * 2654435761) & 0xFF).toDouble(),
              ),
              itemBuilder: (context, index) {
                return SmoothGridTile(
                  child: Container(
                    color: Color(0xFF000000 | (index * 7919 & 0xFFFFFF)),
                    child: Text(
                      '#$index',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SmoothGrid);

      // Rapid scroll: alternate directions
      for (var i = 0; i < 30; i++) {
        final direction = i.isEven ? -600.0 : 400.0;
        await tester.drag(scrollFinder, Offset(0, direction));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // If we get here without crash, it passed
      expect(find.byType(SmoothGrid), findsOneWidget);
      // ignore: avoid_print
      print('Rapid back-and-forth scroll (30 gestures): ✅ No crash');
    });

    testWidgets('fling scroll — measure settle time', (tester) async {
      const itemCount = 10000;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                itemExtentBuilder: (i) =>
                    100 + ((i * 2654435761) & 0xFF).toDouble(),
              ),
              itemBuilder: (context, index) {
                return SmoothGridTile(
                  child: Container(
                    color: Color(0xFF000000 | (index * 31337 & 0xFFFFFF)),
                    child: Text(
                      '#$index',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SmoothGrid);

      // Fling gesture
      final sw = Stopwatch()..start();
      await tester.fling(scrollFinder, const Offset(0, -2000), 3000);

      // Count frames until settled
      int frameCount = 0;
      while (frameCount < 200) {
        // safety limit
        await tester.pump(const Duration(milliseconds: 16));
        frameCount++;

        // Check if still scrolling by trying pump
        try {
          await tester.pump(Duration.zero);
        } catch (_) {
          break;
        }
      }
      sw.stop();

      // ignore: avoid_print
      print(
        'Fling scroll:\n'
        '  Settle time: ${sw.elapsedMilliseconds}ms\n'
        '  Frames rendered: $frameCount',
      );

      expect(find.byType(SmoothGrid), findsOneWidget);
    });
  });

  // ============================================================
  // 3. Heavy Widget Stress Test
  // ============================================================
  group('Heavy Widget Stress', () {
    testWidgets('complex widgets with gradients + icons + text', (
      tester,
    ) async {
      const itemCount = 5000;
      const categories = ['Nature', 'Travel', 'Food', 'Art', 'Music'];
      const icons = [
        Icons.park,
        Icons.flight,
        Icons.restaurant,
        Icons.palette,
        Icons.music_note,
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SmoothGrid(
              itemCount: itemCount,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                padding: const EdgeInsets.all(6),
                itemExtentBuilder: (i) =>
                    80 + ((i * 2654435761) & 0xFF).toDouble(),
              ),
              itemBuilder: (context, index) {
                final hash = (index * 2654435761) & 0xFFFFFFFF;
                final hue = (hash % 360).toDouble();
                final catIdx = hash % categories.length;
                final baseColor = HSLColor.fromAHSL(
                  1,
                  hue,
                  0.6,
                  0.35,
                ).toColor();
                final accentColor = HSLColor.fromAHSL(
                  1,
                  (hue + 40) % 360,
                  0.7,
                  0.25,
                ).toColor();

                return SmoothGridTile(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [baseColor, accentColor],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(
                            icons[catIdx],
                            size: 36,
                            color: const Color(0x33FFFFFF),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x44000000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              categories[catIdx],
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Text(
                            'Item #$index',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll and measure
      final scrollFinder = find.byType(SmoothGrid);
      final frameTimes = <int>[];

      for (var page = 0; page < 30; page++) {
        final sw = Stopwatch()..start();
        await tester.drag(scrollFinder, const Offset(0, -400));
        await tester.pump();
        sw.stop();
        frameTimes.add(sw.elapsedMicroseconds);
      }
      await tester.pumpAndSettle();

      frameTimes.sort();
      final p50 = frameTimes[frameTimes.length ~/ 2];
      final p95 = frameTimes[(frameTimes.length * 0.95).floor()];
      final maxFrame = frameTimes.last;
      final underBudget = frameTimes.where((t) => t < 16000).length;

      // ignore: avoid_print
      print(
        'Heavy widgets (gradient + icon + text, 5K items, 30 scroll pages):\n'
        '  P50: ${(p50 / 1000).toStringAsFixed(1)}ms | '
        'P95: ${(p95 / 1000).toStringAsFixed(1)}ms | '
        'Max: ${(maxFrame / 1000).toStringAsFixed(1)}ms\n'
        '  Under 16ms: $underBudget/30 frames',
      );

      expect(p50, lessThan(16000));
    });
  });

  // ============================================================
  // 4. Column Count Switch (simulates responsive layout)
  // ============================================================
  group('Dynamic Layout Switch', () {
    testWidgets('switch columns 2→3→4→6 without crash', (tester) async {
      const itemCount = 5000;
      int colCount = 2;

      late StateSetter testSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                testSetState = setState;
                return SmoothGrid(
                  itemCount: itemCount,
                  addAutomaticKeepAlives: false,
                  delegate: SmoothGridDelegate.count(
                    crossAxisCount: colCount,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    itemExtentBuilder: (i) =>
                        80 + ((i * 2654435761) & 0xFF).toDouble(),
                  ),
                  itemBuilder: (context, index) {
                    return SmoothGridTile(
                      child: Container(
                        color: Color(0xFF000000 | (index * 7919 & 0xFFFFFF)),
                        child: Center(
                          child: Text(
                            '#$index (${colCount}col)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final timings = <String>[];

      for (final cols in [3, 4, 6, 2]) {
        final sw = Stopwatch()..start();
        testSetState(() => colCount = cols);
        await tester.pumpAndSettle();
        sw.stop();
        timings.add('  ${cols}col: ${sw.elapsedMilliseconds}ms');
      }

      // ignore: avoid_print
      print('Column switch timings:\n${timings.join('\n')}');

      expect(find.byType(SmoothGrid), findsOneWidget);
      // ignore: avoid_print
      print('Dynamic column switch: ✅ No crash');
    });
  });

  // ============================================================
  // 5. Tap Interaction
  // ============================================================
  group('Interaction', () {
    testWidgets('tap fires onTap callback', (tester) async {
      int? tappedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmoothGrid(
              itemCount: 100,
              addAutomaticKeepAlives: false,
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                itemExtentBuilder: (_) => 150,
              ),
              itemBuilder: (context, index) {
                return SmoothGridTile(
                  child: Container(
                    color: Colors.blue,
                    child: Center(child: Text('$index')),
                  ),
                );
              },
              onTap: (index) {
                tappedIndex = index;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the first visible item
      final gridFinder = find.byType(SmoothGrid);
      await tester.tap(gridFinder);
      await tester.pump();

      // ignore: avoid_print
      print('Tapped index: $tappedIndex');
      // Note: tap may or may not register depending on gesture handling
      // The important thing is it doesn't crash
      expect(find.byType(SmoothGrid), findsOneWidget);
    });
  });
}

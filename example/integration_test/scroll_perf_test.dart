import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

/// Scroll smoothness integration test.
///
/// Measures actual frame timings during scroll on real device/emulator.
/// Run with: `flutter test integration_test/scroll_perf_test.dart --profile`
///
/// For detailed timeline:
/// `flutter drive --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart --profile`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const itemCount = 1000;

  double heightForIndex(int index) {
    final h = ((index * 2654435761) & 0xFFFFFFFF) % 200;
    return 80.0 + h;
  }

  Widget buildSmoothGrid({int columns = 3}) {
    return MaterialApp(
      home: Scaffold(
        body: SmoothGrid(
          itemCount: itemCount,
          delegate: SmoothGridDelegate.count(
            crossAxisCount: columns,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            padding: const EdgeInsets.all(6),
            itemExtentBuilder: (i) => heightForIndex(i),
          ),
          itemBuilder: (context, index) {
            final hash = ((index * 2654435761) & 0xFFFFFFFF);
            final hue = (hash % 360).toDouble();
            final baseColor = HSLColor.fromAHSL(1, hue, 0.6, 0.35).toColor();

            return SmoothGridTile(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: baseColor,
                ),
                child: Center(
                  child: Text(
                    '#$index',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildListView() {
    return MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final hash = ((index * 2654435761) & 0xFFFFFFFF);
            final hue = (hash % 360).toDouble();
            final baseColor = HSLColor.fromAHSL(1, hue, 0.6, 0.35).toColor();
            final height = heightForIndex(index);

            return Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: baseColor,
              ),
              child: Center(
                child: Text(
                  '#$index',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  group('Scroll Smoothness — SmoothGrid', () {
    testWidgets('slow scroll (fling)', (tester) async {
      await tester.pumpWidget(buildSmoothGrid());
      await tester.pumpAndSettle();

      await binding.traceAction(() async {
        for (var i = 0; i < 10; i++) {
          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -300),
            800,
          );
          await tester.pumpAndSettle();
        }
      }, reportKey: 'smooth_grid_slow_scroll');
    });

    testWidgets('fast scroll (rapid fling)', (tester) async {
      await tester.pumpWidget(buildSmoothGrid());
      await tester.pumpAndSettle();

      await binding.traceAction(() async {
        for (var i = 0; i < 10; i++) {
          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -1000),
            3000,
          );
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pumpAndSettle();
      }, reportKey: 'smooth_grid_fast_scroll');
    });

    testWidgets('column switch during scroll', (tester) async {
      int columns = 3;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SmoothGrid(
                  itemCount: itemCount,
                  delegate: SmoothGridDelegate.count(
                    crossAxisCount: columns,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    padding: const EdgeInsets.all(6),
                    itemExtentBuilder: (i) => heightForIndex(i),
                  ),
                  itemBuilder: (_, index) => SmoothGridTile(
                    child: Container(
                      color: Colors.primaries[index % Colors.primaries.length],
                      child: Center(child: Text('#$index')),
                    ),
                  ),
                ),
                floatingActionButton: FloatingActionButton(
                  key: const Key('switch_cols'),
                  onPressed: () => setState(() {
                    columns = columns == 3 ? 4 : 3;
                  }),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await binding.traceAction(() async {
        // Scroll, switch columns, scroll again
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -500),
          1500,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('switch_cols')));
        await tester.pumpAndSettle();

        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -500),
          1500,
        );
        await tester.pumpAndSettle();
      }, reportKey: 'smooth_grid_column_switch');
    });
  });

  group('Scroll Smoothness — ListView Baseline', () {
    testWidgets('slow scroll (fling)', (tester) async {
      await tester.pumpWidget(buildListView());
      await tester.pumpAndSettle();

      await binding.traceAction(() async {
        for (var i = 0; i < 10; i++) {
          await tester.fling(find.byType(ListView), const Offset(0, -300), 800);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'listview_slow_scroll');
    });

    testWidgets('fast scroll (rapid fling)', (tester) async {
      await tester.pumpWidget(buildListView());
      await tester.pumpAndSettle();

      await binding.traceAction(() async {
        for (var i = 0; i < 10; i++) {
          await tester.fling(
            find.byType(ListView),
            const Offset(0, -1000),
            3000,
          );
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pumpAndSettle();
      }, reportKey: 'listview_fast_scroll');
    });
  });
}

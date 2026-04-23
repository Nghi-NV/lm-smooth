import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

void main() {
  double heightForIndex(int index) {
    final h = ((index * 2654435761) & 0xFFFFFFFF) % 200;
    return 80.0 + h;
  }

  testWidgets('Column switch: children get new width', (tester) async {
    int columns = 3;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: SmoothGrid(
                itemCount: 100,
                delegate: SmoothGridDelegate.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  padding: const EdgeInsets.all(6),
                  itemExtentBuilder: (i) => heightForIndex(i),
                ),
                itemBuilder: (context, index) => SmoothGridTile(
                  child: Container(
                    key: ValueKey('item_$index'),
                    color: Colors.blue,
                    child: Text('$index'),
                  ),
                ),
              ),
              floatingActionButton: FloatingActionButton(
                key: const Key('switch'),
                onPressed: () => setState(() {
                  columns = columns == 3 ? 4 : 3;
                  debugPrint('[TEST] setState: columns=$columns');
                }),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // Find the first SmoothGridTile child and measure its width
    final firstItem = find.byKey(const ValueKey('item_0'));
    expect(firstItem, findsOneWidget);
    final size3col = tester.getSize(firstItem);
    debugPrint('[TEST] 3 cols: item_0 width=${size3col.width}');

    // Switch to 4 columns
    await tester.tap(find.byKey(const Key('switch')));
    await tester.pumpAndSettle();

    // Measure again
    final size4col = tester.getSize(firstItem);
    debugPrint('[TEST] 4 cols: item_0 width=${size4col.width}');

    // Width MUST be different with different column count
    expect(
      size4col.width,
      lessThan(size3col.width),
      reason: 'Item width should decrease when switching from 3 to 4 columns',
    );

    // Switch back to 3 columns
    await tester.tap(find.byKey(const Key('switch')));
    await tester.pumpAndSettle();

    final sizeBack = tester.getSize(firstItem);
    debugPrint('[TEST] Back to 3 cols: item_0 width=${sizeBack.width}');

    expect(
      sizeBack.width,
      closeTo(size3col.width, 1.0),
      reason: 'Item width should return to original when switching back',
    );
  });
}

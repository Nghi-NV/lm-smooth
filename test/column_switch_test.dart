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
                }),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final firstItem = find.byKey(const ValueKey('item_0'));
    expect(firstItem, findsOneWidget);
    final size3col = tester.getSize(firstItem);

    await tester.tap(find.byKey(const Key('switch')));
    await tester.pumpAndSettle();

    final size4col = tester.getSize(firstItem);

    expect(
      size4col.width,
      lessThan(size3col.width),
      reason: 'Item width should decrease when switching from 3 to 4 columns',
    );

    await tester.tap(find.byKey(const Key('switch')));
    await tester.pumpAndSettle();

    final sizeBack = tester.getSize(firstItem);

    expect(
      sizeBack.width,
      closeTo(size3col.width, 1.0),
      reason: 'Item width should return to original when switching back',
    );
  });
}

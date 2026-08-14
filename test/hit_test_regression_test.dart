import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

void main() {
  testWidgets('all visible SmoothGrid items receive taps', (tester) async {
    final tapped = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothGrid.count(
            itemCount: 8,
            crossAxisCount: 2,
            itemExtentBuilder: (_) => 120,
            itemBuilder: (_, index) => GestureDetector(
              key: ValueKey('item-$index'),
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped.add(index),
              child: ColoredBox(color: Colors.blue, child: Text('$index')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final index in [0, 1, 2, 3]) {
      await tester.tap(find.byKey(ValueKey('item-$index')));
      await tester.pump();
    }

    expect(tapped, [0, 1, 2, 3]);
  });
}

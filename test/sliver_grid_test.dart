import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

void main() {
  testWidgets('SmoothSliverGrid stays lazy in a parent CustomScrollView', (
    tester,
  ) async {
    final builtItems = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
              SmoothSliverGrid.count(
                itemCount: 300,
                crossAxisCount: 2,
                itemExtentBuilder: (_) => 120,
                itemBuilder: (context, index) {
                  builtItems.add(index);
                  return ColoredBox(
                    color: Colors.blue,
                    child: Text('item-$index'),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(builtItems, isNotEmpty);
    expect(builtItems.length, lessThan(300));
    expect(find.text('item-299'), findsNothing);
  });

  testWidgets('replacing a smooth sliver preserves the parent scroll offset', (
    tester,
  ) async {
    final controller = ScrollController();
    var layoutRevision = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CustomScrollView(
                controller: controller,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  SmoothSliverGrid.count(
                    key: ValueKey(layoutRevision),
                    itemCount: 100,
                    crossAxisCount: 2,
                    itemExtentBuilder: (index) =>
                        layoutRevision == 0 ? 120 : 122,
                    itemBuilder: (context, index) =>
                        Text('revision-$layoutRevision-item-$index'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(600);
    await tester.pump();
    expect(controller.offset, 600);

    rebuild(() => layoutRevision++);
    await tester.pump();

    expect(controller.offset, 600);
    controller.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

void main() {
  group('LayoutCache', () {
    test('set and get rect', () {
      final cache = LayoutCache();
      cache.setRect(0, 10, 20, 100, 50);
      cache.setRect(1, 110, 20, 100, 80);

      final r0 = cache.getRect(0);
      expect(r0.left, 10);
      expect(r0.top, 20);
      expect(r0.width, 100);
      expect(r0.height, 50);

      final r1 = cache.getRect(1);
      expect(r1.left, 110);
      expect(r1.top, 20);
      expect(r1.width, 100);
      expect(r1.height, 80);
    });

    test('totalItems and totalHeight', () {
      final cache = LayoutCache();
      cache.setRect(0, 0, 0, 100, 50);
      cache.setRect(1, 0, 50, 100, 30);

      expect(cache.totalItems, 2);
      expect(cache.totalHeight, 80); // 50 + 30
    });

    test('getY and getBottom', () {
      final cache = LayoutCache();
      cache.setRect(0, 0, 15, 100, 50);

      expect(cache.getY(0), 15);
      expect(cache.getBottom(0), 65);
    });

    test('flat list export/import', () {
      final cache = LayoutCache();
      cache.setRect(0, 10, 20, 100, 50);
      cache.setRect(1, 110, 20, 100, 80);

      final flatList = cache.toFlatList();
      expect(flatList.length, 8); // 2 items * 4 values

      final cache2 = LayoutCache();
      cache2.setFromFlatList(flatList, 2);

      expect(cache2.getRect(0), cache.getRect(0));
      expect(cache2.getRect(1), cache.getRect(1));
    });

    test('invalidateFrom', () {
      final cache = LayoutCache();
      for (var i = 0; i < 10; i++) {
        cache.setRect(i, 0, i * 100.0, 100, 90);
      }
      expect(cache.totalItems, 10);

      cache.invalidateFrom(5);
      expect(cache.totalItems, 5);
    });

    test('clear', () {
      final cache = LayoutCache();
      cache.setRect(0, 0, 0, 100, 50);
      cache.clear();
      expect(cache.totalItems, 0);
      expect(cache.totalHeight, 0);
    });
  });

  group('MasonryLayoutEngine', () {
    test('basic 3-column layout', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        viewportWidth: 340, // 3 * 100 + 2 * 10 + 2 * 10
        paddingLeft: 10,
        paddingRight: 10,
      );

      // 6 items with varying heights
      final heights = [100.0, 150.0, 120.0, 80.0, 90.0, 110.0];

      final totalHeight = engine.computeLayout(
        itemCount: 6,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );

      expect(cache.totalItems, 6);
      expect(totalHeight, greaterThan(0));

      // First row: items 0,1,2 placed in columns 0,1,2
      final r0 = cache.getRect(0);
      final r1 = cache.getRect(1);
      final r2 = cache.getRect(2);

      expect(r0.top, 0); // column 0 starts at 0
      expect(r1.top, 0); // column 1 starts at 0
      expect(r2.top, 0); // column 2 starts at 0

      // Item heights match input
      expect(r0.height, 100);
      expect(r1.height, 150);
      expect(r2.height, 120);
    });

    test('shortest column first placement', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(crossAxisCount: 2, viewportWidth: 200);

      // Item 0: h=100 → col 0 (both equal, picks first)
      // Item 1: h=50 → col 1 (col 1 is shorter)
      // Item 2: h=30 → col 1 (col 1 at 50, col 0 at 100)
      final heights = [100.0, 50.0, 30.0];

      engine.computeLayout(
        itemCount: 3,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );

      final r2 = cache.getRect(2);
      expect(r2.top, 50); // Placed below item 1 in column 1
    });

    test('layout 10K items without error', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        viewportWidth: 400,
      );

      final sw = Stopwatch()..start();
      engine.computeLayout(
        itemCount: 10000,
        itemExtentBuilder: (i) => 100.0 + (i % 5) * 30.0,
        config: config,
      );
      sw.stop();

      expect(cache.totalItems, 10000);
      // Should complete quickly
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('SpatialIndex', () {
    test('query range finds visible items', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);

      // 5 items, column 1 at different Y positions
      cache.setRect(0, 0, 0, 100, 50);
      cache.setRect(1, 100, 0, 100, 80);
      cache.setRect(2, 0, 50, 100, 60);
      cache.setRect(3, 100, 80, 100, 40);
      cache.setRect(4, 0, 110, 100, 50);

      spatialIndex.rebuild();

      // Query range [40, 100] should include items 0,1,2,3
      final range = spatialIndex.queryRange(40, 100);
      expect(range.start, greaterThanOrEqualTo(0));
      expect(range.end, greaterThanOrEqualTo(0));
    });

    test('empty cache returns -1', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      spatialIndex.rebuild();

      final range = spatialIndex.queryRange(0, 100);
      expect(range.start, -1);
      expect(range.end, -1);
    });
  });

  group('GestureRecognizer', () {
    test('tap detection', () {
      int? tappedIndex;
      final recognizer = SmoothGestureRecognizer(
        onTap: (index) => tappedIndex = index,
        hitTest: (x, y) => 5,
      );

      recognizer.handlePointerDown(100, 200);
      expect(recognizer.state, GestureState.pressStarted);

      recognizer.handlePointerUp(100, 200);
      expect(tappedIndex, 5);
      expect(recognizer.state, GestureState.idle);
    });

    test('drag detection when moved beyond slop', () {
      int? dragStartIndex;
      final recognizer = SmoothGestureRecognizer(
        config: const GestureConfig(dragSlop: 10),
        onDragStart: (index, dx, dy) => dragStartIndex = index,
        hitTest: (x, y) => 3,
      );

      recognizer.handlePointerDown(100, 200);
      // Move beyond slop
      recognizer.handlePointerMove(115, 200);

      expect(dragStartIndex, 3);
      expect(recognizer.state, GestureState.dragging);
    });

    test('no hit returns early', () {
      int? tappedIndex;
      final recognizer = SmoothGestureRecognizer(
        onTap: (index) => tappedIndex = index,
        hitTest: (x, y) => -1, // No hit
      );

      recognizer.handlePointerDown(100, 200);
      expect(recognizer.state, GestureState.idle);
      expect(tappedIndex, isNull);
    });
  });

  group('SmoothDragEngine', () {
    test('preview mapping shifts affected items only', () {
      final engine = SmoothDragEngine(collisionHysteresis: 10);
      final rects = <int, Rect>{
        0: const Rect.fromLTWH(0, 0, 100, 80),
        1: const Rect.fromLTWH(0, 90, 100, 100),
        2: const Rect.fromLTWH(0, 200, 100, 70),
        3: const Rect.fromLTWH(0, 280, 100, 60),
      };

      engine.startDrag(
        index: 0,
        dragRect: rects[0]!,
        pointerGlobal: const Offset(10, 10),
        pointerLocal: const Offset(10, 10),
      );
      engine.updatePointer(
        pointerGlobal: const Offset(10, 210),
        pointerLocal: const Offset(10, 210),
      );

      final target = engine.computeTargetIndex(
        candidateIndices: const [0, 1, 2, 3],
        getItemRect: (index) => rects[index]!,
        viewportTop: 0,
        viewportBottom: 400,
      );

      expect(target, 2);

      final preview = engine.buildPreviewOffsets(
        indices: const [0, 1, 2, 3],
        getItemRect: (index) => rects[index]!,
      );

      expect(preview[1], const Offset(0, -90));
      expect(preview[2], const Offset(0, -110));
      expect(preview.containsKey(0), isFalse);
      expect(preview.containsKey(3), isFalse);
    });

    test('collision hysteresis keeps current target stable', () {
      final engine = SmoothDragEngine(collisionHysteresis: 20);
      final rects = <int, Rect>{
        0: const Rect.fromLTWH(0, 0, 100, 80),
        1: const Rect.fromLTWH(0, 90, 100, 80),
        2: const Rect.fromLTWH(0, 180, 100, 80),
      };

      engine.startDrag(
        index: 0,
        dragRect: rects[0]!,
        pointerGlobal: const Offset(10, 120),
        pointerLocal: const Offset(10, 120),
      );

      expect(
        engine.computeTargetIndex(
          candidateIndices: const [0, 1, 2],
          getItemRect: (index) => rects[index]!,
          viewportTop: 0,
          viewportBottom: 400,
        ),
        1,
      );

      engine.updatePointer(
        pointerGlobal: const Offset(10, 136),
        pointerLocal: const Offset(10, 136),
      );

      expect(
        engine.computeTargetIndex(
          candidateIndices: const [0, 1, 2],
          getItemRect: (index) => rects[index]!,
          viewportTop: 0,
          viewportBottom: 400,
        ),
        1,
      );
    });
  });

  group('AutoScroller', () {
    test('velocity increases near viewport edge', () {
      final controller = ScrollController();
      final autoScroller = AutoScroller(
        scrollController: controller,
        edgeThreshold: 80,
        maxScrollVelocity: 1000,
      );

      final mid = autoScroller.computeVelocity(
        pointerY: 40,
        viewportHeight: 500,
      );
      final nearEdge = autoScroller.computeVelocity(
        pointerY: 5,
        viewportHeight: 500,
      );

      expect(mid, lessThan(0));
      expect(nearEdge.abs(), greaterThan(mid.abs()));
      expect(
        autoScroller.computeVelocity(pointerY: 250, viewportHeight: 500),
        0,
      );
    });
  });

  group('SmoothGrid reorder', () {
    testWidgets('long press drag reorders with overlay preview', (tester) async {
      final items = List<int>.generate(8, (i) => i);

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: SmoothGrid(
                  itemCount: items.length,
                  reorderable: true,
                  reorderConfig: const SmoothReorderConfig(
                    longPressDelay: Duration(milliseconds: 220),
                  ),
                  delegate: SmoothGridDelegate.count(
                    crossAxisCount: 1,
                    mainAxisSpacing: 8,
                    itemExtentBuilder: (_) => 80,
                  ),
                  itemBuilder: (context, index) => SmoothGridTile(
                    child: Container(
                      key: ValueKey('item_${items[index]}'),
                      alignment: Alignment.center,
                      color: Colors.blue,
                      child: Text('${items[index]}'),
                    ),
                  ),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      final item = items.removeAt(oldIndex);
                      items.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
                    });
                  },
                ),
              );
            },
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('item_0'))),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.moveBy(const Offset(0, 320));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(items.first, isNot(0));
      expect(items.indexOf(0), greaterThan(0));
    });

    testWidgets('drag near bottom auto-scrolls', (tester) async {
      final controller = ScrollController();
      final items = List<int>.generate(40, (i) => i);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 320,
            child: SmoothGrid(
              controller: controller,
              itemCount: items.length,
              reorderable: true,
              reorderConfig: const SmoothReorderConfig(
                longPressDelay: Duration(milliseconds: 220),
              ),
              delegate: SmoothGridDelegate.count(
                crossAxisCount: 1,
                mainAxisSpacing: 8,
                itemExtentBuilder: (_) => 80,
              ),
              itemBuilder: (context, index) => SmoothGridTile(
                child: Container(
                  key: ValueKey('scroll_item_${items[index]}'),
                  color: Colors.red,
                ),
              ),
              onReorder: (_, _) {},
            ),
          ),
        ),
      );

      final start = tester.getCenter(find.byKey(const ValueKey('scroll_item_0')));
      final gridRect = tester.getRect(find.byType(SmoothGrid));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 250));
      await gesture.moveTo(Offset(start.dx, gridRect.bottom - 4));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(controller.offset, greaterThan(0));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

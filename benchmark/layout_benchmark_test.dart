import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lm_smooth/lm_smooth.dart';

/// Benchmark suite for lm_smooth core components.
///
/// Run with:
/// ```sh
/// flutter test benchmark/layout_benchmark_test.dart --reporter expanded
/// ```
void main() {
  group('LayoutCache Benchmark', () {
    test('write 1M items — should complete < 500ms', () {
      final cache = LayoutCache();
      final sw = Stopwatch()..start();

      for (var i = 0; i < 1000000; i++) {
        cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
      }

      sw.stop();
      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('LayoutCache write 1M items: ${ms}ms');
      expect(ms, lessThan(500), reason: 'Writing 1M items should be < 500ms');
      expect(cache.totalItems, 1000000);
    });

    test('read 1M items — should complete < 200ms', () {
      final cache = LayoutCache();
      for (var i = 0; i < 1000000; i++) {
        cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
      }

      final sw = Stopwatch()..start();
      double sumHeight = 0;
      for (var i = 0; i < 1000000; i++) {
        final r = cache.getRect(i);
        sumHeight += r.height;
      }
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('LayoutCache read 1M items: ${ms}ms (sumHeight=$sumHeight)');
      expect(ms, lessThan(200), reason: 'Reading 1M items should be < 200ms');
    });

    test('flat list export/import 1M items — roundtrip', () {
      final cache = LayoutCache();
      for (var i = 0; i < 1000000; i++) {
        cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
      }

      final sw = Stopwatch()..start();
      final flat = cache.toFlatList();
      sw.stop();
      // ignore: avoid_print
      print(
        'LayoutCache export 1M → flat: ${sw.elapsedMilliseconds}ms (${flat.length} doubles)',
      );

      sw
        ..reset()
        ..start();
      final cache2 = LayoutCache();
      cache2.setFromFlatList(flat, 1000000);
      sw.stop();
      // ignore: avoid_print
      print('LayoutCache import flat → 1M: ${sw.elapsedMilliseconds}ms');

      // Verify correctness
      expect(cache2.totalItems, 1000000);
      expect(cache2.getRect(999999), cache.getRect(999999));
    });
  });

  group('MasonryLayoutEngine Benchmark', () {
    test('compute 1M items (4 columns) — should complete < 2s', () {
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
        paddingLeft: 8,
        paddingRight: 8,
      );

      final random = math.Random(42);
      final heights = List.generate(
        1000000,
        (i) => 80 + random.nextDouble() * 200,
      );

      final sw = Stopwatch()..start();
      final totalHeight = engine.computeLayout(
        itemCount: 1000000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print(
        'MasonryLayout 1M items (4 cols): ${ms}ms, totalHeight=${totalHeight.toStringAsFixed(0)}',
      );
      expect(ms, lessThan(2000), reason: 'Layout 1M items should be < 2s');
      expect(cache.totalItems, 1000000);
      expect(totalHeight, greaterThan(0));
    });

    test('incremental reflow from middle — should be fast', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(crossAxisCount: 3, viewportWidth: 360);

      final heights = List.generate(100000, (i) => 100 + (i % 7) * 20.0);

      // Full layout first
      engine.computeLayout(
        itemCount: 100000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );

      // Now reflow from index 50000
      final sw = Stopwatch()..start();
      engine.recomputeFrom(
        startIndex: 50000,
        itemCount: 100000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );
      sw.stop();

      // ignore: avoid_print
      print('Incremental reflow 50K→100K: ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('SpatialIndex Benchmark', () {
    test('queryRange on 1M items — should be < 1ms per query', () {
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

      final random = math.Random(42);
      final heights = List.generate(
        1000000,
        (i) => 80 + random.nextDouble() * 200,
      );

      engine.computeLayout(
        itemCount: 1000000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );

      // Perform 1000 random viewport queries
      final totalHeight = cache.totalHeight;
      final sw = Stopwatch()..start();
      for (var q = 0; q < 1000; q++) {
        final top = random.nextDouble() * (totalHeight - 800);
        final bottom = top + 800; // 800px viewport
        final range = spatialIndex.queryRange(top, bottom);
        expect(range.start, greaterThanOrEqualTo(0));
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print(
        'SpatialIndex 1000 queries on 1M items: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg',
      );
      // Each query should be O(log n) → < 1ms
      expect(
        avgMicros,
        lessThan(1000),
        reason: 'Average query should be < 1ms',
      );
    });
  });

  group('GestureRecognizer Benchmark', () {
    test('process 10K events — should be < 50ms', () {
      int tapCount = 0;
      int dragStartCount = 0;

      final recognizer = SmoothGestureRecognizer(
        config: const GestureConfig(dragSlop: 10),
        onTap: (_) => tapCount++,
        onDragStart: (_, __, ___) => dragStartCount++,
        onDragEnd: (_) {},
        hitTest: (x, y) => (x / 100).floor(),
      );

      final random = math.Random(42);
      final sw = Stopwatch()..start();

      for (var i = 0; i < 10000; i++) {
        final x = random.nextDouble() * 400;
        final y = random.nextDouble() * 800;

        recognizer.handlePointerDown(x, y);

        if (i % 3 == 0) {
          // Drag gesture
          recognizer.handlePointerMove(x + 20, y + 20);
          recognizer.handlePointerUp(x + 20, y + 20);
        } else {
          // Tap gesture
          recognizer.handlePointerUp(x, y);
        }
      }

      sw.stop();
      // ignore: avoid_print
      print(
        'GestureRecognizer 10K events: ${sw.elapsedMilliseconds}ms '
        '(taps=$tapCount, dragStarts=$dragStartCount)',
      );
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  group('Memory Estimate', () {
    test('LayoutCache memory for 1M items', () {
      // Each item = 4 doubles × 8 bytes = 32 bytes
      // 1M items = 32MB raw data
      // Chunks: 1M / 4096 = ~244 chunks
      const itemCount = 1000000;
      const bytesPerItem = 32; // 4 × Float64 (8 bytes each)
      const totalBytes = itemCount * bytesPerItem;
      const totalMB = totalBytes / (1024 * 1024);

      // ignore: avoid_print
      print('Memory estimate for $itemCount items:');
      // ignore: avoid_print
      print('  Raw layout data: ${totalMB.toStringAsFixed(1)} MB');
      // ignore: avoid_print
      print('  Chunks: ${(itemCount / 4096).ceil()} × 32KB');
      // ignore: avoid_print
      print('  Target: < 80MB total (including Flutter overhead)');

      expect(
        totalMB,
        lessThan(40),
        reason: 'Raw layout data should be < 40MB for 1M items',
      );
    });
  });
}

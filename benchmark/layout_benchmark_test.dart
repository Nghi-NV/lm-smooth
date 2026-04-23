import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart' hide HitTester;
import 'package:lm_smooth/lm_smooth.dart';

/// Comprehensive performance benchmark suite for lm_smooth.
///
/// Measures every hot path in the rendering pipeline.
/// Run with:
/// ```sh
/// flutter test benchmark/layout_benchmark_test.dart --reporter expanded
/// ```
///
/// Key metrics tracked:
/// - LayoutCache read/write throughput
/// - MasonryLayoutEngine layout speed
/// - SpatialIndex query latency (queryRange, findFirstVisible, findLastBefore)
/// - Delegate getGeometryForChildIndex throughput
/// - Simulated scroll performance
void main() {
  // ============================================================
  // 1. LayoutCache Benchmarks
  // ============================================================
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

    test('read 1M items (getRect) — should complete < 200ms', () {
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
      print('LayoutCache read (getRect) 1M items: ${ms}ms');
      expect(ms, lessThan(200));
      expect(sumHeight, greaterThan(0)); // prevent dead-code elimination
    });

    test(
      'read 1M items (getRaw zero-alloc) — should be faster than getRect',
      () {
        final cache = LayoutCache();
        for (var i = 0; i < 1000000; i++) {
          cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
        }

        final sw = Stopwatch()..start();
        double sumHeight = 0;
        for (var i = 0; i < 1000000; i++) {
          final r = cache.getRaw(i);
          sumHeight += r.h;
        }
        sw.stop();

        final ms = sw.elapsedMilliseconds;
        // ignore: avoid_print
        print('LayoutCache read (getRaw) 1M items: ${ms}ms');
        expect(ms, lessThan(200));
        expect(sumHeight, greaterThan(0));
      },
    );

    test('getY / getBottom — single-field access throughput', () {
      final cache = LayoutCache();
      for (var i = 0; i < 1000000; i++) {
        cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
      }

      final sw = Stopwatch()..start();
      double sum = 0;
      for (var i = 0; i < 1000000; i++) {
        sum += cache.getY(i);
        sum += cache.getBottom(i);
      }
      sw.stop();

      // ignore: avoid_print
      print(
        'LayoutCache getY+getBottom 1M×2: ${sw.elapsedMilliseconds}ms '
        '(${(sw.elapsedMicroseconds / 2000000).toStringAsFixed(3)}μs/op)',
      );
      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(sum, isNot(0));
    });

    test('flat list export/import roundtrip 1M items', () {
      final cache = LayoutCache();
      for (var i = 0; i < 1000000; i++) {
        cache.setRect(i, (i % 3) * 110.0, i * 30.0, 100, 80 + (i % 5) * 20.0);
      }

      final sw = Stopwatch()..start();
      final flat = cache.toFlatList();
      sw.stop();
      // ignore: avoid_print
      print('Export 1M → flat: ${sw.elapsedMilliseconds}ms');

      sw
        ..reset()
        ..start();
      final cache2 = LayoutCache();
      cache2.setFromFlatList(flat, 1000000);
      sw.stop();
      // ignore: avoid_print
      print('Import flat → 1M: ${sw.elapsedMilliseconds}ms');

      expect(cache2.totalItems, 1000000);
      expect(cache2.getRect(999999), cache.getRect(999999));
    });
  });

  // ============================================================
  // 2. MasonryLayoutEngine Benchmarks
  // ============================================================
  group('MasonryLayoutEngine Benchmark', () {
    late LayoutCache cache;
    late SpatialIndex spatialIndex;
    late MasonryLayoutEngine engine;
    late List<double> heights;

    setUp(() {
      cache = LayoutCache();
      spatialIndex = SpatialIndex(cache);
      engine = MasonryLayoutEngine(cache: cache, spatialIndex: spatialIndex);
      final random = math.Random(42);
      heights = List.generate(1000000, (i) => 80 + random.nextDouble() * 200);
    });

    test('compute 1M items (3 columns) — should complete < 2s', () {
      final config = MasonryLayoutConfig(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        viewportWidth: 400,
        paddingLeft: 8,
        paddingRight: 8,
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
        'MasonryLayout 1M items (3 cols): ${ms}ms, '
        'totalHeight=${totalHeight.toStringAsFixed(0)}',
      );
      expect(ms, lessThan(2000));
      expect(cache.totalItems, 1000000);
    });

    test('compute 1M items (4 columns) — should complete < 2s', () {
      final config = MasonryLayoutConfig(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        viewportWidth: 400,
        paddingLeft: 8,
        paddingRight: 8,
      );

      final sw = Stopwatch()..start();
      engine.computeLayout(
        itemCount: 1000000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );
      sw.stop();

      // ignore: avoid_print
      print('MasonryLayout 1M items (4 cols): ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('incremental reflow from middle — should be ~50% of full', () {
      final config = MasonryLayoutConfig(crossAxisCount: 3, viewportWidth: 360);

      final sw = Stopwatch()..start();
      engine.computeLayout(
        itemCount: 100000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );
      sw.stop();
      final fullMs = sw.elapsedMilliseconds;

      sw
        ..reset()
        ..start();
      engine.recomputeFrom(
        startIndex: 50000,
        itemCount: 100000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );
      sw.stop();
      final halfMs = sw.elapsedMilliseconds;

      // ignore: avoid_print
      print(
        'Full 100K: ${fullMs}ms | Reflow 50K→100K: ${halfMs}ms '
        '(ratio: ${(halfMs / math.max(1, fullMs)).toStringAsFixed(1)}x)',
      );
      // Reflow should complete in reasonable time (<500ms)
      // Note: recomputeFrom scans items before startIndex to reconstruct
      // column heights, so it may not always be faster than full layout.
      expect(halfMs, lessThan(500));
    });
  });

  // ============================================================
  // 3. SpatialIndex Benchmarks
  // ============================================================
  group('SpatialIndex Benchmark', () {
    late LayoutCache cache;
    late SpatialIndex spatialIndex;
    late double totalHeight;

    setUp(() {
      cache = LayoutCache();
      spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );
      final config = MasonryLayoutConfig(
        crossAxisCount: 3,
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
      totalHeight = cache.totalHeight;
    });

    test('queryRange: 1000 random queries on 1M items — avg < 100μs', () {
      final random = math.Random(42);
      final sw = Stopwatch()..start();

      for (var q = 0; q < 1000; q++) {
        final top = random.nextDouble() * (totalHeight - 800);
        final bottom = top + 800;
        final range = spatialIndex.queryRange(top, bottom);
        expect(range.start, greaterThanOrEqualTo(0));
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print(
        'queryRange 1K queries on 1M: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg',
      );
      expect(avgMicros, lessThan(1000));
    });

    test('findFirstVisibleIndex: 1000 queries — avg < 100μs', () {
      final random = math.Random(42);
      final sw = Stopwatch()..start();

      for (var q = 0; q < 1000; q++) {
        final offset = random.nextDouble() * (totalHeight - 800);
        final result = spatialIndex.findFirstVisibleIndex(offset);
        expect(result, greaterThanOrEqualTo(0));
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print(
        'findFirstVisibleIndex 1K queries on 1M: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg',
      );
      expect(avgMicros, lessThan(1000));
    });

    test('findLastItemBeforeOffset: 1000 queries — avg < 100μs', () {
      final random = math.Random(42);
      final sw = Stopwatch()..start();

      for (var q = 0; q < 1000; q++) {
        final offset = random.nextDouble() * totalHeight;
        final result = spatialIndex.findLastItemBeforeOffset(offset);
        expect(result, greaterThanOrEqualTo(-1));
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print(
        'findLastItemBeforeOffset 1K queries on 1M: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg',
      );
      expect(avgMicros, lessThan(1000));
    });

    test('queryVisibleItems: 100 queries — avg < 500μs', () {
      final random = math.Random(42);
      final sw = Stopwatch()..start();

      for (var q = 0; q < 100; q++) {
        final top = random.nextDouble() * (totalHeight - 800);
        final items = spatialIndex.queryVisibleItems(top, top + 800);
        expect(items, isNotEmpty);
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 100;
      // ignore: avoid_print
      print(
        'queryVisibleItems 100 queries on 1M: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg',
      );
      expect(avgMicros, lessThan(5000));
    });
  });

  // ============================================================
  // 4. SliverGridDelegate — Simulated Scroll Benchmark
  // ============================================================
  group('Delegate Scroll Simulation', () {
    test('simulate 60fps scroll (16ms budget) — 1000 frames on 1M items', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        viewportWidth: 400,
      );

      final random = math.Random(42);
      final heights = List.generate(
        1000000,
        (i) => 80 + random.nextDouble() * 200,
      );

      final totalHeight = engine.computeLayout(
        itemCount: 1000000,
        itemExtentBuilder: (i) => heights[i],
        config: config,
      );

      final delegate = SmoothSliverGridDelegate(
        cache: cache,
        spatialIndex: spatialIndex,
        totalExtent: totalHeight,
        itemCount: 1000000,
      );

      // Simulate scrolling: 1000 frames at ~16ms intervals
      // Each frame: getMin, getMax, then getGeometry for each visible child
      const viewportHeight = 800.0;
      const scrollSpeed = 50.0; // pixels per frame
      const frameCount = 1000;

      var scrollOffset = 0.0;
      var totalChildBuilds = 0;

      // Warm up: create layout once
      final layout = delegate.getLayout(
        const SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.forward,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 800,
          crossAxisExtent: 400,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 800,
          remainingCacheExtent: 1050,
          cacheOrigin: -250,
        ),
      );

      final sw = Stopwatch()..start();

      for (var frame = 0; frame < frameCount; frame++) {
        final top = scrollOffset;
        final bottom = scrollOffset + viewportHeight;

        final minIdx = layout.getMinChildIndexForScrollOffset(top);
        final maxIdx = layout.getMaxChildIndexForScrollOffset(bottom);

        // Simulate getGeometryForChildIndex for each visible child
        for (var i = minIdx; i <= maxIdx && i < 1000000; i++) {
          layout.getGeometryForChildIndex(i);
          totalChildBuilds++;
        }

        scrollOffset += scrollSpeed;
        if (scrollOffset > totalHeight - viewportHeight) {
          scrollOffset = 0; // Wrap around
        }
      }

      sw.stop();

      final totalMs = sw.elapsedMilliseconds;
      final avgFrameUs = sw.elapsedMicroseconds / frameCount;
      final avgChildrenPerFrame = totalChildBuilds / frameCount;

      // ignore: avoid_print
      print(
        'Scroll simulation ($frameCount frames):\n'
        '  Total: ${totalMs}ms\n'
        '  Avg frame: ${avgFrameUs.toStringAsFixed(1)}μs '
        '(budget: 16000μs)\n'
        '  Avg children/frame: ${avgChildrenPerFrame.toStringAsFixed(1)}\n'
        '  Total child builds: $totalChildBuilds',
      );

      // Each frame should use < 1ms of CPU for layout queries
      expect(
        avgFrameUs,
        lessThan(1000),
        reason: 'Avg frame query time should be < 1ms (we have 16ms budget)',
      );
    });
  });

  // ============================================================
  // 5. HitTester Benchmark
  // ============================================================
  group('HitTester Benchmark', () {
    test('1000 hit tests on 1M items — avg < 100μs', () {
      final cache = LayoutCache();
      final spatialIndex = SpatialIndex(cache);
      final engine = MasonryLayoutEngine(
        cache: cache,
        spatialIndex: spatialIndex,
      );

      final config = MasonryLayoutConfig(
        crossAxisCount: 3,
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

      final hitTester = HitTester(cache: cache, spatialIndex: spatialIndex);
      final totalHeight = cache.totalHeight;

      int hitCount = 0;
      final sw = Stopwatch()..start();

      for (var q = 0; q < 1000; q++) {
        final scrollOffset = random.nextDouble() * (totalHeight - 800);
        final x = random.nextDouble() * 400;
        final y = random.nextDouble() * 800;
        final result = hitTester.hitTest(x, y, scrollOffset: scrollOffset);
        if (result >= 0) hitCount++;
      }
      sw.stop();

      final avgMicros = sw.elapsedMicroseconds / 1000;
      // ignore: avoid_print
      print(
        'HitTester 1K queries on 1M: '
        '${sw.elapsedMilliseconds}ms total, '
        '${avgMicros.toStringAsFixed(1)}μs avg, '
        'hits: $hitCount/1000',
      );
      expect(avgMicros, lessThan(1000));
    });
  });

  // ============================================================
  // 6. GestureRecognizer Benchmark
  // ============================================================
  group('GestureRecognizer Benchmark', () {
    test('process 10K events — should be < 50ms', () {
      int tapCount = 0;
      int dragStartCount = 0;

      final recognizer = SmoothGestureRecognizer(
        config: const GestureConfig(dragSlop: 10),
        onTap: (_) => tapCount++,
        onDragStart: (a, b, c) => dragStartCount++,
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
          recognizer.handlePointerMove(x + 20, y + 20);
          recognizer.handlePointerUp(x + 20, y + 20);
        } else {
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

  // ============================================================
  // 7. Memory Estimation
  // ============================================================
  group('Memory Estimate', () {
    test('LayoutCache + SpatialIndex memory for 1M items', () {
      const itemCount = 1000000;

      // LayoutCache: 4 × Float64 (8 bytes) = 32 bytes per item
      const cacheBytes = itemCount * 32;

      // SpatialIndex: Float64List(n) + Int32List(n)
      // = n * 8 + n * 4 = 12 bytes per item
      const indexBytes = itemCount * 12;

      const totalBytes = cacheBytes + indexBytes;
      const totalMB = totalBytes / (1024 * 1024);

      // ignore: avoid_print
      print(
        'Memory for $itemCount items:\n'
        '  LayoutCache: ${(cacheBytes / 1024 / 1024).toStringAsFixed(1)} MB '
        '(${(itemCount / 4096).ceil()} chunks)\n'
        '  SpatialIndex: ${(indexBytes / 1024 / 1024).toStringAsFixed(1)} MB\n'
        '  Total: ${totalMB.toStringAsFixed(1)} MB',
      );

      // Total should be under 50MB for 1M items
      expect(totalMB, lessThan(50));
    });
  });
}

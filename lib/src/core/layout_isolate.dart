import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'layout_cache.dart';
import 'masonry_layout_engine.dart';
import 'spatial_index.dart';

/// Manages off-main-thread layout computation for large datasets (>100K items).
///
/// Uses [Isolate.run] for one-shot computation, transferring results
/// via [Float64List] for minimal copying overhead.
class LayoutIsolateManager {
  /// Threshold: use Isolate if itemCount exceeds this.
  ///
  /// Layout computation is intentionally very cheap after the spatial index
  /// stopped sorting during rebuild. Since item heights still have to be
  /// materialized on the main isolate before work can be transferred, using an
  /// isolate too early causes extra allocation and first-scroll jank.
  static const int kIsolateThreshold = 1000000;

  /// Compute layout on an Isolate if [itemCount] > [kIsolateThreshold],
  /// otherwise compute on the main thread.
  ///
  /// Returns the computed total height.
  static Future<double> computeLayout({
    required LayoutCache cache,
    required SpatialIndex spatialIndex,
    required int itemCount,
    required List<double> itemHeights,
    required int crossAxisCount,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    required double viewportWidth,
    double paddingLeft = 0,
    double paddingRight = 0,
    double paddingTop = 0,
    double paddingBottom = 0,
    bool forceIsolate = false,
  }) async {
    final useIsolate = forceIsolate || itemCount > kIsolateThreshold;

    if (useIsolate) {
      return _computeOnIsolate(
        cache: cache,
        spatialIndex: spatialIndex,
        itemCount: itemCount,
        itemHeights: itemHeights,
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        viewportWidth: viewportWidth,
        paddingLeft: paddingLeft,
        paddingRight: paddingRight,
        paddingTop: paddingTop,
        paddingBottom: paddingBottom,
      );
    } else {
      return _computeOnMainThread(
        cache: cache,
        spatialIndex: spatialIndex,
        itemCount: itemCount,
        itemHeights: itemHeights,
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        viewportWidth: viewportWidth,
        paddingLeft: paddingLeft,
        paddingRight: paddingRight,
        paddingTop: paddingTop,
        paddingBottom: paddingBottom,
      );
    }
  }

  static double _computeOnMainThread({
    required LayoutCache cache,
    required SpatialIndex spatialIndex,
    required int itemCount,
    required List<double> itemHeights,
    required int crossAxisCount,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    required double viewportWidth,
    required double paddingLeft,
    required double paddingRight,
    required double paddingTop,
    required double paddingBottom,
  }) {
    final config = MasonryLayoutConfig(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      viewportWidth: viewportWidth,
      paddingLeft: paddingLeft,
      paddingRight: paddingRight,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
    );

    final engine = MasonryLayoutEngine(
      cache: cache,
      spatialIndex: spatialIndex,
    );

    return engine.computeLayout(
      itemCount: itemCount,
      itemExtentBuilder: (i) => itemHeights[i],
      config: config,
    );
  }

  static Future<double> _computeOnIsolate({
    required LayoutCache cache,
    required SpatialIndex spatialIndex,
    required int itemCount,
    required List<double> itemHeights,
    required int crossAxisCount,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    required double viewportWidth,
    required double paddingLeft,
    required double paddingRight,
    required double paddingTop,
    required double paddingBottom,
  }) async {
    final params = IsolateLayoutParams(
      itemCount: itemCount,
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      viewportWidth: viewportWidth,
      itemHeights: itemHeights,
      paddingLeft: paddingLeft,
      paddingRight: paddingRight,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
    );

    // Run layout computation on Isolate
    final flatResult = await Isolate.run(() => computeLayoutIsolate(params));

    // Transfer results into cache — already Float64List, no conversion needed
    cache.setFromFlatList(flatResult, itemCount);

    // Rebuild spatial index on main thread (needs cache reference)
    spatialIndex.invalidate();
    spatialIndex.rebuild();

    return cache.totalHeight;
  }
}

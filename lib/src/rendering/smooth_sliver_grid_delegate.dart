import 'package:flutter/rendering.dart';

import '../core/layout_cache.dart';
import '../core/spatial_index.dart';

/// A [SliverGridDelegate] that reads layout from a pre-computed [LayoutCache].
///
/// This delegate does NOT compute layout itself — it only reads positions
/// from the cache that was already populated by the widget layer.
class SmoothSliverGridDelegate extends SliverGridDelegate {
  SmoothSliverGridDelegate({
    required this.cache,
    required this.spatialIndex,
    required this.totalExtent,
    required this.itemCount,
  });

  final LayoutCache cache;
  final SpatialIndex spatialIndex;
  final double totalExtent;
  final int itemCount;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    return _SmoothGridLayout(
      cache: cache,
      spatialIndex: spatialIndex,
      totalExtent: totalExtent,
      itemCount: itemCount,
    );
  }

  @override
  bool shouldRelayout(covariant SmoothSliverGridDelegate oldDelegate) {
    return oldDelegate.totalExtent != totalExtent ||
        oldDelegate.itemCount != itemCount ||
        !identical(oldDelegate.cache, cache);
  }
}

/// Custom [SliverGridLayout] that reads item geometry from pre-computed cache.
///
/// Uses [SpatialIndex.queryRange] (O(log n)) for viewport queries.
/// This correctly handles masonry grids where items are NOT monotonically
/// sorted by Y offset across indices.
class _SmoothGridLayout extends SliverGridLayout {
  final LayoutCache cache;
  final SpatialIndex spatialIndex;
  final double totalExtent;
  final int itemCount;

  const _SmoothGridLayout({
    required this.cache,
    required this.spatialIndex,
    required this.totalExtent,
    required this.itemCount,
  });

  @override
  double computeMaxScrollOffset(int childCount) {
    return totalExtent;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (itemCount == 0) return 0;
    if (scrollOffset <= 0) return 0;

    // Use SpatialIndex: correct O(log n) query on Y-sorted data.
    // Query a viewport-height window to find the min item index visible.
    final result = spatialIndex.findFirstVisibleIndex(scrollOffset);
    return result >= 0 ? result : 0;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (itemCount == 0) return 0;
    if (scrollOffset >= totalExtent) return itemCount - 1;

    // Find the last item whose top < scrollOffset.
    final result = spatialIndex.findLastItemBeforeOffset(scrollOffset);
    return result >= 0 ? result : 0;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index >= cache.totalItems || index < 0) {
      return const SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent: 0,
        crossAxisExtent: 0,
      );
    }

    // Use getRaw() to avoid Rect allocation — this is called per-child per-frame
    final r = cache.getRaw(index);
    return SliverGridGeometry(
      scrollOffset: r.y,
      crossAxisOffset: r.x,
      mainAxisExtent: r.h,
      crossAxisExtent: r.w,
    );
  }
}

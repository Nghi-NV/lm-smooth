import 'dart:math' as math;

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
/// Key insight for masonry layout:
/// Items are placed using "shortest column first". After placing i items,
/// the minimum column height is monotonically non-decreasing.
/// This means we can use binary search on the cache to find viewport bounds.
class _SmoothGridLayout extends SliverGridLayout {
  final LayoutCache cache;
  final double totalExtent;
  final int itemCount;

  const _SmoothGridLayout({
    required this.cache,
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

    // Binary search: find the first item whose bottom > scrollOffset
    // (i.e., it's still visible). Since items are NOT monotonically sorted
    // by Y (masonry interleaves columns), we use a conservative approach:
    //
    // We binary search for an approximate starting point, then back up
    // to ensure we don't miss items in other columns.
    var lo = 0;
    var hi = itemCount - 1;

    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final bottom = cache.getBottom(mid);
      if (bottom <= scrollOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // Now lo is approximately correct, but in a masonry grid items in
    // different columns can have different Y offsets at the same index range.
    // Back up by (crossAxisCount * 2) items to be safe.
    // We don't know crossAxisCount here, so back up by a fixed buffer.
    lo = math.max(0, lo - 20);

    // Linear scan forward to find the true first visible item
    while (lo < itemCount && cache.getBottom(lo) <= scrollOffset) {
      lo++;
    }

    return lo;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (itemCount == 0) return 0;
    if (scrollOffset >= totalExtent) return itemCount - 1;

    // Binary search: find the last item whose top < scrollOffset
    var lo = 0;
    var hi = itemCount - 1;

    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      final top = cache.getY(mid);
      if (top < scrollOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }

    // Forward buffer for items in other columns that might start
    // just before scrollOffset
    lo = math.min(itemCount - 1, lo + 20);

    // Linear scan backward to find the true last item starting before scrollOffset
    while (lo > 0 && cache.getY(lo) >= scrollOffset) {
      lo--;
    }

    return lo;
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

    final rect = cache.getRect(index);
    return SliverGridGeometry(
      scrollOffset: rect.top,
      crossAxisOffset: rect.left,
      mainAxisExtent: rect.height,
      crossAxisExtent: rect.width,
    );
  }
}

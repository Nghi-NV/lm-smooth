import '../core/layout_cache.dart';
import '../core/spatial_index.dart';

/// Translates pixel coordinates to item indices via [SpatialIndex].
///
/// O(log n) per lookup — uses binary search on sorted Y entries,
/// then checks X against column boundaries.
class HitTester {
  final LayoutCache _cache;
  final SpatialIndex _spatialIndex;

  HitTester({required LayoutCache cache, required SpatialIndex spatialIndex})
    : _cache = cache,
      _spatialIndex = spatialIndex;

  /// Returns the item index at position (x, y) relative to grid origin,
  /// or -1 if no item is at that position.
  ///
  /// [scrollOffset] is the current scroll position.
  int hitTest(double x, double y, {double scrollOffset = 0}) {
    // Convert to content-space Y
    final contentY = y + scrollOffset;

    // Query visible items around this Y
    final range = _spatialIndex.queryRange(contentY - 1, contentY + 1);
    if (range.start < 0) return -1;

    // Check each candidate item's full rect — zero-allocation
    for (var i = range.start; i <= range.end; i++) {
      if (i >= _cache.totalItems) break;

      final r = _cache.getRaw(i);
      if (x >= r.x &&
          x <= r.x + r.w &&
          contentY >= r.y &&
          contentY <= r.y + r.h) {
        return i;
      }
    }

    return -1;
  }
}

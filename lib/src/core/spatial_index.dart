import 'dart:typed_data';

import 'layout_cache.dart';

/// Spatial index for fast O(log n) range queries on the layout cache.
///
/// Given a vertical scroll range [top, bottom], this index finds the
/// first and last item indices that intersect that range.
///
/// Implementation: uses flat [Float64List] + [Int32List] arrays instead
/// of object lists to eliminate GC pressure. Binary search on sorted Y
/// offsets, with back-tracking for items that extend past the viewport top.
class SpatialIndex {
  final LayoutCache _cache;

  /// Flat arrays for zero-GC sorted entries.
  /// _sortedY[i] = Y position of the i-th sorted entry.
  /// _sortedIdx[i] = item index of the i-th sorted entry.
  Float64List _sortedY = Float64List(0);
  Int32List _sortedIdx = Int32List(0);
  int _length = 0;

  bool _isDirty = true;

  SpatialIndex(this._cache);

  /// Mark the index as needing rebuild (e.g., after layout changes).
  void invalidate() {
    _isDirty = true;
  }

  /// Rebuild the spatial index from the current layout cache.
  ///
  /// O(n log n) — called once after layout computation.
  /// Maximum backtrack distance in _lowerBoundTop to cap worst-case scan.
  static const int _maxBacktrack = 50;

  void rebuild() {
    final n = _cache.totalItems;
    if (n == 0) {
      _length = 0;
      _isDirty = false;
      return;
    }

    // Reuse arrays if same size, otherwise allocate new ones
    if (_sortedY.length != n) {
      _sortedY = Float64List(n);
      _sortedIdx = Int32List(n);
    }

    // Masonry layout assigns each next item to the current shortest column.
    // That minimum column height is monotonic, so Y is already sorted by index.
    // Keep the index identity-mapped to avoid sort scratch allocations.
    for (var i = 0; i < n; i++) {
      _sortedY[i] = _cache.getY(i);
      _sortedIdx[i] = i;
    }
    _length = n;
    assert(_debugAssertMonotonicY());

    _isDirty = false;
  }

  /// Incrementally rebuild the spatial index from [fromIndex] onward.
  ///
  /// Only updates Y values for items ≥ fromIndex, then re-sorts.
  /// This is O(k) for updating + O(n log n) worst-case sort, but Timsort
  /// on a nearly-sorted array (only tail changed) runs in ~O(n + k log k).
  ///
  /// Use after [MasonryLayoutEngine.recomputeFrom] or item reorder.
  void rebuildFrom(int fromIndex) {
    final n = _cache.totalItems;
    if (n == 0 || fromIndex >= n) {
      _isDirty = false;
      return;
    }

    // If array size changed, do full rebuild
    if (_length != n) {
      rebuild();
      return;
    }

    for (var i = fromIndex; i < _length; i++) {
      _sortedY[i] = _cache.getY(i);
      _sortedIdx[i] = i;
    }
    assert(_debugAssertMonotonicY());

    _isDirty = false;
  }

  /// Query the range of item indices whose rects intersect [top, bottom].
  ///
  /// Returns (startIndex, endIndex) inclusive.
  /// Returns (-1, -1) if no items intersect.
  ///
  /// O(log n) binary search + O(k) for collecting results.
  ({int start, int end}) queryRange(double top, double bottom) {
    if (_isDirty) rebuild();
    if (_length == 0) return (start: -1, end: -1);

    // Find first entry where Y + H > top (item's bottom > viewport top)
    var startIdx = _lowerBoundTop(top);
    if (startIdx >= _length) return (start: -1, end: -1);

    // Find last entry where Y < bottom (item starts before viewport bottom)
    var endIdx = _upperBoundBottom(bottom);
    if (endIdx < 0) return (start: -1, end: -1);

    if (startIdx > endIdx) return (start: -1, end: -1);

    // Convert sorted-entry indices back to item indices
    // We need the min and max item indices in visible range
    var minItem = _sortedIdx[startIdx];
    var maxItem = minItem;

    for (var i = startIdx + 1; i <= endIdx; i++) {
      final idx = _sortedIdx[i];
      if (idx < minItem) {
        minItem = idx;
      } else if (idx > maxItem) {
        maxItem = idx;
      }
    }

    return (start: minItem, end: maxItem);
  }

  /// Returns the list of item indices visible in [top, bottom] range,
  /// sorted by item index.
  ///
  /// This is more precise than [queryRange] — returns exact visible items
  /// instead of a continuous range.
  ///
  /// O(log n + k) where k = number of visible items.
  List<int> queryVisibleItems(double top, double bottom) {
    if (_isDirty) rebuild();
    if (_length == 0) return const [];

    // Use binary search to narrow the scan window
    final startPos = _lowerBoundTop(top);
    if (startPos >= _length) return const [];

    final endPos = _upperBoundBottom(bottom);
    if (endPos < 0) return const [];

    if (startPos > endPos) return const [];

    final result = <int>[];
    for (var i = startPos; i <= endPos; i++) {
      final itemIdx = _sortedIdx[i];
      final itemBottom = _cache.getBottom(itemIdx);
      if (itemBottom > top) {
        result.add(itemIdx);
      }
    }

    result.sort();
    return result;
  }

  /// Binary search: find first sorted index where the item's bottom > [top].
  int _lowerBoundTop(double top) {
    var lo = 0;
    var hi = _length;

    // Find first entry where Y >= top
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedY[mid] < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // Back up to find items that start before `top` but extend past it.
    // Bounded to _maxBacktrack to prevent O(k) scan with extreme heights.
    final minLo = lo > _maxBacktrack ? lo - _maxBacktrack : 0;
    while (lo > minLo) {
      final prevIdx = _sortedIdx[lo - 1];
      if (_cache.getBottom(prevIdx) > top) {
        lo--;
      } else {
        break;
      }
    }

    return lo;
  }

  /// Binary search: find last sorted index where Y < [bottom].
  int _upperBoundBottom(double bottom) {
    var lo = 0;
    var hi = _length;

    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedY[mid] < bottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    return lo - 1;
  }

  /// Find the minimum item index whose bottom edge > [scrollOffset].
  /// This is the first item that could be visible at this scroll position.
  ///
  /// O(log n) binary search on Y-sorted entries.
  int findFirstVisibleIndex(double scrollOffset) {
    if (_isDirty) rebuild();
    if (_length == 0) return -1;

    // Use _lowerBoundTop which already handles back-scanning
    // for items that start before scrollOffset but extend past it
    final startPos = _lowerBoundTop(scrollOffset);
    if (startPos >= _length) return -1;

    // Among visible entries starting from startPos, find minimum item index.
    // In masonry grid, we only need to check entries within the viewport
    // window — items at higher Y positions won't have lower indices.
    // Scan until Y exceeds scrollOffset (items fully past visible start)
    var minItemIdx = _sortedIdx[startPos];
    final scanEnd = _upperBoundBottom(scrollOffset + 1) + 1;
    final endPos = scanEnd < _length ? scanEnd : _length;
    for (var i = startPos + 1; i < endPos; i++) {
      final idx = _sortedIdx[i];
      if (idx < minItemIdx) {
        minItemIdx = idx;
      }
    }

    return minItemIdx;
  }

  /// Find the maximum item index whose top edge < [scrollOffset].
  /// This is the last item that starts before this scroll position.
  ///
  /// O(log n) binary search on Y-sorted entries.
  int findLastItemBeforeOffset(double scrollOffset) {
    if (_isDirty) rebuild();
    if (_length == 0) return -1;

    // Use _upperBoundBottom to find last entry where Y < scrollOffset
    final endPos = _upperBoundBottom(scrollOffset);
    if (endPos < 0) return -1;

    // Among entries [0, endPos], find the maximum item index.
    // Only scan the tail — entries near endPos have the highest Y
    // and in masonry are most likely to have the highest item indices.
    var maxItemIdx = _sortedIdx[endPos];
    // Scan backwards from endPos; in a masonry grid with C columns,
    // we need at most ~C entries to find the max index.
    final scanStart = endPos > 20 ? endPos - 20 : 0;
    for (var i = scanStart; i < endPos; i++) {
      final idx = _sortedIdx[i];
      if (idx > maxItemIdx) {
        maxItemIdx = idx;
      }
    }

    return maxItemIdx;
  }

  bool _debugAssertMonotonicY() {
    for (var i = 1; i < _length; i++) {
      if (_sortedY[i] < _sortedY[i - 1]) {
        throw StateError(
          'SpatialIndex requires masonry Y offsets to be monotonic by index. '
          'Item ${_sortedIdx[i]} has y=${_sortedY[i]} after '
          'item ${_sortedIdx[i - 1]} with y=${_sortedY[i - 1]}.',
        );
      }
    }
    return true;
  }
}

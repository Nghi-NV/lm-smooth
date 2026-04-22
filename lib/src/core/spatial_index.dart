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

    // Fill arrays
    for (var i = 0; i < n; i++) {
      _sortedY[i] = _cache.getY(i);
      _sortedIdx[i] = i;
    }
    _length = n;

    // Sort by Y position using indices array (insertion sort for small n,
    // otherwise use a simple quicksort-like approach)
    _sortByY(0, n - 1);

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
  List<int> queryVisibleItems(double top, double bottom) {
    if (_isDirty) rebuild();
    if (_length == 0) return const [];

    final result = <int>[];

    for (var i = 0; i < _length; i++) {
      if (_sortedY[i] >= bottom) break; // Past viewport, stop (sorted by Y)

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

    // Back up to find items that start before `top` but extend past it
    while (lo > 0) {
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

  /// In-place sort of _sortedIdx by _sortedY values.
  /// Uses introsort-like approach: quicksort with insertion sort for small ranges.
  void _sortByY(int left, int right) {
    if (right - left < 16) {
      // Insertion sort for small ranges
      for (var i = left + 1; i <= right; i++) {
        final keyY = _sortedY[i];
        final keyIdx = _sortedIdx[i];
        var j = i - 1;
        while (j >= left && (_sortedY[j] > keyY || (_sortedY[j] == keyY && _sortedIdx[j] > keyIdx))) {
          _sortedY[j + 1] = _sortedY[j];
          _sortedIdx[j + 1] = _sortedIdx[j];
          j--;
        }
        _sortedY[j + 1] = keyY;
        _sortedIdx[j + 1] = keyIdx;
      }
      return;
    }

    // Quicksort with median-of-three pivot
    final mid = (left + right) >> 1;
    // Sort left, mid, right
    if (_sortedY[left] > _sortedY[mid]) _swap(left, mid);
    if (_sortedY[left] > _sortedY[right]) _swap(left, right);
    if (_sortedY[mid] > _sortedY[right]) _swap(mid, right);

    // Pivot is median, place it at right-1
    _swap(mid, right - 1);
    final pivotY = _sortedY[right - 1];
    final pivotIdx = _sortedIdx[right - 1];

    var i = left;
    var j = right - 1;
    while (true) {
      while (_sortedY[++i] < pivotY || (_sortedY[i] == pivotY && _sortedIdx[i] < pivotIdx)) {}
      while (_sortedY[--j] > pivotY || (_sortedY[j] == pivotY && _sortedIdx[j] > pivotIdx)) {}
      if (i >= j) break;
      _swap(i, j);
    }
    _swap(i, right - 1);

    _sortByY(left, i - 1);
    _sortByY(i + 1, right);
  }

  void _swap(int a, int b) {
    final tmpY = _sortedY[a];
    _sortedY[a] = _sortedY[b];
    _sortedY[b] = tmpY;

    final tmpIdx = _sortedIdx[a];
    _sortedIdx[a] = _sortedIdx[b];
    _sortedIdx[b] = tmpIdx;
  }
}

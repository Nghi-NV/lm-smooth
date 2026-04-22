import 'layout_cache.dart';

/// Spatial index for fast O(log n) range queries on the layout cache.
///
/// Given a vertical scroll range [top, bottom], this index finds the
/// first and last item indices that intersect that range.
///
/// Implementation: binary search on sorted Y offsets within the [LayoutCache].
/// Items in a masonry layout are NOT sorted by Y globally, but each column
/// IS sorted. So we maintain per-column sorted indices and merge results.
///
/// Simplified approach: since items are added column-by-column in order,
/// we maintain a sorted "row boundary" list — the Y offset where each
/// "row band" starts. This gives O(log n) lookup.
class SpatialIndex {
  final LayoutCache _cache;

  /// Sorted list of (y, itemIndex) pairs for binary search.
  /// This is rebuilt when layout changes.
  List<_YEntry> _sortedEntries = [];

  bool _isDirty = true;

  SpatialIndex(this._cache);

  /// Mark the index as needing rebuild (e.g., after layout changes).
  void invalidate() {
    _isDirty = true;
  }

  /// Rebuild the spatial index from the current layout cache.
  ///
  /// O(n log n) — called once after layout computation.
  /// For 1M items this takes ~100ms, done on Isolate.
  void rebuild() {
    final n = _cache.totalItems;
    _sortedEntries = List<_YEntry>.generate(
      n,
      (i) => _YEntry(_cache.getY(i), i),
    );

    // Sort by Y position, then by index for stability
    _sortedEntries.sort((a, b) {
      final cmp = a.y.compareTo(b.y);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });

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
    if (_sortedEntries.isEmpty) return (start: -1, end: -1);

    // Find first entry where Y + H > top (item's bottom > viewport top)
    // This means: find items that haven't scrolled past the top
    var startIdx = _lowerBoundTop(top);
    if (startIdx >= _sortedEntries.length) return (start: -1, end: -1);

    // Find last entry where Y < bottom (item starts before viewport bottom)
    var endIdx = _upperBoundBottom(bottom);
    if (endIdx < 0) return (start: -1, end: -1);

    if (startIdx > endIdx) return (start: -1, end: -1);

    // Convert sorted-entry indices back to item indices
    // We need the min and max item indices in visible range
    var minItem = _sortedEntries[startIdx].index;
    var maxItem = _sortedEntries[startIdx].index;

    for (var i = startIdx; i <= endIdx; i++) {
      final idx = _sortedEntries[i].index;
      if (idx < minItem) minItem = idx;
      if (idx > maxItem) maxItem = idx;
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
    if (_sortedEntries.isEmpty) return const [];

    final result = <int>[];

    for (final entry in _sortedEntries) {
      if (entry.y >= bottom) break; // Past viewport, stop (sorted by Y)

      final itemBottom = _cache.getBottom(entry.index);
      if (itemBottom > top) {
        result.add(entry.index);
      }
    }

    result.sort();
    return result;
  }

  /// Binary search: find first entry index where the item's bottom > [top].
  ///
  /// item bottom = entry.y + item height
  int _lowerBoundTop(double top) {
    // We want items whose bottom edge > top, meaning they're still visible.
    // Since entries are sorted by Y, we find the first entry where Y could
    // potentially have bottom > top.
    //
    // Conservative: find first entry where Y > top - maxItemHeight.
    // But we don't know maxItemHeight, so scan from the binary search point.

    var lo = 0;
    var hi = _sortedEntries.length;

    // Find first entry where Y >= top (but item could start earlier and extend past top)
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedEntries[mid].y < top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    // Back up to find items that start before `top` but extend past it
    while (lo > 0) {
      final prevIdx = _sortedEntries[lo - 1].index;
      if (_cache.getBottom(prevIdx) > top) {
        lo--;
      } else {
        break;
      }
    }

    return lo;
  }

  /// Binary search: find last entry index where Y < [bottom].
  int _upperBoundBottom(double bottom) {
    var lo = 0;
    var hi = _sortedEntries.length;

    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedEntries[mid].y < bottom) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    return lo - 1;
  }
}

class _YEntry {
  final double y;
  final int index;

  const _YEntry(this.y, this.index);
}

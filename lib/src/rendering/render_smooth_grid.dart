import 'dart:math' as math;

import 'package:flutter/rendering.dart' hide ItemExtentBuilder;

import '../core/layout_cache.dart';
import '../core/layout_isolate.dart';
import '../core/masonry_layout_engine.dart';
import '../core/spatial_index.dart';
import 'smooth_grid_parent_data.dart';

class _ReorderPreviewResult {
  final Map<int, Offset> offsets;
  final Rect? dragRect;

  const _ReorderPreviewResult({required this.offsets, required this.dragRect});
}

/// Custom [RenderSliver] that implements a high-performance masonry grid.
///
/// Key performance characteristics:
/// - Only creates/layouts children in the visible viewport + overscan
/// - Uses pre-computed layout positions from [LayoutCache] (no measure pass)
/// - O(log n) binary search to find visible range via [SpatialIndex]
/// - `collectGarbage()` aggressively reclaims off-screen children
class RenderSmoothGrid extends RenderSliverMultiBoxAdaptor {
  static const int _kExactReorderPreviewItemLimit = 5000;
  static const int _kPartialReorderPreviewItemLimit = 12000;

  RenderSmoothGrid({
    required super.childManager,
    required MasonryLayoutConfig layoutConfig,
    required SmoothItemExtentBuilder itemExtentBuilder,
    required int itemCount,
  }) : _layoutConfig = layoutConfig,
       _itemExtentBuilder = itemExtentBuilder,
       _itemCount = itemCount {
    _layoutEngine = MasonryLayoutEngine(
      cache: _layoutCache,
      spatialIndex: _spatialIndex,
    );
  }

  final LayoutCache _layoutCache = LayoutCache();
  final LayoutCacheEntry _layoutEntry = LayoutCache.entry();
  late final SpatialIndex _spatialIndex = SpatialIndex(_layoutCache);
  late final MasonryLayoutEngine _layoutEngine;

  MasonryLayoutConfig _layoutConfig;
  SmoothItemExtentBuilder _itemExtentBuilder;
  int _itemCount;

  double _totalScrollExtent = 0;
  bool _needsLayoutRecompute = true;

  // --- Fast scroll path ---
  int _lastFirstIndex = -1;
  int _lastLastIndex = -1;
  bool _layoutJustRecomputed = false;

  // --- Auto-Isolate support ---
  bool? _useIsolate;
  bool _isolateInFlight = false;
  List<double>? _cachedItemHeights; // cache heights to avoid re-materialization
  int _cachedItemHeightsCount = 0;
  Map<int, Offset> _previewOffsets = const {};
  int _hiddenIndex = -1;
  Rect? _previewPlaceholderRect;

  // --- Property setters (trigger relayout) ---

  set layoutConfig(MasonryLayoutConfig value) {
    final configChanged =
        _layoutConfig.crossAxisCount != value.crossAxisCount ||
        _layoutConfig.mainAxisSpacing != value.mainAxisSpacing ||
        _layoutConfig.crossAxisSpacing != value.crossAxisSpacing;

    if (configChanged || _layoutConfig.viewportWidth != value.viewportWidth) {
      _layoutConfig = value;
      _needsLayoutRecompute = true;
      markNeedsLayout();
    }
  }

  set itemExtentBuilder(SmoothItemExtentBuilder value) {
    // Store the new builder but DON'T force recompute.
    // Function closures can't be compared; the setter is called on every
    // widget rebuild with a new closure even if the underlying data hasn't
    // changed. Only config/itemCount changes should trigger recompute.
    _itemExtentBuilder = value;
  }

  /// Explicitly mark layout as dirty when item heights actually change.
  /// Call this after updating item data that affects heights.
  void markLayoutDirty() {
    _needsLayoutRecompute = true;
    markNeedsLayout();
  }

  set itemCount(int value) {
    if (_itemCount != value) {
      _itemCount = value;
      _needsLayoutRecompute = true;
      markNeedsLayout();
    }
  }

  /// Controls Isolate usage.
  /// - `null`: auto (use Isolate for >100K items)
  /// - `true`: always use Isolate
  /// - `false`: never use Isolate
  set useIsolate(bool? value) {
    _useIsolate = value;
  }

  bool get _shouldUseIsolate {
    if (_useIsolate != null) return _useIsolate!;
    return _itemCount > LayoutIsolateManager.kIsolateThreshold;
  }

  Rect getItemRect(int index) {
    _layoutCache.readEntry(index, _layoutEntry);
    return Rect.fromLTWH(
      _layoutEntry.x,
      _layoutEntry.y,
      _layoutEntry.w,
      _layoutEntry.h,
    );
  }

  int getItemIndexAt(Offset contentOffset) {
    final band = constraints.viewportMainAxisExtent > 0
        ? constraints.viewportMainAxisExtent
        : 400.0;
    final candidates = queryVisibleItems(
      contentOffset.dy - band,
      contentOffset.dy + band,
    );
    var bestIndex = -1;
    var bestScore = double.infinity;
    for (final index in candidates) {
      final rect = getItemRect(index);
      if (rect.contains(contentOffset)) {
        return index;
      }
      final center = rect.center;
      final score =
          (contentOffset.dy - center.dy).abs() +
          ((contentOffset.dx - center.dx).abs() * 0.75);
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  List<int> queryVisibleItems(double top, double bottom) =>
      _spatialIndex.queryVisibleItems(top, bottom);

  Map<int, Offset> get previewOffsets => _previewOffsets;

  bool get _hasPreviewState =>
      _previewOffsets.isNotEmpty ||
      _hiddenIndex >= 0 ||
      _previewPlaceholderRect != null;

  Rect? computeReorderTargetRect({
    required int dragIndex,
    required int targetIndex,
  }) {
    return _simulateReorderPreview(
      dragIndex: dragIndex,
      targetIndex: targetIndex,
      indices: const <int>[],
    ).dragRect;
  }

  Map<int, Offset> buildReorderPreviewOffsets({
    required int dragIndex,
    required int targetIndex,
    required Iterable<int> indices,
  }) {
    return _simulateReorderPreview(
      dragIndex: dragIndex,
      targetIndex: targetIndex,
      indices: indices,
    ).offsets;
  }

  _ReorderPreviewResult _simulateReorderPreview({
    required int dragIndex,
    required int targetIndex,
    required Iterable<int> indices,
  }) {
    if (dragIndex < 0 ||
        targetIndex < 0 ||
        dragIndex >= _itemCount ||
        targetIndex > _itemCount ||
        dragIndex == targetIndex) {
      return const _ReorderPreviewResult(offsets: {}, dragRect: null);
    }

    if (_itemCount > _kExactReorderPreviewItemLimit) {
      return _simulateBoundedReorderPreview(
        dragIndex: dragIndex,
        targetIndex: targetIndex,
        indices: indices,
      );
    }

    final visible = indices.toSet();
    final order = List<int>.generate(
      _itemCount,
      (i) => i,
      growable: false,
    ).toList();
    final moved = order.removeAt(dragIndex);
    final insertAt = targetIndex > dragIndex ? targetIndex - 1 : targetIndex;
    order.insert(insertAt.clamp(0, order.length), moved);

    final columnCount = _layoutConfig.crossAxisCount;
    final columnXs = List<double>.generate(columnCount, _layoutConfig.columnX);
    final columnHeights = List<double>.filled(
      columnCount,
      _layoutConfig.paddingTop,
    );
    final offsets = <int, Offset>{};
    Rect? dragRect;

    for (final itemIndex in order) {
      var shortestCol = 0;
      var minHeight = columnHeights[0];
      for (var c = 1; c < columnCount; c++) {
        if (columnHeights[c] < minHeight) {
          minHeight = columnHeights[c];
          shortestCol = c;
        }
      }

      final currentRect = getItemRect(itemIndex);
      final nextTopLeft = Offset(
        columnXs[shortestCol],
        columnHeights[shortestCol],
      );
      if (itemIndex == dragIndex) {
        dragRect = nextTopLeft & currentRect.size;
      } else if (visible.contains(itemIndex)) {
        final delta = nextTopLeft - currentRect.topLeft;
        if (delta != Offset.zero) {
          offsets[itemIndex] = delta;
        }
      }

      columnHeights[shortestCol] =
          nextTopLeft.dy + currentRect.height + _layoutConfig.mainAxisSpacing;
    }

    return _ReorderPreviewResult(
      offsets: Map<int, Offset>.unmodifiable(offsets),
      dragRect: dragRect,
    );
  }

  _ReorderPreviewResult _simulateBoundedReorderPreview({
    required int dragIndex,
    required int targetIndex,
    required Iterable<int> indices,
  }) {
    final visibleIndices = indices is List<int>
        ? indices
        : indices.toList(growable: false);
    final partialPreview = _simulatePartialReorderPreview(
      dragIndex: dragIndex,
      targetIndex: targetIndex,
      indices: visibleIndices,
    );
    if (partialPreview != null) {
      return partialPreview;
    }

    final previewIndex = dragIndex < targetIndex
        ? (targetIndex - 1).clamp(0, _itemCount - 1)
        : targetIndex.clamp(0, _itemCount - 1);
    final targetRect = getItemRect(
      previewIndex == dragIndex ? dragIndex : previewIndex,
    );
    final draggedRect = getItemRect(dragIndex);
    final dragRect = targetRect.topLeft & draggedRect.size;

    final offsets = <int, Offset>{};
    _fillBoundedPreviewOffsets(
      offsets: offsets,
      indices: visibleIndices,
      dragIndex: dragIndex,
      targetIndex: targetIndex,
    );

    return _ReorderPreviewResult(
      offsets: Map<int, Offset>.unmodifiable(offsets),
      dragRect: dragRect,
    );
  }

  _ReorderPreviewResult? _simulatePartialReorderPreview({
    required int dragIndex,
    required int targetIndex,
    required List<int> indices,
  }) {
    var startIndex = dragIndex < targetIndex ? dragIndex : targetIndex;
    var endIndex = dragIndex < targetIndex ? targetIndex - 1 : dragIndex;
    if (indices.isNotEmpty) {
      final firstVisible = indices.first;
      final lastVisible = indices.last;
      if (firstVisible < startIndex && firstVisible <= dragIndex) {
        startIndex = firstVisible;
      }
      if (lastVisible > endIndex) {
        endIndex = lastVisible;
      }
    }

    startIndex = startIndex.clamp(0, _itemCount - 1);
    endIndex = endIndex.clamp(startIndex, _itemCount - 1);
    if (endIndex - startIndex + 1 > _kPartialReorderPreviewItemLimit) {
      return null;
    }

    final columnCount = _layoutConfig.crossAxisCount;
    final columnXs = List<double>.generate(columnCount, _layoutConfig.columnX);
    final columnHeights = _columnHeightsBefore(startIndex);
    final visible = indices.toSet();
    final offsets = <int, Offset>{};
    Rect? dragRect;

    void placeItem(int itemIndex) {
      if (itemIndex < startIndex || itemIndex > endIndex) return;

      var shortestCol = 0;
      var minHeight = columnHeights[0];
      for (var c = 1; c < columnCount; c++) {
        if (columnHeights[c] < minHeight) {
          minHeight = columnHeights[c];
          shortestCol = c;
        }
      }

      final currentRect = getItemRect(itemIndex);
      final nextTopLeft = Offset(
        columnXs[shortestCol],
        columnHeights[shortestCol],
      );
      if (itemIndex == dragIndex) {
        dragRect = nextTopLeft & currentRect.size;
      } else if (visible.contains(itemIndex)) {
        final delta = nextTopLeft - currentRect.topLeft;
        if (delta != Offset.zero) offsets[itemIndex] = delta;
      }

      columnHeights[shortestCol] =
          nextTopLeft.dy + currentRect.height + _layoutConfig.mainAxisSpacing;
    }

    if (dragIndex < targetIndex) {
      for (var index = startIndex; index < targetIndex; index++) {
        if (index == dragIndex) continue;
        placeItem(index);
      }
      placeItem(dragIndex);
      for (var index = targetIndex; index <= endIndex; index++) {
        placeItem(index);
      }
    } else {
      for (var index = startIndex; index <= endIndex; index++) {
        if (index == targetIndex) placeItem(dragIndex);
        if (index == dragIndex) continue;
        placeItem(index);
      }
    }

    return _ReorderPreviewResult(
      offsets: Map<int, Offset>.unmodifiable(offsets),
      dragRect: dragRect,
    );
  }

  List<double> _columnHeightsBefore(int index) {
    final columnCount = _layoutConfig.crossAxisCount;
    final heights = List<double>.filled(columnCount, _layoutConfig.paddingTop);
    if (index <= 0) return heights;

    var foundColumns = 0;
    final found = List<bool>.filled(columnCount, false);
    for (var itemIndex = index - 1; itemIndex >= 0; itemIndex--) {
      final rect = getItemRect(itemIndex);
      final column = _columnForX(rect.left);
      if (found[column]) continue;
      heights[column] = rect.bottom + _layoutConfig.mainAxisSpacing;
      found[column] = true;
      foundColumns++;
      if (foundColumns == columnCount) break;
    }

    return heights;
  }

  int _columnForX(double x) {
    final stride = _layoutConfig.columnWidth + _layoutConfig.crossAxisSpacing;
    if (stride <= 0) return 0;
    return ((x - _layoutConfig.paddingLeft) / stride).round().clamp(
      0,
      _layoutConfig.crossAxisCount - 1,
    );
  }

  void _fillBoundedPreviewOffsets({
    required Map<int, Offset> offsets,
    required List<int> indices,
    required int dragIndex,
    required int targetIndex,
  }) {
    if (dragIndex < targetIndex) {
      for (final index in indices) {
        if (index <= dragIndex || index >= targetIndex) continue;
        final from = getItemRect(index);
        final to = getItemRect(index - 1);
        final delta = to.topLeft - from.topLeft;
        if (delta != Offset.zero) offsets[index] = delta;
      }
    } else {
      for (final index in indices) {
        if (index < targetIndex || index >= dragIndex) continue;
        final from = getItemRect(index);
        final to = getItemRect(index + 1);
        final delta = to.topLeft - from.topLeft;
        if (delta != Offset.zero) offsets[index] = delta;
      }
    }
  }

  void setPreviewState({
    required Map<int, Offset> offsets,
    required int hiddenIndex,
    Rect? placeholderRect,
  }) {
    _previewOffsets = Map<int, Offset>.unmodifiable(offsets);
    _hiddenIndex = hiddenIndex;
    _previewPlaceholderRect = placeholderRect;
    markNeedsPaint();
  }

  void clearPreviewState() {
    if (_previewOffsets.isEmpty &&
        _hiddenIndex < 0 &&
        _previewPlaceholderRect == null) {
      return;
    }
    _previewOffsets = const {};
    _hiddenIndex = -1;
    _previewPlaceholderRect = null;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SmoothGridParentData) {
      child.parentData = SmoothGridParentData();
    }
  }

  @override
  void performLayout() {
    final constraints = this.constraints;

    if (constraints.crossAxisExtent <= 0 ||
        constraints.viewportMainAxisExtent <= 0) {
      geometry = SliverGeometry.zero;
      return;
    }

    // Update viewport width if changed
    if (_layoutConfig.viewportWidth != constraints.crossAxisExtent) {
      _layoutConfig = _layoutConfig.copyWith(
        viewportWidth: constraints.crossAxisExtent,
      );
      _needsLayoutRecompute = true;
    }

    // Recompute full masonry layout if needed
    _layoutJustRecomputed = false;
    if (_needsLayoutRecompute) {
      if (_shouldUseIsolate && !_isolateInFlight) {
        // Large dataset: try cached heights first (instant column switch)
        if (_cachedItemHeights != null &&
            _cachedItemHeightsCount == _itemCount) {
          // Heights cached — compute synchronously using cached data
          // Only positions change (new column layout), heights are the same.
          _totalScrollExtent = _layoutEngine.computeLayout(
            itemCount: _itemCount,
            itemExtentBuilder: (i) => _cachedItemHeights![i],
            config: _layoutConfig,
          );
          _needsLayoutRecompute = false;
          _layoutJustRecomputed = true;
          _lastFirstIndex = -1;
          _lastLastIndex = -1;
        } else {
          // First time — need to materialize heights (slow, use Isolate)
          _computeLayoutOnIsolate();
          if (_totalScrollExtent <= 0) {
            geometry = SliverGeometry.zero;
            return;
          }
        }
      } else if (!_isolateInFlight) {
        if (_itemCount > LayoutIsolateManager.kIsolateThreshold) {
          final itemHeights = List<double>.generate(
            _itemCount,
            _itemExtentBuilder,
            growable: false,
          );
          _cachedItemHeights = itemHeights;
          _cachedItemHeightsCount = _itemCount;
          _totalScrollExtent = _layoutEngine.computeLayout(
            itemCount: _itemCount,
            itemExtentBuilder: (i) => itemHeights[i],
            config: _layoutConfig,
          );
        } else {
          _totalScrollExtent = _layoutEngine.computeLayout(
            itemCount: _itemCount,
            itemExtentBuilder: _itemExtentBuilder,
            config: _layoutConfig,
          );
        }
        _needsLayoutRecompute = false;
        _layoutJustRecomputed = true;
        _lastFirstIndex = -1;
        _lastLastIndex = -1;
      }
    }

    if (_itemCount == 0) {
      geometry = SliverGeometry.zero;
      return;
    }

    final scrollOffset = constraints.scrollOffset;
    final remainingPaintExtent = constraints.remainingPaintExtent;

    // Compute the full cache region
    final cacheStart = scrollOffset + constraints.cacheOrigin;
    final cacheEnd = cacheStart + constraints.remainingCacheExtent;

    // Binary search for visible item range
    final range = _spatialIndex.queryRange(cacheStart, cacheEnd);

    if (range.start < 0 || range.end < 0 || _totalScrollExtent <= 0) {
      geometry = SliverGeometry(
        scrollExtent: _totalScrollExtent,
        paintExtent: 0,
        maxPaintExtent: _totalScrollExtent,
      );
      return;
    }

    final firstIndex = math.max(0, range.start);
    final lastIndex = math.min(range.end, _itemCount - 1);

    // ── Fast path: visible range unchanged, no layout recompute ──
    // During slow scroll, most frames have the same visible items.
    // Skip ALL child management — just update geometry.
    if (!_layoutJustRecomputed &&
        firstIndex == _lastFirstIndex &&
        lastIndex == _lastLastIndex &&
        firstChild != null) {
      _setGeometry(scrollOffset, remainingPaintExtent);
      return;
    }
    _lastFirstIndex = firstIndex;
    _lastLastIndex = lastIndex;

    // ── Step 1: Garbage collect children outside visible range ──
    final leadingGarbage = _countLeadingGarbage(firstIndex);
    final trailingGarbage = _countTrailingGarbage(lastIndex);
    collectGarbage(leadingGarbage, trailingGarbage);

    // ── Step 2: Seed the first child ──
    if (firstChild == null) {
      final y = _layoutCache.getY(firstIndex);
      if (!addInitialChild(index: firstIndex, layoutOffset: y)) {
        geometry = SliverGeometry(
          scrollExtent: _totalScrollExtent,
          paintExtent: 0,
          maxPaintExtent: _totalScrollExtent,
        );
        return;
      }
      _layoutChildAt(firstChild!, firstIndex);
    }

    // ── Step 3: Walk backward to firstIndex ──
    var currentLeadingIndex = indexOf(firstChild!);
    while (currentLeadingIndex > firstIndex) {
      final targetIndex = currentLeadingIndex - 1;
      _layoutCache.readEntry(targetIndex, _layoutEntry);
      final child = insertAndLayoutLeadingChild(
        BoxConstraints.tightFor(width: _layoutEntry.w, height: _layoutEntry.h),
      );
      if (child == null) break;
      _applyParentDataRaw(child, targetIndex, _layoutEntry.x, _layoutEntry.y);
      currentLeadingIndex = targetIndex;
    }

    // ── Step 4: Re-layout existing children ONLY when config changed ──
    // Use lastChild to skip the O(visible) walk on normal scroll frames.
    RenderBox trailingChild;
    if (_layoutJustRecomputed) {
      // Config changed — must re-layout ALL existing children with new sizes
      trailingChild = firstChild!;
      while (childAfter(trailingChild) != null) {
        trailingChild = childAfter(trailingChild)!;
        _layoutChildAt(trailingChild, indexOf(trailingChild));
      }
      // Also ensure firstChild is re-laid out
      _layoutChildAt(firstChild!, indexOf(firstChild!));
    } else {
      // Normal scroll — skip directly to lastChild (O(1) instead of O(visible))
      trailingChild = lastChild ?? firstChild!;
    }

    // ── Step 5: Create new children going forward ──
    var trailingIndex = indexOf(trailingChild);
    while (trailingIndex < lastIndex) {
      final nextIndex = trailingIndex + 1;
      if (nextIndex >= _itemCount) break;

      _layoutCache.readEntry(nextIndex, _layoutEntry);
      final child = insertAndLayoutChild(
        BoxConstraints.tightFor(width: _layoutEntry.w, height: _layoutEntry.h),
        after: trailingChild,
      );
      if (child == null) {
        childManager.setDidUnderflow(true);
        break;
      }
      _applyParentDataRaw(child, nextIndex, _layoutEntry.x, _layoutEntry.y);
      trailingChild = child;
      trailingIndex = nextIndex;
    }

    // ── Step 6: Compute geometry ──
    _setGeometry(scrollOffset, remainingPaintExtent);
  }

  /// Compute and set sliver geometry from scroll state.
  void _setGeometry(double scrollOffset, double remainingPaintExtent) {
    final paintExtent = math.min(
      remainingPaintExtent,
      math.max(0.0, _totalScrollExtent - scrollOffset),
    );

    final cacheExtent = math.min(
      constraints.remainingCacheExtent,
      math.max(
        0.0,
        _totalScrollExtent - scrollOffset + constraints.cacheOrigin,
      ),
    );

    geometry = SliverGeometry(
      scrollExtent: _totalScrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: _totalScrollExtent,
      cacheExtent: cacheExtent,
      hasVisualOverflow: _totalScrollExtent > constraints.remainingPaintExtent,
    );
  }

  /// Layout a child and apply its pre-computed position from cache.
  void _layoutChildAt(RenderBox child, int index) {
    if (index < 0 || index >= _layoutCache.totalItems) return;
    _layoutCache.readEntry(index, _layoutEntry);
    child.layout(
      BoxConstraints.tightFor(width: _layoutEntry.w, height: _layoutEntry.h),
      parentUsesSize: true,
    );
    _applyParentDataRaw(child, index, _layoutEntry.x, _layoutEntry.y);
  }

  /// Set parent data from raw layout values (zero-allocation).
  void _applyParentDataRaw(RenderBox child, int index, double x, double y) {
    final data = child.parentData! as SmoothGridParentData;
    data.layoutOffset = y;
    data.crossAxisOffset = x;
  }

  /// Count children before [firstIndex] that should be garbage collected.
  int _countLeadingGarbage(int firstIndex) {
    var count = 0;
    var child = firstChild;
    while (child != null) {
      if (indexOf(child) < firstIndex) {
        count++;
        child = childAfter(child);
      } else {
        break;
      }
    }
    return count;
  }

  /// Count children after [lastIndex] that should be garbage collected.
  int _countTrailingGarbage(int lastIndex) {
    var count = 0;
    var child = lastChild;
    while (child != null) {
      if (indexOf(child) > lastIndex) {
        count++;
        child = childBefore(child);
      } else {
        break;
      }
    }
    return count;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;

    if (!_hasPreviewState) {
      _paintNormalChildren(context, offset);
      return;
    }

    var child = firstChild;
    RenderBox? hiddenChild;
    while (child != null) {
      final data = child.parentData! as SmoothGridParentData;
      final index = indexOf(child);
      if (index == _hiddenIndex) {
        hiddenChild = child;
        child = childAfter(child);
        continue;
      }

      final mainAxisDelta = data.layoutOffset! - constraints.scrollOffset;
      final preview = _previewOffsets[index] ?? Offset.zero;

      // Only paint if within paint region
      if (mainAxisDelta + preview.dy < constraints.remainingPaintExtent &&
          mainAxisDelta + preview.dy + child.size.height > 0) {
        context.paintChild(
          child,
          offset +
              Offset(
                data.crossAxisOffset + preview.dx,
                mainAxisDelta + preview.dy,
              ),
        );
      }

      child = childAfter(child);
    }

    final placeholderRect = _previewPlaceholderRect;
    if (hiddenChild != null && placeholderRect != null) {
      final placeholderOffset =
          offset +
          Offset(
            placeholderRect.left,
            placeholderRect.top - constraints.scrollOffset,
          );
      final mainAxisDelta = placeholderRect.top - constraints.scrollOffset;
      if (mainAxisDelta < constraints.remainingPaintExtent &&
          mainAxisDelta + placeholderRect.height > 0) {
        context.pushOpacity(
          placeholderOffset,
          72,
          (context, offset) => context.paintChild(hiddenChild!, offset),
        );
      }
    }
  }

  void _paintNormalChildren(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as SmoothGridParentData;
      final mainAxisDelta = data.layoutOffset! - constraints.scrollOffset;

      if (mainAxisDelta < constraints.remainingPaintExtent &&
          mainAxisDelta + child.size.height > 0) {
        context.paintChild(
          child,
          offset + Offset(data.crossAxisOffset, mainAxisDelta),
        );
      }

      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    if (!_hasPreviewState) {
      return _hitTestNormalChildren(
        result,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      );
    }

    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as SmoothGridParentData;
      final index = indexOf(child);
      if (index == _hiddenIndex) {
        child = childBefore(child);
        continue;
      }
      final preview = _previewOffsets[index] ?? Offset.zero;
      final mainAxisDelta =
          data.layoutOffset! - constraints.scrollOffset + preview.dy;
      final childCrossAxis =
          crossAxisPosition - data.crossAxisOffset - preview.dx;

      if (hitTestBoxChild(
        BoxHitTestResult.wrap(result),
        child,
        mainAxisPosition: mainAxisPosition - mainAxisDelta,
        crossAxisPosition: childCrossAxis,
      )) {
        return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  bool _hitTestNormalChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as SmoothGridParentData;
      final mainAxisDelta = data.layoutOffset! - constraints.scrollOffset;
      final childCrossAxis = crossAxisPosition - data.crossAxisOffset;

      if (hitTestBoxChild(
        BoxHitTestResult.wrap(result),
        child,
        mainAxisPosition: mainAxisPosition - mainAxisDelta,
        crossAxisPosition: childCrossAxis,
      )) {
        return true;
      }
      child = childBefore(child);
    }
    return false;
  }

  @override
  double childMainAxisPosition(RenderBox child) {
    final data = child.parentData! as SmoothGridParentData;
    if (_previewOffsets.isEmpty) {
      return data.layoutOffset! - constraints.scrollOffset;
    }
    final preview = _previewOffsets[indexOf(child)] ?? Offset.zero;
    return data.layoutOffset! - constraints.scrollOffset + preview.dy;
  }

  @override
  double childCrossAxisPosition(RenderBox child) {
    final data = child.parentData! as SmoothGridParentData;
    if (_previewOffsets.isEmpty) {
      return data.crossAxisOffset;
    }
    final preview = _previewOffsets[indexOf(child)] ?? Offset.zero;
    return data.crossAxisOffset + preview.dx;
  }

  /// Notify that items have been reordered (for drag-drop).
  /// Triggers incremental relayout from [fromIndex].
  void reorderNotify(int fromIndex) {
    _totalScrollExtent = _layoutEngine.recomputeFrom(
      startIndex: fromIndex,
      itemCount: _itemCount,
      itemExtentBuilder: _itemExtentBuilder,
      config: _layoutConfig,
    );
    // Incremental spatial index rebuild — only update changed items
    _spatialIndex.rebuildFrom(fromIndex);
    markNeedsLayout();
  }

  /// First-time Isolate computation: materializes heights and computes layout.
  /// After completion, heights are cached in [_cachedItemHeights] so future
  /// column switches use the synchronous path (instant).
  void _computeLayoutOnIsolate() {
    _isolateInFlight = true;

    final itemCount = _itemCount;
    final config = _layoutConfig;

    // Pre-materialize heights on main thread (required — closures can't
    // cross Isolate boundary). This is O(n) but only happens ONCE.
    final itemHeights = List<double>.generate(
      itemCount,
      _itemExtentBuilder,
      growable: false,
    );

    // Cache heights for future column switches (instant reuse)
    _cachedItemHeights = itemHeights;
    _cachedItemHeightsCount = itemCount;

    LayoutIsolateManager.computeLayout(
      cache: _layoutCache,
      spatialIndex: _spatialIndex,
      itemCount: itemCount,
      itemHeights: itemHeights,
      crossAxisCount: config.crossAxisCount,
      mainAxisSpacing: config.mainAxisSpacing,
      crossAxisSpacing: config.crossAxisSpacing,
      viewportWidth: config.viewportWidth,
      paddingLeft: config.paddingLeft,
      paddingRight: config.paddingRight,
      paddingTop: config.paddingTop,
      paddingBottom: config.paddingBottom,
    ).then((totalHeight) {
      _totalScrollExtent = totalHeight;
      _needsLayoutRecompute = false;
      _isolateInFlight = false;
      _lastFirstIndex = -1;
      _lastLastIndex = -1;

      if (attached) {
        markNeedsLayout();
      }
    });
  }
}

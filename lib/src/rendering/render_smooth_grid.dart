import 'dart:math' as math;

import 'package:flutter/rendering.dart' hide ItemExtentBuilder;

import '../core/layout_cache.dart';
import '../core/layout_isolate.dart';
import '../core/masonry_layout_engine.dart';
import '../core/spatial_index.dart';
import 'smooth_grid_parent_data.dart';

/// Custom [RenderSliver] that implements a high-performance masonry grid.
///
/// Key performance characteristics:
/// - Only creates/layouts children in the visible viewport + overscan
/// - Uses pre-computed layout positions from [LayoutCache] (no measure pass)
/// - O(log n) binary search to find visible range via [SpatialIndex]
/// - `collectGarbage()` aggressively reclaims off-screen children
class RenderSmoothGrid extends RenderSliverMultiBoxAdaptor {
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
    final r = _layoutCache.getRaw(index);
    return Rect.fromLTWH(r.x, r.y, r.w, r.h);
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

  Map<int, Offset> buildReorderPreviewOffsets({
    required int dragIndex,
    required int targetIndex,
    required Iterable<int> indices,
  }) {
    if (dragIndex < 0 ||
        targetIndex < 0 ||
        dragIndex >= _itemCount ||
        targetIndex >= _itemCount ||
        dragIndex == targetIndex) {
      return const {};
    }

    final visible = indices.toSet();
    final order = List<int>.generate(_itemCount, (i) => i, growable: false).toList();
    final moved = order.removeAt(dragIndex);
    final insertAt = targetIndex > dragIndex ? targetIndex - 1 : targetIndex;
    order.insert(insertAt.clamp(0, order.length), moved);

    final columnCount = _layoutConfig.crossAxisCount;
    final columnXs = List<double>.generate(columnCount, _layoutConfig.columnX);
    final columnHeights = List<double>.filled(columnCount, _layoutConfig.paddingTop);
    final offsets = <int, Offset>{};

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
      final nextTopLeft = Offset(columnXs[shortestCol], columnHeights[shortestCol]);
      if (itemIndex != dragIndex && visible.contains(itemIndex)) {
        final delta = nextTopLeft - currentRect.topLeft;
        if (delta != Offset.zero) {
          offsets[itemIndex] = delta;
        }
      }

      columnHeights[shortestCol] =
          nextTopLeft.dy + currentRect.height + _layoutConfig.mainAxisSpacing;
    }

    return offsets;
  }

  void setPreviewState({
    required Map<int, Offset> offsets,
    required int hiddenIndex,
  }) {
    _previewOffsets = Map<int, Offset>.unmodifiable(offsets);
    _hiddenIndex = hiddenIndex;
    markNeedsPaint();
  }

  void clearPreviewState() {
    if (_previewOffsets.isEmpty && _hiddenIndex < 0) return;
    _previewOffsets = const {};
    _hiddenIndex = -1;
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
        // Sync path: compute on main thread
        _totalScrollExtent = _layoutEngine.computeLayout(
          itemCount: _itemCount,
          itemExtentBuilder: _itemExtentBuilder,
          config: _layoutConfig,
        );
        _needsLayoutRecompute = false;
        _layoutJustRecomputed = true;
        _lastFirstIndex = -1;
        _lastLastIndex = -1;

        // Cache heights for future column switches
        if (_itemCount > LayoutIsolateManager.kIsolateThreshold) {
          _cachedItemHeights = List<double>.generate(
            _itemCount,
            _itemExtentBuilder,
            growable: false,
          );
          _cachedItemHeightsCount = _itemCount;
        }
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
      final r = _layoutCache.getRaw(firstIndex);
      if (!addInitialChild(index: firstIndex, layoutOffset: r.y)) {
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
      final r = _layoutCache.getRaw(targetIndex);
      final child = insertAndLayoutLeadingChild(
        BoxConstraints.tightFor(width: r.w, height: r.h),
      );
      if (child == null) break;
      _applyParentDataRaw(child, targetIndex, r.x, r.y);
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

      final r = _layoutCache.getRaw(nextIndex);
      final child = insertAndLayoutChild(
        BoxConstraints.tightFor(width: r.w, height: r.h),
        after: trailingChild,
      );
      if (child == null) {
        childManager.setDidUnderflow(true);
        break;
      }
      _applyParentDataRaw(child, nextIndex, r.x, r.y);
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
    final r = _layoutCache.getRaw(index);
    child.layout(
      BoxConstraints.tightFor(width: r.w, height: r.h),
      parentUsesSize: true,
    );
    _applyParentDataRaw(child, index, r.x, r.y);
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

    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as SmoothGridParentData;
      final index = indexOf(child);
      if (index == _hiddenIndex) {
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
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
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

  @override
  double childMainAxisPosition(RenderBox child) {
    final data = child.parentData! as SmoothGridParentData;
    final preview = _previewOffsets[indexOf(child)] ?? Offset.zero;
    return data.layoutOffset! - constraints.scrollOffset + preview.dy;
  }

  @override
  double childCrossAxisPosition(RenderBox child) {
    final data = child.parentData! as SmoothGridParentData;
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

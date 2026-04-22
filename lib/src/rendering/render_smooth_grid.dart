import 'dart:math' as math;

import 'package:flutter/rendering.dart' hide ItemExtentBuilder;

import '../core/layout_cache.dart';
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

  // --- Property setters (trigger relayout) ---

  set layoutConfig(MasonryLayoutConfig value) {
    if (_layoutConfig.crossAxisCount != value.crossAxisCount ||
        _layoutConfig.mainAxisSpacing != value.mainAxisSpacing ||
        _layoutConfig.crossAxisSpacing != value.crossAxisSpacing ||
        _layoutConfig.viewportWidth != value.viewportWidth) {
      _layoutConfig = value;
      _needsLayoutRecompute = true;
      markNeedsLayout();
    }
  }

  set itemExtentBuilder(SmoothItemExtentBuilder value) {
    _itemExtentBuilder = value;
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

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SmoothGridParentData) {
      child.parentData = SmoothGridParentData();
    }
  }

  @override
  void performLayout() {
    final constraints = this.constraints;

    // Update viewport width if changed
    if (_layoutConfig.viewportWidth != constraints.crossAxisExtent) {
      _layoutConfig = MasonryLayoutConfig(
        crossAxisCount: _layoutConfig.crossAxisCount,
        mainAxisSpacing: _layoutConfig.mainAxisSpacing,
        crossAxisSpacing: _layoutConfig.crossAxisSpacing,
        viewportWidth: constraints.crossAxisExtent,
        paddingLeft: _layoutConfig.paddingLeft,
        paddingRight: _layoutConfig.paddingRight,
        paddingTop: _layoutConfig.paddingTop,
        paddingBottom: _layoutConfig.paddingBottom,
      );
      _needsLayoutRecompute = true;
    }

    // Recompute full masonry layout if needed
    if (_needsLayoutRecompute) {
      _totalScrollExtent = _layoutEngine.computeLayout(
        itemCount: _itemCount,
        itemExtentBuilder: _itemExtentBuilder,
        config: _layoutConfig,
      );
      _needsLayoutRecompute = false;
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

    // ── Step 1: Garbage collect children outside visible range ──
    final leadingGarbage = _countLeadingGarbage(firstIndex);
    final trailingGarbage = _countTrailingGarbage(lastIndex);
    collectGarbage(leadingGarbage, trailingGarbage);

    // ── Step 2: Seed the first child ──
    if (firstChild == null) {
      final rect = _layoutCache.getRect(firstIndex);
      if (!addInitialChild(index: firstIndex, layoutOffset: rect.top)) {
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
      final rect = _layoutCache.getRect(targetIndex);
      final child = insertAndLayoutLeadingChild(
        BoxConstraints.tightFor(width: rect.width, height: rect.height),
      );
      if (child == null) break;
      _applyParentData(child, targetIndex, rect);
      currentLeadingIndex = targetIndex;
    }

    // ── Step 4: Ensure firstChild is laid out ──
    {
      final idx = indexOf(firstChild!);
      _layoutChildAt(firstChild!, idx);
    }

    // ── Step 5: Walk forward to lastIndex ──
    var trailingChild = firstChild!;
    // Walk to the last existing child and layout each one
    while (childAfter(trailingChild) != null) {
      trailingChild = childAfter(trailingChild)!;
      final idx = indexOf(trailingChild);
      _layoutChildAt(trailingChild, idx);
    }

    // Create new children going forward
    while (indexOf(trailingChild) < lastIndex) {
      final nextIndex = indexOf(trailingChild) + 1;
      if (nextIndex > lastIndex || nextIndex >= _itemCount) break;

      final rect = _layoutCache.getRect(nextIndex);
      final child = insertAndLayoutChild(
        BoxConstraints.tightFor(width: rect.width, height: rect.height),
        after: trailingChild,
      );
      if (child == null) {
        childManager.setDidUnderflow(true);
        break;
      }
      _applyParentData(child, nextIndex, rect);
      trailingChild = child;
    }

    // ── Step 6: Compute geometry ──
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
    final rect = _layoutCache.getRect(index);
    child.layout(
      BoxConstraints.tightFor(width: rect.width, height: rect.height),
      parentUsesSize: true,
    );
    _applyParentData(child, index, rect);
  }

  /// Set parent data from pre-computed layout rect.
  void _applyParentData(RenderBox child, int index, Rect rect) {
    final data = child.parentData! as SmoothGridParentData;
    data.layoutOffset = rect.top;
    data.crossAxisOffset = rect.left;
    data.column = _getColumnForX(rect.left);
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
      final mainAxisDelta = data.layoutOffset! - constraints.scrollOffset;

      // Only paint if within paint region
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
    return data.layoutOffset! - constraints.scrollOffset;
  }

  @override
  double childCrossAxisPosition(RenderBox child) {
    final data = child.parentData! as SmoothGridParentData;
    return data.crossAxisOffset;
  }

  int _getColumnForX(double x) {
    final relativeX = x - _layoutConfig.paddingLeft;
    final colWidth = _layoutConfig.columnWidth + _layoutConfig.crossAxisSpacing;
    if (colWidth <= 0) return 0;
    return (relativeX / colWidth).floor().clamp(
      0,
      _layoutConfig.crossAxisCount - 1,
    );
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
    markNeedsLayout();
  }
}

import 'dart:math' as math;

import 'package:flutter/rendering.dart' hide ItemExtentBuilder;
import 'package:flutter/scheduler.dart';

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

  // --- Auto-Isolate support ---
  bool? _useIsolate;
  bool _isolateInFlight = false;

  // --- Property setters (trigger relayout) ---

  set layoutConfig(MasonryLayoutConfig value) {
    final configChanged =
        _layoutConfig.crossAxisCount != value.crossAxisCount ||
        _layoutConfig.mainAxisSpacing != value.mainAxisSpacing ||
        _layoutConfig.crossAxisSpacing != value.crossAxisSpacing;

    if (configChanged || _layoutConfig.viewportWidth != value.viewportWidth) {
      _layoutConfig = value;
      _needsLayoutRecompute = true;

      if (configChanged) {
        // Config changed structurally — all item positions are invalid.
        // Must clear cache and remove all children.
        _layoutCache.clear();
        _spatialIndex.invalidate();
      }

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
      _layoutConfig = _layoutConfig.copyWith(
        viewportWidth: constraints.crossAxisExtent,
      );
      _needsLayoutRecompute = true;
    }

    // Recompute full masonry layout if needed
    if (_needsLayoutRecompute) {
      if (_shouldUseIsolate && !_isolateInFlight) {
        // Async path: compute on Isolate, show old data while waiting
        _computeLayoutOnIsolate();
        // If we have no previous data, show empty
        if (_totalScrollExtent <= 0) {
          geometry = SliverGeometry.zero;
          return;
        }
        // Otherwise keep displaying old data until Isolate finishes
      } else if (!_isolateInFlight) {
        // Sync path: compute on main thread
        _totalScrollExtent = _layoutEngine.computeLayout(
          itemCount: _itemCount,
          itemExtentBuilder: _itemExtentBuilder,
          config: _layoutConfig,
        );
        _needsLayoutRecompute = false;
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
    data.column = _getColumnForX(x);
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
    // Incremental spatial index rebuild — only update changed items
    _spatialIndex.rebuildFrom(fromIndex);
    markNeedsLayout();
  }

  /// Compute layout on a background Isolate.
  ///
  /// Pre-materializes [_itemExtentBuilder] into a flat [List<double>],
  /// sends to Isolate, and triggers relayout when results arrive.
  void _computeLayoutOnIsolate() {
    _isolateInFlight = true;

    // Pre-materialize heights (must be done on main thread — callback access)
    final itemCount = _itemCount;
    final itemHeights = List<double>.generate(
      itemCount,
      _itemExtentBuilder,
      growable: false,
    );
    final config = _layoutConfig;

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

      // Schedule relayout on next frame (safe from Isolate callback)
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) {
          markNeedsLayout();
        }
      });
    });
  }
}

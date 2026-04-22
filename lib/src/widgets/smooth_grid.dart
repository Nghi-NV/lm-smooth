import 'package:flutter/widgets.dart';

import '../core/layout_cache.dart';
import '../core/masonry_layout_engine.dart';
import '../core/spatial_index.dart';
import '../rendering/smooth_sliver_grid_delegate.dart';
import 'smooth_grid_delegate.dart';

/// A high-performance staggered/masonry grid view.
///
/// Renders 1M+ items smoothly by:
/// - Pre-computing layout positions (no measure pass)
/// - Only building visible children via [SliverChildBuilderDelegate]
/// - Using [LayoutCache] with O(1) lookups and [SpatialIndex] with O(log n) queries
///
/// ## Basic Usage
/// ```dart
/// SmoothGrid(
///   itemCount: items.length,
///   itemBuilder: (context, index) => SmoothGridTile(
///     child: YourItemWidget(items[index]),
///   ),
///   delegate: SmoothGridDelegate.count(
///     crossAxisCount: 3,
///     mainAxisSpacing: 8,
///     crossAxisSpacing: 8,
///     itemExtentBuilder: (index) => items[index].height,
///   ),
/// )
/// ```
class SmoothGrid extends StatefulWidget {
  /// Total number of items in the grid.
  final int itemCount;

  /// Builder for each item widget.
  final IndexedWidgetBuilder itemBuilder;

  /// Layout delegate configuring columns, spacing, and item heights.
  final SmoothGridDelegate delegate;

  /// Optional scroll controller.
  final ScrollController? controller;

  /// Scroll physics.
  final ScrollPhysics? physics;

  /// Whether items can be reordered via drag and drop.
  final bool reorderable;

  /// Called when an item is tapped.
  final ValueChanged<int>? onTap;

  /// Called when an item is long-pressed.
  final ValueChanged<int>? onLongPress;

  /// Called when items are reordered via drag and drop.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// Whether to add [RepaintBoundary] to each item.
  final bool addRepaintBoundaries;

  /// Whether to add [AutomaticKeepAlive] to each item.
  final bool addAutomaticKeepAlives;

  /// Cache extent in pixels (overscan/prefetch area).
  final double? cacheExtent;

  /// Scroll direction. Default: vertical.
  final Axis scrollDirection;

  /// Whether the grid has a fixed extent and shrinks to fit.
  final bool shrinkWrap;

  const SmoothGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.delegate,
    this.controller,
    this.physics,
    this.reorderable = false,
    this.onTap,
    this.onLongPress,
    this.onReorder,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = true,
    this.cacheExtent,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = false,
  }) : assert(
         !reorderable || onReorder != null,
         'onReorder must be provided when reorderable is true',
       );

  @override
  State<SmoothGrid> createState() => _SmoothGridState();
}

class _SmoothGridState extends State<SmoothGrid> {
  final LayoutCache _cache = LayoutCache();
  late final SpatialIndex _spatialIndex = SpatialIndex(_cache);
  late final MasonryLayoutEngine _engine = MasonryLayoutEngine(
    cache: _cache,
    spatialIndex: _spatialIndex,
  );

  double _totalExtent = 0;
  double _lastViewportWidth = -1;
  bool _needsRecompute = true;

  // Track config changes
  int _lastItemCount = -1;
  int _lastCrossAxisCount = -1;
  double _lastMainAxisSpacing = -1;
  double _lastCrossAxisSpacing = -1;

  @override
  void didUpdateWidget(covariant SmoothGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final del = widget.delegate;
    if (widget.itemCount != _lastItemCount ||
        del.crossAxisCount != _lastCrossAxisCount ||
        del.mainAxisSpacing != _lastMainAxisSpacing ||
        del.crossAxisSpacing != _lastCrossAxisSpacing) {
      _needsRecompute = true;
    }
  }

  void _ensureLayout(double viewportWidth) {
    if (viewportWidth <= 0) return; // Guard: no valid viewport yet
    if (!_needsRecompute && viewportWidth == _lastViewportWidth) return;

    final del = widget.delegate;
    final config = del.toConfig(viewportWidth);

    _totalExtent = _engine.computeLayout(
      itemCount: widget.itemCount,
      itemExtentBuilder: del.itemExtentBuilder,
      config: config,
    );

    _lastViewportWidth = viewportWidth;
    _lastItemCount = widget.itemCount;
    _lastCrossAxisCount = del.crossAxisCount;
    _lastMainAxisSpacing = del.mainAxisSpacing;
    _lastCrossAxisSpacing = del.crossAxisSpacing;
    _needsRecompute = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = widget.scrollDirection == Axis.vertical
            ? constraints.maxWidth
            : constraints.maxHeight;

        // Skip rendering if viewport has no size yet (first frame)
        if (viewportWidth <= 0) {
          return const SizedBox.shrink();
        }

        // Pre-compute layout before building SliverGrid
        _ensureLayout(viewportWidth);

        return CustomScrollView(
          controller: widget.controller,
          physics: widget.physics,
          scrollDirection: widget.scrollDirection,
          shrinkWrap: widget.shrinkWrap,
          cacheExtent: widget.cacheExtent,
          slivers: [
            SliverGrid(
              gridDelegate: SmoothSliverGridDelegate(
                cache: _cache,
                spatialIndex: _spatialIndex,
                totalExtent: _totalExtent,
                itemCount: widget.itemCount,
              ),
              delegate: SliverChildBuilderDelegate(
                _buildItem,
                childCount: widget.itemCount,
                addRepaintBoundaries: widget.addRepaintBoundaries,
                addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    Widget child = widget.itemBuilder(context, index);

    // Wrap with gesture detectors if needed (only when NOT reorderable)
    if (!widget.reorderable &&
        (widget.onTap != null || widget.onLongPress != null)) {
      child = GestureDetector(
        onTap: widget.onTap != null ? () => widget.onTap!(index) : null,
        onLongPress: widget.onLongPress != null
            ? () => widget.onLongPress!(index)
            : null,
        child: child,
      );
    }

    // Wrap with drag-and-drop when reorderable
    if (widget.reorderable) {
      child = _buildDraggableItem(context, index, child);
    }

    return child;
  }

  Widget _buildDraggableItem(BuildContext context, int index, Widget child) {
    return LongPressDraggable<int>(
      data: index,
      delay: const Duration(milliseconds: 300),
      hapticFeedbackOnStart: true,
      // Ghost feedback shown while dragging
      feedback: SizedBox(
        width: _cache.totalItems > index
            ? _cache.getRaw(index).w
            : 120,
        height: _cache.totalItems > index
            ? _cache.getRaw(index).h
            : 120,
        child: Opacity(
          opacity: 0.85,
          child: Transform.scale(
            scale: 1.05,
            child: child,
          ),
        ),
      ),
      // Dim the original item while dragging
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: child,
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) {
          final oldIndex = details.data;
          widget.onReorder?.call(oldIndex, index);
        },
        builder: (context, candidateData, rejectedData) {
          // Highlight when a draggable hovers over this target
          if (candidateData.isNotEmpty) {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF6750A4),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            );
          }
          // Wrap with tap handler in reorderable mode
          if (widget.onTap != null) {
            return GestureDetector(
              onTap: () => widget.onTap!(index),
              child: child,
            );
          }
          return child;
        },
      ),
    );
  }
}


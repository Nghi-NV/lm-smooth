import 'package:flutter/widgets.dart';

import '../rendering/render_smooth_grid.dart';
import 'smooth_grid_delegate.dart';

/// A high-performance staggered/masonry grid view.
///
/// Renders 1M+ items smoothly by:
/// - Pre-computing layout positions (no measure pass)
/// - Only building visible children via [SliverChildBuilderDelegate]
/// - Using [LayoutCache] with O(1) lookups and [SpatialIndex] with O(log n) queries
/// - **No LayoutBuilder overhead** — constraints read directly in RenderSliver
///
/// For datasets >100K items, layout is automatically computed on a background
/// Isolate to avoid blocking the main thread. Set [useIsolate] to override.
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

  /// Controls Isolate usage for layout computation.
  /// - `null` (default): auto-detect (use Isolate for >100K items)
  /// - `true`: always use Isolate
  /// - `false`: never use Isolate
  final bool? useIsolate;

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
    this.addAutomaticKeepAlives = false,
    this.cacheExtent,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = false,
    this.useIsolate,
  }) : assert(
         !reorderable || onReorder != null,
         'onReorder must be provided when reorderable is true',
       );

  @override
  State<SmoothGrid> createState() => _SmoothGridState();
}

class _SmoothGridState extends State<SmoothGrid> {
  @override
  Widget build(BuildContext context) {
    // NO LayoutBuilder! Constraints are read directly by RenderSmoothGrid
    // in performLayout() via constraints.crossAxisExtent.
    // This eliminates an extra build frame on resize.
    return CustomScrollView(
      controller: widget.controller,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      shrinkWrap: widget.shrinkWrap,
      cacheExtent: widget.cacheExtent,
      slivers: [
        _SmoothGridSliver(
          itemCount: widget.itemCount,
          itemBuilder: _buildItem,
          gridDelegate: widget.delegate,
          addRepaintBoundaries: widget.addRepaintBoundaries,
          addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
          useIsolate: widget.useIsolate,
        ),
      ],
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
      feedback: SizedBox(
        width: 120,
        height: 120,
        child: Opacity(
          opacity: 0.85,
          child: Transform.scale(scale: 1.05, child: child),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) {
          final oldIndex = details.data;
          widget.onReorder?.call(oldIndex, index);
        },
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF6750A4), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            );
          }
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

// ---------------------------------------------------------------------------
// _SmoothGridSliver: Direct RenderObjectWidget → RenderSmoothGrid
// ---------------------------------------------------------------------------

/// A sliver that creates a [RenderSmoothGrid] directly, bypassing
/// the SliverGrid → SliverGridDelegate indirection.
///
/// This avoids LayoutBuilder overhead and gives the RenderObject direct
/// access to sliver constraints for viewport-width-based layout.
class _SmoothGridSliver extends SliverMultiBoxAdaptorWidget {
  final SmoothGridDelegate gridDelegate;
  final int itemCount;
  final bool? useIsolate;

  _SmoothGridSliver({
    required this.itemCount,
    required IndexedWidgetBuilder itemBuilder,
    required this.gridDelegate,
    required bool addRepaintBoundaries,
    required bool addAutomaticKeepAlives,
    this.useIsolate,
  }) : super(
         delegate: SliverChildBuilderDelegate(
           itemBuilder,
           childCount: itemCount,
           addRepaintBoundaries: addRepaintBoundaries,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
         ),
       );

  @override
  SliverMultiBoxAdaptorElement createElement() =>
      SliverMultiBoxAdaptorElement(this, replaceMovedChildren: true);

  @override
  RenderSmoothGrid createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    // viewportWidth=0 initially; RenderSmoothGrid.performLayout() detects
    // the real width from constraints.crossAxisExtent and triggers recompute.
    final config = gridDelegate.toConfig(0);
    return RenderSmoothGrid(
      childManager: element,
      layoutConfig: config,
      itemExtentBuilder: gridDelegate.itemExtentBuilder,
      itemCount: itemCount,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSmoothGrid renderObject,
  ) {
    // viewportWidth=0 here; actual width comes from performLayout constraints
    final config = gridDelegate.toConfig(0);
    renderObject
      ..layoutConfig = config
      ..itemExtentBuilder = gridDelegate.itemExtentBuilder
      ..itemCount = itemCount;
  }
}

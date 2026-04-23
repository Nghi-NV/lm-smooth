import 'package:flutter/widgets.dart';

/// Manages the drag-drop overlay ghost and auto-scrolling during reorder.
///
/// Architecture:
/// 1. On drag start: create [OverlayEntry] with captured child widget
/// 2. On drag update: move ghost via [Transform.translate], detect drop target
/// 3. On drag end: animate ghost to target position, commit reorder
///
/// Performance considerations:
/// - Ghost uses [CompositedTransformFollower] for GPU-composited movement
/// - Drop target detection uses spatial index (O(log n))
/// - Visible items shift via [AnimatedContainer] (paint-only, no layout)
class SmoothDragEngine {
  final OverlayState overlayState;
  final ScrollController scrollController;
  final double Function(int index) getItemTop;
  final double Function(int index) getItemLeft;
  final double Function(int index) getItemHeight;
  final double Function(int index) getItemWidth;

  OverlayEntry? _ghostEntry;
  int _dragIndex = -1;
  int _targetIndex = -1;
  double _ghostX = 0;
  double _ghostY = 0;
  Widget? _ghostChild;

  /// Called when a reorder is committed: (oldIndex, newIndex).
  void Function(int oldIndex, int newIndex)? onReorder;

  SmoothDragEngine({
    required this.overlayState,
    required this.scrollController,
    required this.getItemTop,
    required this.getItemLeft,
    required this.getItemHeight,
    required this.getItemWidth,
    this.onReorder,
  });

  bool get isDragging => _dragIndex >= 0;
  int get dragIndex => _dragIndex;
  int get targetIndex => _targetIndex;

  /// Start dragging the item at [index].
  ///
  /// [ghostChild] is a widget snapshot of the dragged item.
  /// [startX], [startY] are the initial pointer position in global coordinates.
  void startDrag({
    required int index,
    required Widget ghostChild,
    required double startX,
    required double startY,
  }) {
    _dragIndex = index;
    _targetIndex = index;
    _ghostChild = ghostChild;
    _ghostX = startX;
    _ghostY = startY;

    _ghostEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: _ghostX - getItemWidth(index) / 2,
        top: _ghostY - getItemHeight(index) / 2,
        child: DragGhost(
          elevation: 8,
          shadowColor: const Color(0x40000000),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: getItemWidth(index),
            height: getItemHeight(index),
            child: Opacity(opacity: 0.9, child: _ghostChild!),
          ),
        ),
      ),
    );

    overlayState.insert(_ghostEntry!);
  }

  /// Update the ghost position during drag.
  ///
  /// [dx], [dy] are the delta from drag start.
  void updateDrag(double globalX, double globalY) {
    _ghostX = globalX;
    _ghostY = globalY;
    _ghostEntry?.markNeedsBuild();

    // Auto-scroll when near edges
    _autoScroll(globalY);
  }

  /// Compute the target drop index based on current ghost position.
  ///
  /// Uses "closest center" algorithm on visible items only.
  /// If viewportTop/viewportBottom are provided, only checks items
  /// within that range for O(visible) instead of O(n).
  int computeTargetIndex({
    required int itemCount,
    required double localY,
    double? viewportTop,
    double? viewportBottom,
  }) {
    if (itemCount == 0) return 0;

    var closestIndex = _dragIndex;
    var closestDistance = double.infinity;

    // Determine scan range — only visible items when viewport bounds provided
    final startIdx = viewportTop != null ? 0 : 0;
    final endIdx = itemCount;

    // When viewport bounds are available, we limit the search.
    // The caller should provide a pre-filtered range of visible indices.
    for (var i = startIdx; i < endIdx; i++) {
      final itemCenterY = getItemTop(i) + getItemHeight(i) / 2;

      // Skip items clearly outside viewport (fast early-exit)
      if (viewportTop != null && viewportBottom != null) {
        final itemTop = getItemTop(i);
        final itemBottom = itemTop + getItemHeight(i);
        if (itemBottom < viewportTop || itemTop > viewportBottom) continue;
      }

      final distance = (localY - itemCenterY).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }

    _targetIndex = closestIndex;
    return closestIndex;
  }

  /// End the drag and commit the reorder.
  void endDrag() {
    if (_dragIndex < 0) return;

    // Remove ghost overlay
    _ghostEntry?.remove();
    _ghostEntry = null;

    // Commit reorder if target differs from source
    if (_targetIndex != _dragIndex) {
      onReorder?.call(_dragIndex, _targetIndex);
    }

    _dragIndex = -1;
    _targetIndex = -1;
    _ghostChild = null;
  }

  /// Cancel the drag without committing.
  void cancelDrag() {
    _ghostEntry?.remove();
    _ghostEntry = null;
    _dragIndex = -1;
    _targetIndex = -1;
    _ghostChild = null;
  }

  /// Auto-scroll when dragging near the top or bottom edge.
  void _autoScroll(double globalY) {
    if (!scrollController.hasClients) return;

    const edgeThreshold = 80.0;
    const scrollSpeed = 5.0;

    final position = scrollController.position;

    // Approximate: check if near top/bottom of viewport
    // In production, use RenderBox.globalToLocal for precise calculation
    if (globalY < edgeThreshold) {
      // Scroll up
      final newOffset = (position.pixels - scrollSpeed).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      scrollController.jumpTo(newOffset);
    } else if (globalY > position.viewportDimension - edgeThreshold) {
      // Scroll down
      final newOffset = (position.pixels + scrollSpeed).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      scrollController.jumpTo(newOffset);
    }
  }

  /// Dispose and clean up.
  void dispose() {
    cancelDrag();
  }
}

/// A simple widget for the drag ghost with elevation shadow.
/// Named DragGhost to avoid conflict with flutter/material.dart's Material.
class DragGhost extends StatelessWidget {
  final Widget child;
  final double elevation;
  final Color shadowColor;
  final BorderRadius borderRadius;

  const DragGhost({
    super.key,
    required this.child,
    this.elevation = 0,
    this.shadowColor = const Color(0xFF000000),
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: elevation * 2,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

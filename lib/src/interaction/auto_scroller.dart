import 'package:flutter/widgets.dart';

/// Handles auto-scrolling when dragging near viewport edges.
///
/// When the drag position enters the edge zone, smoothly scrolls
/// the [ScrollController] in that direction.
class AutoScroller {
  final ScrollController scrollController;

  /// Threshold distance from edge to trigger auto-scroll (in pixels).
  final double edgeThreshold;

  /// Maximum scroll speed (pixels per frame at 60 FPS).
  final double maxScrollSpeed;

  /// Acceleration curve: speed increases as pointer gets closer to edge.
  final Curve speedCurve;

  AutoScroller({
    required this.scrollController,
    this.edgeThreshold = 80.0,
    this.maxScrollSpeed = 10.0,
    this.speedCurve = Curves.easeIn,
  });

  /// Compute scroll delta based on pointer position relative to viewport.
  ///
  /// [pointerY] is the pointer's Y position relative to the viewport top.
  /// [viewportHeight] is the height of the visible viewport.
  ///
  /// Returns the scroll delta (positive = scroll down, negative = scroll up).
  double computeScrollDelta(double pointerY, double viewportHeight) {
    if (pointerY < edgeThreshold) {
      // Near top edge — scroll up
      final ratio = 1.0 - (pointerY / edgeThreshold).clamp(0.0, 1.0);
      return -maxScrollSpeed * speedCurve.transform(ratio);
    } else if (pointerY > viewportHeight - edgeThreshold) {
      // Near bottom edge — scroll down
      final distanceFromBottom = viewportHeight - pointerY;
      final ratio = 1.0 - (distanceFromBottom / edgeThreshold).clamp(0.0, 1.0);
      return maxScrollSpeed * speedCurve.transform(ratio);
    }

    return 0;
  }

  /// Apply scroll delta to the controller.
  void applyScrollDelta(double delta) {
    if (!scrollController.hasClients || delta == 0) return;

    final position = scrollController.position;
    final newOffset = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (newOffset != position.pixels) {
      scrollController.jumpTo(newOffset);
    }
  }
}

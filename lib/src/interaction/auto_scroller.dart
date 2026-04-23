import 'package:flutter/widgets.dart';

/// Handles edge-driven auto-scrolling while dragging.
class AutoScroller {
  final ScrollController scrollController;
  final double edgeThreshold;
  final double maxScrollVelocity;
  final Curve velocityCurve;

  AutoScroller({
    required this.scrollController,
    this.edgeThreshold = 72.0,
    this.maxScrollVelocity = 1100.0,
    this.velocityCurve = Curves.easeOutCubic,
  });

  double computeVelocity({
    required double pointerY,
    required double viewportHeight,
  }) {
    if (viewportHeight <= 0) return 0;

    if (pointerY < edgeThreshold) {
      final ratio = 1.0 - (pointerY / edgeThreshold).clamp(0.0, 1.0);
      return -maxScrollVelocity * velocityCurve.transform(ratio);
    }

    final bottomStart = viewportHeight - edgeThreshold;
    if (pointerY > bottomStart) {
      final distanceFromBottom = viewportHeight - pointerY;
      final ratio =
          1.0 - (distanceFromBottom / edgeThreshold).clamp(0.0, 1.0);
      return maxScrollVelocity * velocityCurve.transform(ratio);
    }

    return 0;
  }

  double computeDelta({
    required double pointerY,
    required double viewportHeight,
    required Duration elapsed,
  }) {
    final velocity = computeVelocity(
      pointerY: pointerY,
      viewportHeight: viewportHeight,
    );
    if (velocity == 0) return 0;
    return velocity * (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
  }

  double applyDelta(double delta) {
    if (!scrollController.hasClients || delta == 0) return 0;

    final position = scrollController.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final applied = next - position.pixels;
    if (applied != 0) {
      scrollController.jumpTo(next);
    }
    return applied;
  }
}

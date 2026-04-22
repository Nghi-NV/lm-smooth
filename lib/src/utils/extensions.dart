import 'dart:ui';

/// Extension methods on [Rect] for layout computations.
extension RectExtensions on Rect {
  /// Center point of this rect.
  Offset get centerPoint => Offset(left + width / 2, top + height / 2);

  /// Whether this rect fully contains [other].
  bool fullyContains(Rect other) =>
      left <= other.left &&
      top <= other.top &&
      right >= other.right &&
      bottom >= other.bottom;

  /// Returns a new rect expanded by [amount] on all sides.
  Rect expand(double amount) => Rect.fromLTRB(
    left - amount,
    top - amount,
    right + amount,
    bottom + amount,
  );
}

/// Extension methods on [Offset].
extension OffsetExtensions on Offset {
  /// Squared distance to [other] (avoids sqrt for comparison).
  double squaredDistanceTo(Offset other) {
    final dx2 = dx - other.dx;
    final dy2 = dy - other.dy;
    return dx2 * dx2 + dy2 * dy2;
  }
}

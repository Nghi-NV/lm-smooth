import 'package:flutter/widgets.dart';

import '../core/masonry_layout_engine.dart';

/// Delegate that configures the layout of a [SmoothGrid].
///
/// Provides column count, spacing, padding, and item extent computation.
abstract class SmoothGridDelegate {
  const SmoothGridDelegate();

  /// Creates a delegate with a fixed column count.
  const factory SmoothGridDelegate.count({
    required int crossAxisCount,
    double mainAxisSpacing,
    double crossAxisSpacing,
    EdgeInsets padding,
    required SmoothItemExtentBuilder itemExtentBuilder,
  }) = SmoothGridDelegateWithFixedCount;

  /// The number of columns.
  int get crossAxisCount;

  /// Vertical spacing between items.
  double get mainAxisSpacing;

  /// Horizontal spacing between columns.
  double get crossAxisSpacing;

  /// Padding around the grid.
  EdgeInsets get padding;

  /// Builder that returns the height for each item index.
  ///
  /// **CRITICAL for performance**: This must return pre-computed values.
  /// Do NOT perform widget measurement or expensive computation here.
  SmoothItemExtentBuilder get itemExtentBuilder;

  /// Creates a [MasonryLayoutConfig] for the given viewport width.
  MasonryLayoutConfig toConfig(double viewportWidth) {
    return MasonryLayoutConfig(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      viewportWidth: viewportWidth,
      paddingLeft: padding.left,
      paddingRight: padding.right,
      paddingTop: padding.top,
      paddingBottom: padding.bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmoothGridDelegate &&
          runtimeType == other.runtimeType &&
          crossAxisCount == other.crossAxisCount &&
          mainAxisSpacing == other.mainAxisSpacing &&
          crossAxisSpacing == other.crossAxisSpacing &&
          padding == other.padding;

  @override
  int get hashCode =>
      Object.hash(crossAxisCount, mainAxisSpacing, crossAxisSpacing, padding);
}

/// A [SmoothGridDelegate] with a fixed number of columns.
class SmoothGridDelegateWithFixedCount extends SmoothGridDelegate {
  @override
  final int crossAxisCount;

  @override
  final double mainAxisSpacing;

  @override
  final double crossAxisSpacing;

  @override
  final EdgeInsets padding;

  @override
  final SmoothItemExtentBuilder itemExtentBuilder;

  const SmoothGridDelegateWithFixedCount({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    required this.itemExtentBuilder,
  }) : assert(crossAxisCount > 0, 'crossAxisCount must be > 0');
}

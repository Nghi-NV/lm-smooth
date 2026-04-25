import 'dart:typed_data';

import 'layout_cache.dart';
import 'spatial_index.dart';

/// Callback to provide the height of an item at [index].
///
/// This MUST be pre-computed — do NOT measure widgets here.
/// The width is auto-calculated from column count and spacing.
typedef SmoothItemExtentBuilder = double Function(int index);

/// Configuration for the masonry layout.
class MasonryLayoutConfig {
  /// Number of columns.
  final int crossAxisCount;

  /// Vertical spacing between items.
  final double mainAxisSpacing;

  /// Horizontal spacing between columns.
  final double crossAxisSpacing;

  /// Total available width (viewport width).
  final double viewportWidth;

  /// Padding around the grid.
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;

  const MasonryLayoutConfig({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    required this.viewportWidth,
    this.paddingLeft = 0,
    this.paddingRight = 0,
    this.paddingTop = 0,
    this.paddingBottom = 0,
  }) : assert(crossAxisCount > 0, 'crossAxisCount must be > 0');

  /// Width available for content (excluding padding).
  double get contentWidth => viewportWidth - paddingLeft - paddingRight;

  /// Width of each column.
  double get columnWidth {
    final totalSpacing = crossAxisSpacing * (crossAxisCount - 1);
    return (contentWidth - totalSpacing) / crossAxisCount;
  }

  /// X offset for a given column index.
  double columnX(int column) {
    return paddingLeft + column * (columnWidth + crossAxisSpacing);
  }

  /// Create a copy with some fields replaced.
  MasonryLayoutConfig copyWith({
    int? crossAxisCount,
    double? mainAxisSpacing,
    double? crossAxisSpacing,
    double? viewportWidth,
    double? paddingLeft,
    double? paddingRight,
    double? paddingTop,
    double? paddingBottom,
  }) {
    return MasonryLayoutConfig(
      crossAxisCount: crossAxisCount ?? this.crossAxisCount,
      mainAxisSpacing: mainAxisSpacing ?? this.mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing ?? this.crossAxisSpacing,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      paddingLeft: paddingLeft ?? this.paddingLeft,
      paddingRight: paddingRight ?? this.paddingRight,
      paddingTop: paddingTop ?? this.paddingTop,
      paddingBottom: paddingBottom ?? this.paddingBottom,
    );
  }
}

/// Masonry layout engine using the "Shortest Column First" algorithm.
///
/// Time complexity: O(n) for full layout, O(k) for incremental.
/// Space complexity: O(n) via [LayoutCache] chunks.
///
/// This engine is designed to be:
/// 1. Run on the main thread for ≤100K items
/// 2. Run on an Isolate for >100K items (via [computeLayout])
class MasonryLayoutEngine {
  final LayoutCache cache;
  final SpatialIndex spatialIndex;

  MasonryLayoutEngine({LayoutCache? cache, SpatialIndex? spatialIndex})
      : cache = cache ?? LayoutCache(),
        spatialIndex = spatialIndex ?? SpatialIndex(cache ?? LayoutCache());

  /// Compute the full layout for [itemCount] items.
  ///
  /// [itemExtentBuilder] provides the height of each item.
  /// [config] provides column count, spacing, and viewport width.
  ///
  /// Returns the total scroll height.
  double computeLayout({
    required int itemCount,
    required SmoothItemExtentBuilder itemExtentBuilder,
    required MasonryLayoutConfig config,
  }) {
    cache.clear();
    if (itemCount == 0) return 0;

    final columnCount = config.crossAxisCount;
    final columnWidth = config.columnWidth;
    final mainAxisSpacing = config.mainAxisSpacing;

    // Pre-compute column X positions — avoid recomputing per item
    final columnXs = List<double>.generate(
      columnCount,
      (c) => config.columnX(c),
    );

    // Track the current height of each column
    final columnHeights = List<double>.filled(columnCount, config.paddingTop);

    for (var i = 0; i < itemCount; i++) {
      // Find the shortest column
      var shortestCol = 0;
      var minHeight = columnHeights[0];
      for (var c = 1; c < columnCount; c++) {
        if (columnHeights[c] < minHeight) {
          minHeight = columnHeights[c];
          shortestCol = c;
        }
      }

      final x = columnXs[shortestCol];
      final y = columnHeights[shortestCol];
      final h = itemExtentBuilder(i);

      cache.setRect(i, x, y, columnWidth, h);

      // Update column height
      columnHeights[shortestCol] = y + h + mainAxisSpacing;
    }

    // Total height = max column height - last spacing + bottom padding
    var maxHeight = 0.0;
    for (var c = 0; c < columnCount; c++) {
      // Remove trailing spacing
      final colHeight = columnHeights[c] > config.paddingTop
          ? columnHeights[c] - mainAxisSpacing
          : columnHeights[c];
      if (colHeight > maxHeight) maxHeight = colHeight;
    }

    final totalHeight = maxHeight + config.paddingBottom;

    // Rebuild spatial index
    spatialIndex.invalidate();
    spatialIndex.rebuild();

    return totalHeight;
  }

  /// Incrementally recompute layout starting from [startIndex].
  ///
  /// Use this when items are inserted/removed/reordered.
  /// Items before [startIndex] keep their positions.
  double recomputeFrom({
    required int startIndex,
    required int itemCount,
    required SmoothItemExtentBuilder itemExtentBuilder,
    required MasonryLayoutConfig config,
  }) {
    if (startIndex <= 0) {
      return computeLayout(
        itemCount: itemCount,
        itemExtentBuilder: itemExtentBuilder,
        config: config,
      );
    }

    cache.invalidateFrom(startIndex);

    final columnCount = config.crossAxisCount;
    final columnWidth = config.columnWidth;
    final mainAxisSpacing = config.mainAxisSpacing;

    // Pre-compute column X positions
    final columnXs = List<double>.generate(
      columnCount,
      (c) => config.columnX(c),
    );

    // Reconstruct column heights from existing layout (before startIndex)
    final columnHeights = List<double>.filled(columnCount, config.paddingTop);

    // Scan existing items to find column heights — zero-allocation
    for (var i = 0; i < startIndex; i++) {
      final r = cache.getRaw(i);
      final colIdx = _getColumnForX(r.x, config);
      final bottom = r.y + r.h + mainAxisSpacing;
      if (bottom > columnHeights[colIdx]) {
        columnHeights[colIdx] = bottom;
      }
    }

    // Continue layout from startIndex
    for (var i = startIndex; i < itemCount; i++) {
      var shortestCol = 0;
      var minHeight = columnHeights[0];
      for (var c = 1; c < columnCount; c++) {
        if (columnHeights[c] < minHeight) {
          minHeight = columnHeights[c];
          shortestCol = c;
        }
      }

      final x = columnXs[shortestCol];
      final y = columnHeights[shortestCol];
      final h = itemExtentBuilder(i);

      cache.setRect(i, x, y, columnWidth, h);
      columnHeights[shortestCol] = y + h + mainAxisSpacing;
    }

    var maxHeight = 0.0;
    for (var c = 0; c < columnCount; c++) {
      final colHeight = columnHeights[c] > config.paddingTop
          ? columnHeights[c] - mainAxisSpacing
          : columnHeights[c];
      if (colHeight > maxHeight) maxHeight = colHeight;
    }

    final totalHeight = maxHeight + config.paddingBottom;

    spatialIndex.invalidate();
    spatialIndex.rebuild();

    return totalHeight;
  }

  /// Get the column index for a given X position.
  int _getColumnForX(double x, MasonryLayoutConfig config) {
    final relativeX = x - config.paddingLeft;
    final colWidth = config.columnWidth + config.crossAxisSpacing;
    return (relativeX / colWidth).floor().clamp(0, config.crossAxisCount - 1);
  }
}

/// Static function for Isolate computation.
///
/// Takes a flat parameter map and returns a [Float64List] of layout rects.
/// This avoids sending complex objects across Isolate boundaries.
class IsolateLayoutParams {
  final int itemCount;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double viewportWidth;
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;

  /// Pre-computed item heights as a flat Float64List.
  final List<double> itemHeights;

  const IsolateLayoutParams({
    required this.itemCount,
    required this.crossAxisCount,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.viewportWidth,
    required this.itemHeights,
    this.paddingLeft = 0,
    this.paddingRight = 0,
    this.paddingTop = 0,
    this.paddingBottom = 0,
  });
}

/// Compute layout in an Isolate-friendly way.
///
/// Returns a flat [Float64List] where every 4 values = (x, y, w, h).
/// Transfer via [TransferableTypedData] for zero-copy.
Float64List computeLayoutIsolate(IsolateLayoutParams params) {
  final columnCount = params.crossAxisCount;
  final contentWidth =
      params.viewportWidth - params.paddingLeft - params.paddingRight;
  final totalSpacing = params.crossAxisSpacing * (columnCount - 1);
  final columnWidth = (contentWidth - totalSpacing) / columnCount;

  double columnX(int column) {
    return params.paddingLeft +
        column * (columnWidth + params.crossAxisSpacing);
  }

  final columnHeights = List<double>.filled(columnCount, params.paddingTop);
  final result = Float64List(params.itemCount * 4);

  for (var i = 0; i < params.itemCount; i++) {
    // Find shortest column
    var shortestCol = 0;
    var minHeight = columnHeights[0];
    for (var c = 1; c < columnCount; c++) {
      if (columnHeights[c] < minHeight) {
        minHeight = columnHeights[c];
        shortestCol = c;
      }
    }

    final x = columnX(shortestCol);
    final y = columnHeights[shortestCol];
    final h = params.itemHeights[i];

    final offset = i * 4;
    result[offset] = x;
    result[offset + 1] = y;
    result[offset + 2] = columnWidth;
    result[offset + 3] = h;

    columnHeights[shortestCol] = y + h + params.mainAxisSpacing;
  }

  return result;
}

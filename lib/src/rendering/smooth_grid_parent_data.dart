import 'package:flutter/rendering.dart';

/// Custom parent data for [RenderSmoothGrid] children.
///
/// Stores the column index and item index for each child,
/// enabling efficient hit testing and drag-drop operations.
class SmoothGridParentData extends SliverMultiBoxAdaptorParentData {
  /// The column this child is placed in.
  int column = 0;

  /// The cross-axis offset (x position).
  double crossAxisOffset = 0;

  @override
  String toString() => 'SmoothGridParentData(index=$index, column=$column, '
      'crossAxisOffset=$crossAxisOffset, layoutOffset=$layoutOffset)';
}

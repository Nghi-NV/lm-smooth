import 'package:flutter/widgets.dart';

/// Axis-neutral geometry for virtualized smooth views.
class SmoothAxisGeometry {
  final double mainOffset;
  final double crossOffset;
  final double mainExtent;
  final double crossExtent;

  const SmoothAxisGeometry({
    required this.mainOffset,
    required this.crossOffset,
    required this.mainExtent,
    required this.crossExtent,
  });

  Rect toRect(Axis axis) {
    return axis == Axis.vertical
        ? Rect.fromLTWH(crossOffset, mainOffset, crossExtent, mainExtent)
        : Rect.fromLTWH(mainOffset, crossOffset, mainExtent, crossExtent);
  }

  static SmoothAxisGeometry fromRect(Rect rect, Axis axis) {
    return axis == Axis.vertical
        ? SmoothAxisGeometry(
            mainOffset: rect.top,
            crossOffset: rect.left,
            mainExtent: rect.height,
            crossExtent: rect.width,
          )
        : SmoothAxisGeometry(
            mainOffset: rect.left,
            crossOffset: rect.top,
            mainExtent: rect.width,
            crossExtent: rect.height,
          );
  }
}

/// Visible range query result in axis-neutral coordinates.
class SmoothViewportQuery {
  final double mainStart;
  final double mainEnd;
  final double crossStart;
  final double crossEnd;

  const SmoothViewportQuery({
    required this.mainStart,
    required this.mainEnd,
    this.crossStart = 0,
    this.crossEnd = double.infinity,
  });
}

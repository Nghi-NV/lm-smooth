import 'package:flutter/widgets.dart';

/// Runtime configuration for [SmoothGrid] reordering.
class SmoothReorderConfig {
  final Duration longPressDelay;
  final double liftScale;
  final double ghostOpacity;
  final Duration settleDuration;
  final Duration translateDuration;
  final double edgeScrollZone;
  final double maxAutoScrollVelocity;
  final double collisionHysteresis;
  final Curve translateCurve;
  final Curve settleCurve;

  const SmoothReorderConfig({
    this.longPressDelay = const Duration(milliseconds: 220),
    this.liftScale = 1.03,
    this.ghostOpacity = 0.96,
    this.settleDuration = const Duration(milliseconds: 180),
    this.translateDuration = const Duration(milliseconds: 180),
    this.edgeScrollZone = 72.0,
    this.maxAutoScrollVelocity = 1100.0,
    this.collisionHysteresis = 10.0,
    this.translateCurve = Curves.fastOutSlowIn,
    this.settleCurve = Curves.fastOutSlowIn,
  });

  double resolveEdgeScrollZone(double viewportHeight) {
    final proportional = viewportHeight * 0.12;
    return proportional > edgeScrollZone ? proportional : edgeScrollZone;
  }
}

/// Lightweight immutable snapshot of the active drag session.
class SmoothDragSession {
  final int dragIndex;
  final int targetIndex;
  final Offset pointerGlobal;
  final Offset pointerLocal;
  final Rect dragRect;
  final Map<int, Offset> previewOffsets;

  const SmoothDragSession({
    required this.dragIndex,
    required this.targetIndex,
    required this.pointerGlobal,
    required this.pointerLocal,
    required this.dragRect,
    required this.previewOffsets,
  });
}

/// Computes reorder preview state for masonry/grid items without mutating data.
class SmoothDragEngine {
  final double collisionHysteresis;

  int _dragIndex = -1;
  int _targetIndex = -1;
  Offset _pointerGlobal = Offset.zero;
  Offset _pointerLocal = Offset.zero;
  Rect _dragRect = Rect.zero;
  Map<int, Offset> _previewOffsets = const {};

  SmoothDragEngine({this.collisionHysteresis = 10.0});

  bool get isDragging => _dragIndex >= 0;
  int get dragIndex => _dragIndex;
  int get targetIndex => _targetIndex;
  Offset get pointerGlobal => _pointerGlobal;
  Offset get pointerLocal => _pointerLocal;
  Rect get dragRect => _dragRect;
  Map<int, Offset> get previewOffsets => _previewOffsets;

  void startDrag({
    required int index,
    required Rect dragRect,
    required Offset pointerGlobal,
    required Offset pointerLocal,
  }) {
    _dragIndex = index;
    _targetIndex = index;
    _dragRect = dragRect;
    _pointerGlobal = pointerGlobal;
    _pointerLocal = pointerLocal;
    _previewOffsets = const {};
  }

  void updatePointer({
    required Offset pointerGlobal,
    required Offset pointerLocal,
    double? draggedTop,
  }) {
    _pointerGlobal = pointerGlobal;
    _pointerLocal = pointerLocal;
    if (draggedTop != null) {
      _dragRect = Rect.fromLTWH(
        _dragRect.left,
        draggedTop,
        _dragRect.width,
        _dragRect.height,
      );
    }
  }

  int computeTargetIndex({
    required List<int> candidateIndices,
    required Rect Function(int index) getItemRect,
    required double viewportTop,
    required double viewportBottom,
  }) {
    if (!isDragging) return -1;
    if (candidateIndices.isEmpty) return _targetIndex;

    final pointer = _pointerLocal;
    final previousTarget = _targetIndex;
    var bestIndex = _targetIndex;
    var bestScore = double.infinity;

    for (final index in candidateIndices) {
      if (index == _dragIndex) continue;

      final rect = getItemRect(index);
      if (rect.bottom < viewportTop || rect.top > viewportBottom) {
        continue;
      }

      final center = rect.center;
      final dy = (pointer.dy - center.dy).abs();
      final dx = (pointer.dx - center.dx).abs();
      final score = dy + (dx * 0.35);
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }

    if (bestIndex == _targetIndex) {
      return _targetIndex;
    }

    if (previousTarget >= 0 && previousTarget != _dragIndex) {
      final currentRect = getItemRect(previousTarget);
      final currentCenter = currentRect.center;
      final currentScore =
          (pointer.dy - currentCenter.dy).abs() +
          ((pointer.dx - currentCenter.dx).abs() * 0.35);
      if ((currentScore - bestScore).abs() < collisionHysteresis) {
        return _targetIndex;
      }
    }

    _targetIndex = bestIndex.clamp(0, candidateIndices.last);
    return _targetIndex;
  }

  Map<int, Offset> buildPreviewOffsets({
    required Iterable<int> indices,
    required Rect Function(int index) getItemRect,
  }) {
    if (!isDragging) return const {};
    if (_targetIndex == _dragIndex) {
      _previewOffsets = const {};
      return _previewOffsets;
    }

    final offsets = <int, Offset>{};
    final visible = indices.toSet();
    if (_dragIndex < _targetIndex) {
      for (var i = _dragIndex + 1; i <= _targetIndex; i++) {
        if (!visible.contains(i)) continue;
        offsets[i] = getItemRect(i - 1).topLeft - getItemRect(i).topLeft;
      }
    } else {
      for (var i = _targetIndex; i < _dragIndex; i++) {
        if (!visible.contains(i)) continue;
        offsets[i] = getItemRect(i + 1).topLeft - getItemRect(i).topLeft;
      }
    }

    _previewOffsets = offsets;
    return offsets;
  }

  SmoothDragSession snapshot() {
    return SmoothDragSession(
      dragIndex: _dragIndex,
      targetIndex: _targetIndex,
      pointerGlobal: _pointerGlobal,
      pointerLocal: _pointerLocal,
      dragRect: _dragRect,
      previewOffsets: _previewOffsets,
    );
  }

  void reset() {
    _dragIndex = -1;
    _targetIndex = -1;
    _pointerGlobal = Offset.zero;
    _pointerLocal = Offset.zero;
    _dragRect = Rect.zero;
    _previewOffsets = const {};
  }
}

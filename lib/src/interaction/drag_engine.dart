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
    this.translateDuration = const Duration(milliseconds: 90),
    this.edgeScrollZone = 72.0,
    this.maxAutoScrollVelocity = 1100.0,
    this.collisionHysteresis = 10.0,
    this.translateCurve = Curves.easeOutCubic,
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
  Offset _pointerDelta = Offset.zero;
  Rect _dragRect = Rect.zero;
  Map<int, Offset> _previewOffsets = const {};

  SmoothDragEngine({this.collisionHysteresis = 10.0});

  bool get isDragging => _dragIndex >= 0;
  int get dragIndex => _dragIndex;
  int get targetIndex => _targetIndex;
  Offset get pointerGlobal => _pointerGlobal;
  Offset get pointerLocal => _pointerLocal;
  Offset get pointerDelta => _pointerDelta;
  Rect get dragRect => _dragRect;
  Map<int, Offset> get previewOffsets => _previewOffsets;

  void setTargetIndex(int targetIndex, {required int maxTargetIndex}) {
    if (!isDragging) return;
    _targetIndex = targetIndex.clamp(0, maxTargetIndex);
  }

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
    _pointerDelta = Offset.zero;
    _previewOffsets = const {};
  }

  void updatePointer({
    required Offset pointerGlobal,
    required Offset pointerLocal,
    Offset? draggedTopLeft,
  }) {
    _pointerDelta = pointerLocal - _pointerLocal;
    _pointerGlobal = pointerGlobal;
    _pointerLocal = pointerLocal;
    if (draggedTopLeft != null) {
      _dragRect = Rect.fromLTWH(
        draggedTopLeft.dx,
        draggedTopLeft.dy,
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
    required int maxTargetIndex,
  }) {
    if (!isDragging) return -1;
    if (candidateIndices.isEmpty) return _targetIndex;

    final pointer = _pointerLocal;
    final draggedRect = _dragRect;
    final previousTarget = _targetIndex;
    var bestIndex = _targetIndex;
    Rect? bestRect;
    var bestScore = double.infinity;
    var bestOverlapRatio = -1.0;
    var hitContainedItem = false;
    var hitOverlappingItem = false;

    for (final index in candidateIndices) {
      if (index == _dragIndex) continue;

      final rect = getItemRect(index);
      if (rect.bottom < viewportTop || rect.top > viewportBottom) {
        continue;
      }

      final containsPointer = rect.contains(pointer);
      final overlapsDraggedRect = draggedRect.overlaps(rect);
      final intersection =
          overlapsDraggedRect ? draggedRect.intersect(rect) : Rect.zero;
      final overlapArea = intersection.width > 0 && intersection.height > 0
          ? intersection.width * intersection.height
          : 0.0;
      final minArea = _dragRectArea(draggedRect, rect);
      final overlapRatio = minArea > 0 ? overlapArea / minArea : 0.0;
      final center = rect.center;
      final dy = (pointer.dy - center.dy).abs();
      final dx = (pointer.dx - center.dx).abs();
      final score = overlapsDraggedRect
          ? (dy * 0.45) + (dx * 0.25)
          : containsPointer
              ? (dy + dx * 0.15)
              : (dy * 0.9) + (dx * 0.75);

      if (overlapsDraggedRect && !hitOverlappingItem) {
        bestScore = double.infinity;
        bestOverlapRatio = -1.0;
        hitOverlappingItem = true;
        hitContainedItem = false;
      }
      if (containsPointer && !hitContainedItem && !hitOverlappingItem) {
        bestScore = double.infinity;
        hitContainedItem = true;
      }
      if (hitOverlappingItem && !overlapsDraggedRect) {
        continue;
      }
      if (hitContainedItem && !containsPointer) {
        continue;
      }
      final overlapWins = overlapsDraggedRect &&
          (overlapRatio > bestOverlapRatio + 0.08 ||
              ((overlapRatio - bestOverlapRatio).abs() <= 0.08 &&
                  score < bestScore));
      final nonOverlapWins = !overlapsDraggedRect && score < bestScore;
      if (overlapWins || nonOverlapWins) {
        bestOverlapRatio = overlapRatio;
        bestScore = score;
        bestIndex = index;
        bestRect = rect;
      }
    }

    if (bestRect == null) {
      return _targetIndex;
    }

    final center = bestRect.center;
    final splitPosition = center.dy;
    final pointerPosition = pointer.dy;
    final movementDelta = _pointerDelta.dy;
    final beforeTarget = bestIndex;
    final afterTarget = (bestIndex + 1).clamp(0, maxTargetIndex);
    final deadZone = collisionHysteresis;
    final distanceFromSplit = pointerPosition - splitPosition;
    int candidateTarget;
    if (distanceFromSplit.abs() <= deadZone &&
        movementDelta.abs() > 0.5 &&
        beforeTarget != afterTarget) {
      candidateTarget = movementDelta > 0 ? afterTarget : beforeTarget;
    } else {
      candidateTarget = distanceFromSplit > 0 ? afterTarget : beforeTarget;
    }

    final clampedTarget = candidateTarget.clamp(0, maxTargetIndex);

    final nearSplitBoundary = distanceFromSplit.abs() <= deadZone &&
        (_targetIndex == beforeTarget || _targetIndex == afterTarget);
    if (nearSplitBoundary) {
      return _targetIndex;
    }

    if (clampedTarget == _targetIndex) {
      return _targetIndex;
    }

    if (previousTarget >= 0 && previousTarget != _dragIndex) {
      final candidateScore = _targetScore(
        targetIndex: clampedTarget,
        pointer: pointer,
        getItemRect: getItemRect,
        maxTargetIndex: maxTargetIndex,
      );
      final currentScore = _targetScore(
        targetIndex: previousTarget,
        pointer: pointer,
        getItemRect: getItemRect,
        maxTargetIndex: maxTargetIndex,
      );
      if ((currentScore - candidateScore).abs() <= collisionHysteresis) {
        return _targetIndex;
      }
    }

    _targetIndex = clampedTarget;
    return _targetIndex;
  }

  double _dragRectArea(Rect a, Rect b) {
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    return aArea < bArea ? aArea : bArea;
  }

  double _targetScore({
    required int targetIndex,
    required Offset pointer,
    required Rect Function(int index) getItemRect,
    required int maxTargetIndex,
  }) {
    if (maxTargetIndex <= 0) {
      return 0;
    }

    if (targetIndex >= maxTargetIndex) {
      final rect = getItemRect(maxTargetIndex - 1);
      final anchor = Offset(rect.center.dx, rect.bottom);
      return (pointer.dy - anchor.dy).abs() +
          ((pointer.dx - anchor.dx).abs() * 0.35);
    }

    final rect = getItemRect(targetIndex.clamp(0, maxTargetIndex - 1));
    final center = rect.center;
    return (pointer.dy - center.dy).abs() +
        ((pointer.dx - center.dx).abs() * 0.35);
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
      for (var i = _dragIndex + 1; i < _targetIndex; i++) {
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

  Rect? previewDragRect({
    required Rect Function(int index) getItemRect,
    required int itemCount,
  }) {
    if (!isDragging || itemCount <= 0) return null;
    if (_targetIndex == _dragIndex) {
      return getItemRect(_dragIndex);
    }

    final previewIndex = _dragIndex < _targetIndex
        ? (_targetIndex - 1).clamp(0, itemCount - 1)
        : _targetIndex.clamp(0, itemCount - 1);
    return getItemRect(previewIndex);
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

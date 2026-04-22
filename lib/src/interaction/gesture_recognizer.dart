/// Gesture state machine states.
enum GestureState {
  /// No active gesture.
  idle,

  /// Pointer is down, waiting to determine gesture type.
  pressStarted,

  /// Long press timer exceeded threshold but pointer still down.
  longPressStarted,

  /// Drag detected (pointer moved beyond slop).
  dragging,
}

/// Configuration for gesture recognition thresholds.
class GestureConfig {
  /// Maximum time for a tap (pointer down → up).
  final Duration tapTimeout;

  /// Minimum hold time for long press.
  final Duration longPressTimeout;

  /// Minimum movement distance to start a drag (in logical pixels).
  final double dragSlop;

  const GestureConfig({
    this.tapTimeout = const Duration(milliseconds: 150),
    this.longPressTimeout = const Duration(milliseconds: 500),
    this.dragSlop = 18.0,
  });
}

/// Callback types for gesture events.
typedef OnItemTap = void Function(int index);
typedef OnItemLongPress = void Function(int index);
typedef OnDragStart = void Function(int index, double dx, double dy);
typedef OnDragUpdate = void Function(int index, double dx, double dy);
typedef OnDragEnd = void Function(int index);

/// FSM-based gesture recognizer for smooth grid items.
///
/// Detects tap, long press, and drag gestures using a finite state machine.
/// Hit testing is performed via callback to the spatial index.
///
/// ```
/// States:
///   Idle → PressStarted (onPointerDown)
///   PressStarted → Idle (pointer up < tapTimeout → tap callback)
///   PressStarted → LongPressStarted (hold ≥ longPressTimeout)
///   PressStarted → Dragging (moved > dragSlop)
///   LongPressStarted → Idle (pointer up → longPress callback)
///   LongPressStarted → Dragging (moved > dragSlop)
///   Dragging → Idle (pointer up → dragEnd callback)
/// ```
class SmoothGestureRecognizer {
  final GestureConfig config;

  GestureState _state = GestureState.idle;
  int _activeIndex = -1;
  double _startX = 0;
  double _startY = 0;
  DateTime? _pressStartTime;

  // Callbacks
  OnItemTap? onTap;
  OnItemLongPress? onLongPress;
  OnDragStart? onDragStart;
  OnDragUpdate? onDragUpdate;
  OnDragEnd? onDragEnd;

  /// Hit test function: (x, y) → item index, or -1 if no hit.
  int Function(double x, double y)? hitTest;

  SmoothGestureRecognizer({
    this.config = const GestureConfig(),
    this.onTap,
    this.onLongPress,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.hitTest,
  });

  GestureState get state => _state;
  int get activeIndex => _activeIndex;

  /// Handle pointer down event.
  void handlePointerDown(double x, double y) {
    if (_state != GestureState.idle) return;

    final index = hitTest?.call(x, y) ?? -1;
    if (index < 0) return;

    _state = GestureState.pressStarted;
    _activeIndex = index;
    _startX = x;
    _startY = y;
    _pressStartTime = DateTime.now();
  }

  /// Handle pointer move event.
  void handlePointerMove(double x, double y) {
    if (_state == GestureState.idle) return;

    final dx = x - _startX;
    final dy = y - _startY;
    final distance = dx * dx + dy * dy; // squared to avoid sqrt

    if (_state == GestureState.pressStarted ||
        _state == GestureState.longPressStarted) {
      // Check if moved beyond drag threshold
      if (distance > config.dragSlop * config.dragSlop) {
        _state = GestureState.dragging;
        onDragStart?.call(_activeIndex, dx, dy);
        return;
      }
    }

    if (_state == GestureState.dragging) {
      onDragUpdate?.call(_activeIndex, dx, dy);
    }
  }

  /// Handle pointer up event.
  void handlePointerUp(double x, double y) {
    switch (_state) {
      case GestureState.pressStarted:
        // Short tap
        onTap?.call(_activeIndex);
        break;

      case GestureState.longPressStarted:
        // Long press completed
        onLongPress?.call(_activeIndex);
        break;

      case GestureState.dragging:
        // Drag ended
        onDragEnd?.call(_activeIndex);
        break;

      case GestureState.idle:
        break;
    }

    _reset();
  }

  /// Handle pointer cancel (e.g., scroll took over).
  void handlePointerCancel() {
    if (_state == GestureState.dragging) {
      onDragEnd?.call(_activeIndex);
    }
    _reset();
  }

  /// Called periodically (e.g., from a timer) to check long press timeout.
  void checkLongPress() {
    if (_state != GestureState.pressStarted) return;
    if (_pressStartTime == null) return;

    final elapsed = DateTime.now().difference(_pressStartTime!);
    if (elapsed >= config.longPressTimeout) {
      _state = GestureState.longPressStarted;
      // Optionally trigger haptic feedback here
    }
  }

  void _reset() {
    _state = GestureState.idle;
    _activeIndex = -1;
    _startX = 0;
    _startY = 0;
    _pressStartTime = null;
  }

  /// Dispose and reset state.
  void dispose() {
    _reset();
  }
}

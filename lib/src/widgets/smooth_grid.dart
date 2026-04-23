import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../interaction/auto_scroller.dart';
import '../interaction/drag_engine.dart';
import '../rendering/render_smooth_grid.dart';
import 'smooth_grid_delegate.dart';

typedef SmoothReorderStartCallback = void Function(int index);
typedef SmoothReorderUpdateCallback = void Function(int oldIndex, int newIndex);
typedef SmoothReorderEndCallback = void Function(int oldIndex, int newIndex);

/// A high-performance staggered/masonry grid view.
class SmoothGrid extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter? findChildIndexCallback;
  final SmoothGridDelegate delegate;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool reorderable;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onLongPress;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final SmoothReorderConfig? reorderConfig;
  final SmoothReorderStartCallback? onReorderStart;
  final SmoothReorderUpdateCallback? onReorderUpdate;
  final SmoothReorderEndCallback? onReorderEnd;
  final bool addRepaintBoundaries;
  final bool addAutomaticKeepAlives;
  final double? cacheExtent;
  final Axis scrollDirection;
  final bool shrinkWrap;
  final bool? useIsolate;

  const SmoothGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    required this.delegate,
    this.controller,
    this.physics,
    this.reorderable = false,
    this.onTap,
    this.onLongPress,
    this.onReorder,
    this.reorderConfig,
    this.onReorderStart,
    this.onReorderUpdate,
    this.onReorderEnd,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = false,
    this.cacheExtent,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = false,
    this.useIsolate,
  }) : assert(
         !reorderable || onReorder != null,
         'onReorder must be provided when reorderable is true',
       );

  @override
  State<SmoothGrid> createState() => _SmoothGridState();
}

class _SmoothGridState extends State<SmoothGrid> with TickerProviderStateMixin {
  static const SpringDescription _previewSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 36,
  );

  final GlobalKey _scrollViewKey = GlobalKey();
  final GlobalKey _sliverKey = GlobalKey();

  late final AnimationController _previewController;
  late final AnimationController _settleController;

  ScrollController? _ownedController;
  Ticker? _autoScrollTicker;
  Duration? _lastAutoScrollTick;
  OverlayEntry? _ghostEntry;

  SmoothDragEngine? _dragEngine;
  AutoScroller? _autoScroller;

  Map<int, Offset> _previewFrom = const {};
  Map<int, Offset> _previewTo = const {};
  Rect _ghostRect = Rect.zero;
  Rect _settleFromRect = Rect.zero;
  Rect _settleToRect = Rect.zero;
  Offset _latestGlobal = Offset.zero;
  Widget? _ghostChild;
  bool _dropCommitted = false;
  int _lastPreviewTarget = -1;
  int _lastPreviewFirstVisible = -1;
  int _lastPreviewLastVisible = -1;

  ScrollController get _scrollController => widget.controller ?? _ownedController!;
  SmoothReorderConfig get _reorderConfig =>
      widget.reorderConfig ?? const SmoothReorderConfig();

  @override
  void initState() {
    super.initState();
    _previewController =
        AnimationController(vsync: this)..addListener(_applyPreviewAnimation);
    _settleController =
        AnimationController(vsync: this)..addListener(_updateGhostFromSettle);
    if (widget.controller == null) {
      _ownedController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant SmoothGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _ownedController?.dispose();
      _ownedController = widget.controller == null ? ScrollController() : null;
    }

    if (!widget.reorderable && _dragEngine != null) {
      _cancelActiveDrag();
    }
  }

  @override
  void dispose() {
    _ghostEntry?.remove();
    _autoScrollTicker?.dispose();
    _previewController.dispose();
    _settleController.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      shrinkWrap: widget.shrinkWrap,
      cacheExtent: widget.cacheExtent,
      slivers: [
        _SmoothGridSliver(
          key: _sliverKey,
          itemCount: widget.itemCount,
          itemBuilder: _buildItem,
          findChildIndexCallback: widget.findChildIndexCallback,
          gridDelegate: widget.delegate,
          addRepaintBoundaries: widget.addRepaintBoundaries,
          addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
          useIsolate: widget.useIsolate,
        ),
      ],
    );

    if (!widget.reorderable) {
      return scrollView;
    }

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        if (widget.onTap != null)
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(debugOwner: this),
                (instance) {
                  instance.onTapUp = (details) {
                    final index = _resolveIndexFromGlobalPosition(
                      details.globalPosition,
                    );
                    if (index >= 0) {
                      widget.onTap?.call(index);
                    }
                  };
                },
              ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                debugOwner: this,
                duration: _reorderConfig.longPressDelay,
              ),
              (instance) {
                instance.onLongPressStart = (details) {
                  final index = _resolveIndexFromGlobalPosition(
                    details.globalPosition,
                  );
                  if (index >= 0) {
                    _startDrag(index, details.globalPosition);
                  }
                };
                instance.onLongPressMoveUpdate = (details) {
                  _handleDragMove(details.globalPosition);
                };
                instance.onLongPressEnd = (_) => _finishDrag();
                instance.onLongPressCancel = _cancelActiveDrag;
              },
            ),
      },
      child: scrollView,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final child = widget.itemBuilder(context, index);

    if (!widget.reorderable) {
      if (widget.onTap == null && widget.onLongPress == null) {
        return child;
      }
      return GestureDetector(
        key: child.key,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap != null ? () => widget.onTap!(index) : null,
        onLongPress: widget.onLongPress != null
            ? () => widget.onLongPress!(index)
            : null,
        child: child,
      );
    }

    return child;
  }

  RenderSmoothGrid? get _renderGrid {
    final object = _sliverKey.currentContext?.findRenderObject();
    return object is RenderSmoothGrid ? object : null;
  }

  RenderBox? get _scrollViewBox {
    final object = _scrollViewKey.currentContext?.findRenderObject();
    return object is RenderBox ? object : null;
  }

  int _resolveIndexFromGlobalPosition(Offset globalPosition) {
    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (renderGrid == null || viewportBox == null) return -1;

    final viewportOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final pointerLocal = viewportBox.globalToLocal(globalPosition) +
        Offset(0, viewportOffset);
    return renderGrid.getItemIndexAt(pointerLocal);
  }

  void _startDrag(int index, Offset globalPosition) {
    if (!widget.reorderable || widget.scrollDirection != Axis.vertical) return;

    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (renderGrid == null || viewportBox == null || index >= widget.itemCount) {
      return;
    }

    final itemRect = renderGrid.getItemRect(index);
    final viewportOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final viewportRect = Rect.fromLTWH(
      itemRect.left,
      itemRect.top - viewportOffset,
      itemRect.width,
      itemRect.height,
    );
    final globalTopLeft = viewportBox.localToGlobal(viewportRect.topLeft);
    final globalRect = globalTopLeft & viewportRect.size;
    final pointerLocal = viewportBox.globalToLocal(globalPosition) +
        Offset(0, viewportOffset);

    _dragEngine = SmoothDragEngine(
      collisionHysteresis: _reorderConfig.collisionHysteresis,
    )..startDrag(
        index: index,
        dragRect: itemRect,
        pointerGlobal: globalPosition,
        pointerLocal: pointerLocal,
      );

    _autoScroller = AutoScroller(
      scrollController: _scrollController,
      edgeThreshold: _reorderConfig.resolveEdgeScrollZone(viewportBox.size.height),
      maxScrollVelocity: _reorderConfig.maxAutoScrollVelocity,
    );

    _ghostRect = globalRect;
    _latestGlobal = globalPosition;
    _ghostChild = IgnorePointer(
      child: SizedBox(
        width: globalRect.width,
        height: globalRect.height,
        child: Opacity(
          opacity: _reorderConfig.ghostOpacity,
          child: widget.itemBuilder(context, index),
        ),
      ),
    );

    _ensureGhostOverlay();
    _previewFrom = const {};
    _previewTo = const {};
    _lastPreviewTarget = index;
    _lastPreviewFirstVisible = -1;
    _lastPreviewLastVisible = -1;
    renderGrid.setPreviewState(offsets: const {}, hiddenIndex: index);
    widget.onReorderStart?.call(index);
    _startAutoScrollTicker();
  }

  void _ensureGhostOverlay() {
    _ghostEntry?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_ghostChild == null) return;

    _ghostEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: _ghostRect.left,
        top: _ghostRect.top,
        width: _ghostRect.width,
        height: _ghostRect.height,
        child: _GhostFrame(
          scale: _reorderConfig.liftScale,
          child: _ghostChild!,
        ),
      ),
    );
    overlay.insert(_ghostEntry!);
  }

  void _handleDragMove(Offset globalPosition) {
    if (_dragEngine == null) return;
    _latestGlobal = globalPosition;
    _updateFromPointer(globalPosition);
    _updateAutoScrollActivity(globalPosition);
  }

  void _updateFromPointer(Offset globalPosition) {
    final dragEngine = _dragEngine;
    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (dragEngine == null || renderGrid == null || viewportBox == null) return;

    final scrollOffset = _scrollController.position.pixels;
    final localInViewport = viewportBox.globalToLocal(globalPosition);
    final localInContent = localInViewport + Offset(0, scrollOffset);
    dragEngine.updatePointer(
      pointerGlobal: globalPosition,
      pointerLocal: localInContent,
    );

    final viewportTop = scrollOffset;
    final viewportBottom = viewportTop + viewportBox.size.height;
    final band = viewportBox.size.height * 0.5;
    final candidates = renderGrid.queryVisibleItems(
      viewportTop - band,
      viewportBottom + band,
    );
    final previousTarget = dragEngine.targetIndex;

    int targetIndex;
    if (localInContent.dy <= viewportTop) {
      targetIndex = 0;
    } else if (localInContent.dy >= viewportBottom) {
      targetIndex = widget.itemCount - 1;
    } else {
      targetIndex = dragEngine.computeTargetIndex(
        candidateIndices: candidates.isEmpty
            ? List<int>.generate(widget.itemCount, (i) => i)
            : candidates,
        getItemRect: renderGrid.getItemRect,
        viewportTop: viewportTop - band,
        viewportBottom: viewportBottom + band,
      );
    }

    if (targetIndex != previousTarget) {
      widget.onReorderUpdate?.call(dragEngine.dragIndex, targetIndex);
    }

    final dragRect = dragEngine.dragRect;
    _ghostRect = Rect.fromCenter(
      center: globalPosition,
      width: dragRect.width,
      height: dragRect.height,
    );
    _ghostEntry?.markNeedsBuild();

    _syncPreviewToTarget();
  }

  void _updateAutoScrollActivity(Offset globalPosition) {
    final autoScroller = _autoScroller;
    final viewportBox = _scrollViewBox;
    final ticker = _autoScrollTicker;
    if (autoScroller == null || viewportBox == null || ticker == null) return;

    final pointerY = viewportBox.globalToLocal(globalPosition).dy;
    final isInEdgeZone = autoScroller.isInEdgeZone(
      pointerY: pointerY,
      viewportHeight: viewportBox.size.height,
    );

    if (isInEdgeZone) {
      if (!ticker.isActive) {
        _lastAutoScrollTick = null;
        ticker.start();
      }
    } else if (ticker.isActive) {
      ticker.stop();
    }
  }

  void _syncPreviewToTarget() {
    final dragEngine = _dragEngine;
    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (dragEngine == null || renderGrid == null || viewportBox == null) return;

    final scrollOffset = _scrollController.position.pixels;
    final band = viewportBox.size.height * 0.5;
    final indices = renderGrid.queryVisibleItems(
      scrollOffset - band,
      scrollOffset + viewportBox.size.height + band,
    );
    final firstVisible = indices.isEmpty ? -1 : indices.first;
    final lastVisible = indices.isEmpty ? -1 : indices.last;
    final targetUnchanged = dragEngine.targetIndex == _lastPreviewTarget;
    final viewportUnchanged =
        firstVisible == _lastPreviewFirstVisible &&
        lastVisible == _lastPreviewLastVisible;
    if (targetUnchanged && viewportUnchanged) {
      return;
    }

    final nextOffsets = renderGrid.buildReorderPreviewOffsets(
      dragIndex: dragEngine.dragIndex,
      targetIndex: dragEngine.targetIndex,
      indices: indices,
    );
    if (targetUnchanged &&
        viewportUnchanged == false &&
        _offsetMapsEqual(nextOffsets, _previewTo)) {
      _lastPreviewFirstVisible = firstVisible;
      _lastPreviewLastVisible = lastVisible;
      return;
    }

    final currentVisual = _currentPreviewOffsets(renderGrid.previewOffsets);
    _previewController.stop();
    _previewFrom = currentVisual;
    _previewTo = nextOffsets;
    _lastPreviewTarget = dragEngine.targetIndex;
    _lastPreviewFirstVisible = firstVisible;
    _lastPreviewLastVisible = lastVisible;
    renderGrid.setPreviewState(
      offsets: currentVisual,
      hiddenIndex: dragEngine.dragIndex,
    );
    _previewController.value = 0;
    _previewController.animateWith(
      SpringSimulation(_previewSpring, 0, 1, 0),
    );
  }

  Map<int, Offset> _currentPreviewOffsets(Map<int, Offset> fallback) {
    if (!_previewController.isAnimating) {
      return fallback;
    }
    final value = _previewController.value.clamp(0.0, 1.0);
    return _lerpOffsetMaps(_previewFrom, _previewTo, value);
  }

  void _applyPreviewAnimation() {
    final renderGrid = _renderGrid;
    final dragEngine = _dragEngine;
    if (renderGrid == null || dragEngine == null) return;

    final value = _previewController.value.clamp(0.0, 1.0);
    renderGrid.setPreviewState(
      offsets: _lerpOffsetMaps(_previewFrom, _previewTo, value),
      hiddenIndex: dragEngine.dragIndex,
    );
  }

  Map<int, Offset> _lerpOffsetMaps(
    Map<int, Offset> from,
    Map<int, Offset> to,
    double t,
  ) {
    final keys = <int>{...from.keys, ...to.keys};
    final result = <int, Offset>{};
    for (final key in keys) {
      final start = from[key] ?? Offset.zero;
      final end = to[key] ?? Offset.zero;
      final value = Offset.lerp(start, end, t) ?? Offset.zero;
      if (value != Offset.zero) {
        result[key] = value;
      }
    }
    return result;
  }

  bool _offsetMapsEqual(Map<int, Offset> a, Map<int, Offset> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  void _startAutoScrollTicker() {
    _autoScrollTicker ??= createTicker(_onAutoScrollTick);
  }

  void _onAutoScrollTick(Duration elapsed) {
    final autoScroller = _autoScroller;
    final viewportBox = _scrollViewBox;
    if (_dragEngine == null || autoScroller == null || viewportBox == null) {
      _autoScrollTicker?.stop();
      return;
    }

    final last = _lastAutoScrollTick;
    _lastAutoScrollTick = elapsed;
    if (last == null) return;

    final pointerY = viewportBox.globalToLocal(_latestGlobal).dy;
    if (!autoScroller.isInEdgeZone(
      pointerY: pointerY,
      viewportHeight: viewportBox.size.height,
    )) {
      _autoScrollTicker?.stop();
      return;
    }

    final delta = autoScroller.computeDelta(
      pointerY: pointerY,
      viewportHeight: viewportBox.size.height,
      elapsed: elapsed - last,
    );
    final applied = autoScroller.applyDelta(delta);
    if (applied != 0) {
      _updateFromPointer(_latestGlobal);
    } else {
      _autoScrollTicker?.stop();
    }
  }

  void _finishDrag() {
    final dragEngine = _dragEngine;
    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (dragEngine == null || renderGrid == null || viewportBox == null) {
      _cancelActiveDrag();
      return;
    }

    _previewController.stop();
    _autoScrollTicker?.stop();

    final targetRect = renderGrid.getItemRect(dragEngine.targetIndex);
    final scrollOffset = _scrollController.position.pixels;
    final globalTopLeft = viewportBox.localToGlobal(
      Offset(targetRect.left, targetRect.top - scrollOffset),
    );
    _settleFromRect = _ghostRect;
    _settleToRect = globalTopLeft & targetRect.size;
    _settleController.duration = _reorderConfig.settleDuration;
    _dropCommitted = dragEngine.targetIndex != dragEngine.dragIndex;
    _settleController.forward(from: 0).whenComplete(_completeDrop);
  }

  void _updateGhostFromSettle() {
    final value = _reorderConfig.settleCurve.transform(_settleController.value);
    _ghostRect = Rect.lerp(_settleFromRect, _settleToRect, value) ?? _settleToRect;
    _ghostEntry?.markNeedsBuild();
  }

  void _completeDrop() {
    final dragEngine = _dragEngine;
    if (dragEngine == null) return;

    final oldIndex = dragEngine.dragIndex;
    final newIndex = dragEngine.targetIndex;
    if (_dropCommitted) {
      widget.onReorder?.call(oldIndex, newIndex);
    }
    widget.onReorderEnd?.call(oldIndex, newIndex);
    _cancelActiveDrag();
  }

  void _cancelActiveDrag() {
    _autoScrollTicker?.stop();
    _dragEngine?.reset();
    _dragEngine = null;
    _autoScroller = null;
    _previewController.stop();
    _settleController.stop();
    _renderGrid?.clearPreviewState();
    _ghostEntry?.remove();
    _ghostEntry = null;
    _ghostChild = null;
    _previewFrom = const {};
    _previewTo = const {};
    _ghostRect = Rect.zero;
    _dropCommitted = false;
    _lastPreviewTarget = -1;
    _lastPreviewFirstVisible = -1;
    _lastPreviewLastVisible = -1;
  }
}

class _GhostFrame extends StatelessWidget {
  final Widget child;
  final double scale;

  const _GhostFrame({required this.child, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: const Color(0x33000000),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SmoothGridSliver extends SliverMultiBoxAdaptorWidget {
  final SmoothGridDelegate gridDelegate;
  final int itemCount;
  final ChildIndexGetter? findChildIndexCallback;
  final bool? useIsolate;

  _SmoothGridSliver({
    super.key,
    required this.itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.findChildIndexCallback,
    required this.gridDelegate,
    required bool addRepaintBoundaries,
    required bool addAutomaticKeepAlives,
    this.useIsolate,
  }) : super(
         delegate: SliverChildBuilderDelegate(
           itemBuilder,
           childCount: itemCount,
           findChildIndexCallback: findChildIndexCallback,
           addRepaintBoundaries: addRepaintBoundaries,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
         ),
       );

  @override
  SliverMultiBoxAdaptorElement createElement() =>
      SliverMultiBoxAdaptorElement(this, replaceMovedChildren: true);

  @override
  RenderSmoothGrid createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    final config = gridDelegate.toConfig(0);
    return RenderSmoothGrid(
      childManager: element,
      layoutConfig: config,
      itemExtentBuilder: gridDelegate.itemExtentBuilder,
      itemCount: itemCount,
    )..useIsolate = useIsolate;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSmoothGrid renderObject,
  ) {
    final config = gridDelegate.toConfig(0);
    renderObject
      ..layoutConfig = config
      ..itemExtentBuilder = gridDelegate.itemExtentBuilder
      ..itemCount = itemCount
      ..useIsolate = useIsolate;
  }
}

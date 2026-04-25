import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../interaction/auto_scroller.dart';
import '../interaction/drag_engine.dart';
import '../core/masonry_layout_engine.dart';
import '../core/smooth_session.dart';
import '../rendering/render_smooth_grid.dart';
import 'smooth_grid_delegate.dart';

typedef SmoothReorderStartCallback = void Function(int index);
typedef SmoothReorderUpdateCallback = void Function(int oldIndex, int newIndex);
typedef SmoothReorderEndCallback = void Function(int oldIndex, int newIndex);
typedef SmoothSectionHeaderBuilder = Widget Function(
    BuildContext context, int sectionIndex);
typedef SmoothSectionItemBuilder = Widget Function(
    BuildContext context, int sectionIndex, int itemIndex);
typedef SmoothSectionItemExtentBuilder = double Function(
    int sectionIndex, int itemIndex);

/// Describes one logical section in a [SmoothSectionedGrid].
class SmoothGridSection {
  final String id;
  final int itemCount;
  final Object? data;

  const SmoothGridSection({
    required this.id,
    required this.itemCount,
    this.data,
  });
}

class _MultiColumnTargetSlot {
  final int targetIndex;
  final Rect targetRect;
  final Rect? beforeRect;
  final Rect? afterRect;

  const _MultiColumnTargetSlot({
    required this.targetIndex,
    required this.targetRect,
    required this.beforeRect,
    required this.afterRect,
  });
}

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
  final SmoothSessionController? sessionController;

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
    this.sessionController,
  }) : assert(
          !reorderable || onReorder != null,
          'onReorder must be provided when reorderable is true',
        );

  /// Creates a high-performance masonry grid with a fixed column count.
  ///
  /// This constructor keeps the same performance model as [SmoothGrid]: it uses
  /// [itemBuilder] for lazy child creation and requires [itemExtentBuilder] so
  /// layout can be precomputed without measuring widgets at runtime.
  SmoothGrid.count({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    required int crossAxisCount,
    double mainAxisSpacing = 0,
    double crossAxisSpacing = 0,
    EdgeInsets padding = EdgeInsets.zero,
    required SmoothItemExtentBuilder itemExtentBuilder,
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
    this.sessionController,
  })  : delegate = SmoothGridDelegateWithFixedCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          padding: padding,
          itemExtentBuilder: itemExtentBuilder,
        ),
        assert(
          !reorderable || onReorder != null,
          'onReorder must be provided when reorderable is true',
        );

  @override
  State<SmoothGrid> createState() => _SmoothGridState();
}

/// A SmoothGrid-like view that renders multiple item sections with headers in
/// the same scrollable viewport.
///
/// This is intended for grouped feeds such as sessions, days, folders, or
/// categories where each group should keep masonry layout performance but also
/// expose an in-scroll header. Reorder is intentionally not supported here yet
/// because cross-section drag semantics need a separate interaction contract.
class SmoothSectionedGrid extends StatefulWidget {
  final List<SmoothGridSection> sections;
  final SmoothSectionHeaderBuilder headerBuilder;
  final SmoothSectionItemBuilder itemBuilder;
  final SmoothSectionItemExtentBuilder itemExtentBuilder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool addRepaintBoundaries;
  final bool addAutomaticKeepAlives;
  final double? cacheExtent;
  final bool shrinkWrap;
  final bool? useIsolate;
  final SmoothSessionController? sessionController;
  final bool pinnedHeaders;
  final double pinnedHeaderExtent;

  const SmoothSectionedGrid({
    super.key,
    required this.sections,
    required this.headerBuilder,
    required this.itemBuilder,
    required this.itemExtentBuilder,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = 6,
    this.crossAxisSpacing = 6,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = false,
    this.cacheExtent,
    this.shrinkWrap = false,
    this.useIsolate,
    this.sessionController,
    this.pinnedHeaders = false,
    this.pinnedHeaderExtent = 96,
  })  : assert(crossAxisCount > 0),
        assert(pinnedHeaderExtent > 0);

  @override
  State<SmoothSectionedGrid> createState() => _SmoothSectionedGridState();
}

class _SmoothSectionedGridState extends State<SmoothSectionedGrid> {
  ScrollController? _ownedController;
  var _activePinnedSectionIndex = 0;
  var _sectionOffsetsDirty = true;
  List<double> _sectionStarts = const [];

  ScrollController get _scrollController =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = ScrollController(
        initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
      );
    }
    _scrollController.addListener(_handleScroll);
    _attachSessionController();
  }

  @override
  void didUpdateWidget(covariant SmoothSectionedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleScroll);
      _ownedController?.removeListener(_handleScroll);
      oldWidget.sessionController?.detachScrollController();
      _ownedController?.dispose();
      _ownedController = widget.controller == null
          ? ScrollController(
              initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
            )
          : null;
      _scrollController.addListener(_handleScroll);
      _attachSessionController();
    } else if (oldWidget.sessionController != widget.sessionController) {
      oldWidget.sessionController?.detachScrollController();
      _attachSessionController();
    }
    _sectionOffsetsDirty = true;
    if (_activePinnedSectionIndex >= widget.sections.length) {
      _activePinnedSectionIndex =
          widget.sections.isEmpty ? 0 : widget.sections.length - 1;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    widget.sessionController?.detachScrollController();
    _ownedController?.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.pinnedHeaders || widget.sections.isEmpty) return;
    final nextIndex = _sectionIndexForOffset(_scrollController.offset);
    if (nextIndex == _activePinnedSectionIndex) return;
    setState(() => _activePinnedSectionIndex = nextIndex);
  }

  void _attachSessionController() {
    final sessionController = widget.sessionController;
    if (sessionController == null) return;
    sessionController.attachScrollController(_scrollController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sessionController.jumpToSavedOffset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      controller: _scrollController,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      cacheExtent: widget.cacheExtent,
      slivers: [
        for (var sectionIndex = 0;
            sectionIndex < widget.sections.length;
            sectionIndex++)
          ..._buildSection(sectionIndex),
      ],
    );

    if (!widget.pinnedHeaders || widget.sections.isEmpty) {
      return scrollView;
    }

    return Stack(
      children: [
        scrollView,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: widget.pinnedHeaderExtent,
            child: widget.headerBuilder(context, _activePinnedSectionIndex),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSection(int sectionIndex) {
    final section = widget.sections[sectionIndex];
    final delegate = SmoothGridDelegate.count(
      crossAxisCount: widget.crossAxisCount,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      padding: widget.padding,
      itemExtentBuilder: (itemIndex) =>
          widget.itemExtentBuilder(sectionIndex, itemIndex),
    );

    return [
      SliverToBoxAdapter(
        child: widget.pinnedHeaders
            ? SizedBox(
                height: widget.pinnedHeaderExtent,
                child: sectionIndex == _activePinnedSectionIndex
                    ? const SizedBox.shrink()
                    : widget.headerBuilder(context, sectionIndex),
              )
            : widget.headerBuilder(context, sectionIndex),
      ),
      _SmoothGridSliver(
        key: ValueKey('smooth_section_${section.id}'),
        itemCount: section.itemCount,
        itemBuilder: (context, itemIndex) =>
            widget.itemBuilder(context, sectionIndex, itemIndex),
        gridDelegate: delegate,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        useIsolate: widget.useIsolate,
      ),
    ];
  }

  int _sectionIndexForOffset(double offset) {
    _ensureSectionOffsets();
    for (var sectionIndex = _sectionStarts.length - 1;
        sectionIndex >= 0;
        sectionIndex--) {
      if (offset >= _sectionStarts[sectionIndex]) {
        return sectionIndex;
      }
    }
    return 0;
  }

  void _ensureSectionOffsets() {
    if (!_sectionOffsetsDirty) return;

    final starts = <double>[];
    var sectionStart = 0.0;
    for (var sectionIndex = 0;
        sectionIndex < widget.sections.length;
        sectionIndex++) {
      starts.add(sectionStart);
      final section = widget.sections[sectionIndex];
      sectionStart += widget.pinnedHeaderExtent +
          _estimateGridHeight(sectionIndex, section.itemCount);
    }
    _sectionStarts = starts;
    _sectionOffsetsDirty = false;
  }

  double _estimateGridHeight(int sectionIndex, int itemCount) {
    if (itemCount == 0) return 0;

    final columnHeights = List<double>.filled(
      widget.crossAxisCount,
      widget.padding.top,
    );
    for (var itemIndex = 0; itemIndex < itemCount; itemIndex++) {
      var shortestColumn = 0;
      var minHeight = columnHeights[0];
      for (var column = 1; column < widget.crossAxisCount; column++) {
        if (columnHeights[column] < minHeight) {
          minHeight = columnHeights[column];
          shortestColumn = column;
        }
      }
      columnHeights[shortestColumn] = minHeight +
          widget.itemExtentBuilder(sectionIndex, itemIndex) +
          widget.mainAxisSpacing;
    }

    var maxHeight = 0.0;
    for (final columnHeight in columnHeights) {
      final height = columnHeight > widget.padding.top
          ? columnHeight - widget.mainAxisSpacing
          : columnHeight;
      if (height > maxHeight) maxHeight = height;
    }
    return maxHeight + widget.padding.bottom;
  }
}

class _SmoothGridState extends State<SmoothGrid> with TickerProviderStateMixin {
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
  Rect? _previewPlaceholderFrom;
  Rect? _previewPlaceholderTo;
  Rect _ghostRect = Rect.zero;
  Rect _settleFromRect = Rect.zero;
  Rect _settleToRect = Rect.zero;
  Offset _latestGlobal = Offset.zero;
  Offset _dragPointerAnchor = Offset.zero;
  Widget? _ghostChild;
  bool _dropCommitted = false;
  int _lastPreviewTarget = -1;
  int _lastPreviewFirstVisible = -1;
  int _lastPreviewLastVisible = -1;

  ScrollController get _scrollController =>
      widget.controller ?? _ownedController!;
  SmoothReorderConfig get _reorderConfig =>
      widget.reorderConfig ?? const SmoothReorderConfig();

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(vsync: this)
      ..addListener(_applyPreviewAnimation);
    _settleController = AnimationController(vsync: this)
      ..addListener(_updateGhostFromSettle);
    if (widget.controller == null) {
      _ownedController = ScrollController(
        initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
      );
    }
    _attachSessionController();
  }

  @override
  void didUpdateWidget(covariant SmoothGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.sessionController?.detachScrollController();
      _ownedController?.dispose();
      _ownedController = widget.controller == null
          ? ScrollController(
              initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
            )
          : null;
      _attachSessionController();
    } else if (oldWidget.sessionController != widget.sessionController) {
      oldWidget.sessionController?.detachScrollController();
      _attachSessionController();
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
    widget.sessionController?.detachScrollController();
    _ownedController?.dispose();
    super.dispose();
  }

  void _attachSessionController() {
    final sessionController = widget.sessionController;
    if (sessionController == null) return;
    sessionController.attachScrollController(_scrollController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sessionController.jumpToSavedOffset();
    });
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

    final viewportOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final pointerLocal =
        viewportBox.globalToLocal(globalPosition) + Offset(0, viewportOffset);
    return renderGrid.getItemIndexAt(pointerLocal);
  }

  void _startDrag(int index, Offset globalPosition) {
    if (!widget.reorderable || widget.scrollDirection != Axis.vertical) return;

    final renderGrid = _renderGrid;
    final viewportBox = _scrollViewBox;
    if (renderGrid == null ||
        viewportBox == null ||
        index >= widget.itemCount) {
      return;
    }

    final itemRect = renderGrid.getItemRect(index);
    final viewportOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final viewportRect = Rect.fromLTWH(
      itemRect.left,
      itemRect.top - viewportOffset,
      itemRect.width,
      itemRect.height,
    );
    final globalTopLeft = viewportBox.localToGlobal(viewportRect.topLeft);
    final globalRect = globalTopLeft & viewportRect.size;
    final pointerLocal =
        viewportBox.globalToLocal(globalPosition) + Offset(0, viewportOffset);

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
      edgeThreshold: _reorderConfig.resolveEdgeScrollZone(
        viewportBox.size.height,
      ),
      maxScrollVelocity: _reorderConfig.maxAutoScrollVelocity,
    );

    _ghostRect = globalRect;
    _latestGlobal = globalPosition;
    _dragPointerAnchor = globalPosition - globalRect.topLeft;
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
    _previewPlaceholderFrom = itemRect;
    _previewPlaceholderTo = itemRect;
    _lastPreviewTarget = index;
    _lastPreviewFirstVisible = -1;
    _lastPreviewLastVisible = -1;
    renderGrid.setPreviewState(
      offsets: const {},
      hiddenIndex: index,
      placeholderRect: itemRect,
    );
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
    final dragRect = dragEngine.dragRect;
    final dragTopLeft = localInContent - _dragPointerAnchor;
    final dragCenter =
        dragTopLeft + Offset(dragRect.width / 2, dragRect.height / 2);
    dragEngine.updatePointer(
      pointerGlobal: globalPosition,
      pointerLocal: dragCenter,
      draggedTopLeft: dragTopLeft,
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
      dragEngine.setTargetIndex(targetIndex, maxTargetIndex: widget.itemCount);
    } else if (localInContent.dy >= viewportBottom) {
      targetIndex = widget.itemCount;
      dragEngine.setTargetIndex(targetIndex, maxTargetIndex: widget.itemCount);
    } else if (widget.delegate.crossAxisCount > 1) {
      targetIndex = _computeMultiColumnTargetIndex(
        renderGrid: renderGrid,
        dragEngine: dragEngine,
        candidateIndices: candidates,
      );
      dragEngine.setTargetIndex(targetIndex, maxTargetIndex: widget.itemCount);
    } else {
      targetIndex = dragEngine.computeTargetIndex(
        candidateIndices: candidates,
        getItemRect: renderGrid.getItemRect,
        viewportTop: viewportTop - band,
        viewportBottom: viewportBottom + band,
        maxTargetIndex: widget.itemCount,
      );
    }

    if (targetIndex != previousTarget) {
      widget.onReorderUpdate?.call(dragEngine.dragIndex, targetIndex);
    }

    _ghostRect = Rect.fromLTWH(
      globalPosition.dx - _dragPointerAnchor.dx,
      globalPosition.dy - _dragPointerAnchor.dy,
      dragRect.width,
      dragRect.height,
    );
    _ghostEntry?.markNeedsBuild();

    _syncPreviewToTarget();
  }

  int _computeMultiColumnTargetIndex({
    required RenderSmoothGrid renderGrid,
    required SmoothDragEngine dragEngine,
    required List<int> candidateIndices,
  }) {
    final dragRect = dragEngine.dragRect;
    final candidateTargets = <int>{0, widget.itemCount};
    if (candidateIndices.isEmpty) {
      return dragEngine.targetIndex.clamp(0, widget.itemCount);
    }
    for (final index in candidateIndices) {
      if (index < 0 || index >= widget.itemCount) continue;
      candidateTargets.add(index);
      candidateTargets.add(index + 1);
    }

    final slots = candidateTargets
        .map(
          (target) => _buildMultiColumnTargetSlot(
            renderGrid: renderGrid,
            dragIndex: dragEngine.dragIndex,
            targetIndex: target.clamp(0, widget.itemCount),
          ),
        )
        .whereType<_MultiColumnTargetSlot>()
        .toList(growable: false);
    if (slots.isEmpty) {
      return dragEngine.targetIndex.clamp(0, widget.itemCount);
    }

    final previousTarget = dragEngine.targetIndex;
    var bestSlot = slots.first;
    var bestScore = _scoreMultiColumnTargetSlot(
      dragRect: dragRect,
      slot: bestSlot,
    );
    for (final slot in slots.skip(1)) {
      final score = _scoreMultiColumnTargetSlot(dragRect: dragRect, slot: slot);
      if (score < bestScore) {
        bestSlot = slot;
        bestScore = score;
      }
    }

    if (previousTarget >= 0) {
      for (final slot in slots) {
        if (slot.targetIndex != previousTarget) continue;
        final previousScore = _scoreMultiColumnTargetSlot(
          dragRect: dragRect,
          slot: slot,
        );
        if (previousScore <=
            bestScore + (_reorderConfig.collisionHysteresis * 2.0)) {
          return previousTarget;
        }
        break;
      }
    }

    return bestSlot.targetIndex;
  }

  _MultiColumnTargetSlot? _buildMultiColumnTargetSlot({
    required RenderSmoothGrid renderGrid,
    required int dragIndex,
    required int targetIndex,
  }) {
    if (widget.itemCount <= 0 ||
        dragIndex < 0 ||
        dragIndex >= widget.itemCount) {
      return null;
    }

    final clampedTarget = targetIndex.clamp(0, widget.itemCount);
    final targetRect = renderGrid.computeReorderTargetRect(
          dragIndex: dragIndex,
          targetIndex: clampedTarget,
        ) ??
        renderGrid.getItemRect(dragIndex);
    return _MultiColumnTargetSlot(
      targetIndex: clampedTarget,
      targetRect: targetRect,
      beforeRect: _slotNeighborRect(
        renderGrid: renderGrid,
        dragIndex: dragIndex,
        startIndex: clampedTarget - 1,
        step: -1,
      ),
      afterRect: _slotNeighborRect(
        renderGrid: renderGrid,
        dragIndex: dragIndex,
        startIndex: clampedTarget,
        step: 1,
      ),
    );
  }

  Rect? _slotNeighborRect({
    required RenderSmoothGrid renderGrid,
    required int dragIndex,
    required int startIndex,
    required int step,
  }) {
    var index = startIndex;
    while (index >= 0 && index < widget.itemCount) {
      if (index != dragIndex) {
        return renderGrid.getItemRect(index);
      }
      index += step;
    }
    return null;
  }

  double _scoreMultiColumnTargetSlot({
    required Rect dragRect,
    required _MultiColumnTargetSlot slot,
  }) {
    final dragCenter = dragRect.center;
    final containsCenter = slot.targetRect.contains(dragCenter);
    final targetOverlap = _overlapRatio(dragRect, slot.targetRect);

    final beforeContains = slot.beforeRect?.contains(dragCenter) ?? false;
    final afterContains = slot.afterRect?.contains(dragCenter) ?? false;
    final anchorContains = beforeContains || afterContains;
    final beforeOverlap = slot.beforeRect == null
        ? 0.0
        : _overlapRatio(dragRect, slot.beforeRect!);
    final afterOverlap =
        slot.afterRect == null ? 0.0 : _overlapRatio(dragRect, slot.afterRect!);
    final anchorOverlap =
        beforeOverlap > afterOverlap ? beforeOverlap : afterOverlap;

    final targetDistance = (dragCenter.dy - slot.targetRect.center.dy).abs() +
        ((dragCenter.dx - slot.targetRect.center.dx).abs() * 0.6);
    final beforeDistance = slot.beforeRect == null
        ? double.infinity
        : (dragCenter.dy - slot.beforeRect!.center.dy).abs() +
            ((dragCenter.dx - slot.beforeRect!.center.dx).abs() * 0.5);
    final afterDistance = slot.afterRect == null
        ? double.infinity
        : (dragCenter.dy - slot.afterRect!.center.dy).abs() +
            ((dragCenter.dx - slot.afterRect!.center.dx).abs() * 0.5);
    final anchorDistance =
        beforeDistance < afterDistance ? beforeDistance : afterDistance;

    return targetDistance +
        (anchorDistance.isFinite ? anchorDistance * 0.35 : 0.0) -
        (targetOverlap * 280.0) -
        (anchorOverlap * 180.0) -
        (containsCenter ? 1200.0 : 0.0) -
        (anchorContains ? 220.0 : 0.0);
  }

  double _overlapRatio(Rect a, Rect b) {
    if (!a.overlaps(b)) {
      return 0.0;
    }
    final overlap = a.intersect(b);
    final overlapArea = overlap.width * overlap.height;
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    final minArea = aArea < bArea ? aArea : bArea;
    if (minArea <= 0) {
      return 0.0;
    }
    return overlapArea / minArea;
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
    final viewportUnchanged = firstVisible == _lastPreviewFirstVisible &&
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

    final currentPlaceholder = _currentPreviewPlaceholder(
      _previewPlaceholderTo ?? _previewPlaceholderRect(renderGrid, dragEngine),
    );
    final nextPlaceholder = _previewPlaceholderRect(renderGrid, dragEngine);

    _previewFrom = currentVisual;
    _previewTo = nextOffsets;
    _previewPlaceholderFrom = currentPlaceholder;
    _previewPlaceholderTo = nextPlaceholder;
    _lastPreviewTarget = dragEngine.targetIndex;
    _lastPreviewFirstVisible = firstVisible;
    _lastPreviewLastVisible = lastVisible;
    renderGrid.setPreviewState(
      offsets: currentVisual,
      hiddenIndex: dragEngine.dragIndex,
      placeholderRect: currentPlaceholder,
    );
    _previewController.value = 0;
    _previewController.animateTo(
      1,
      duration: _reorderConfig.translateDuration,
      curve: _reorderConfig.translateCurve,
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
      placeholderRect: _lerpRect(
        _previewPlaceholderFrom,
        _previewPlaceholderTo,
        value,
      ),
    );
  }

  Rect? _currentPreviewPlaceholder(Rect? fallback) {
    if (!_previewController.isAnimating) {
      return fallback;
    }
    final value = _previewController.value.clamp(0.0, 1.0);
    return _lerpRect(_previewPlaceholderFrom, _previewPlaceholderTo, value) ??
        fallback;
  }

  Rect? _lerpRect(Rect? from, Rect? to, double t) {
    if (from == null) return to;
    if (to == null) return from;
    return Rect.lerp(from, to, t);
  }

  Rect? _previewPlaceholderRect(
    RenderSmoothGrid renderGrid,
    SmoothDragEngine dragEngine,
  ) {
    return renderGrid.computeReorderTargetRect(
          dragIndex: dragEngine.dragIndex,
          targetIndex: dragEngine.targetIndex,
        ) ??
        renderGrid.getItemRect(dragEngine.dragIndex);
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

    final targetRect = renderGrid.computeReorderTargetRect(
          dragIndex: dragEngine.dragIndex,
          targetIndex: dragEngine.targetIndex,
        ) ??
        renderGrid.getItemRect(
          dragEngine.targetIndex.clamp(0, widget.itemCount - 1),
        );
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
    _ghostRect =
        Rect.lerp(_settleFromRect, _settleToRect, value) ?? _settleToRect;
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
    _previewPlaceholderFrom = null;
    _previewPlaceholderTo = null;
    _ghostRect = Rect.zero;
    _dragPointerAnchor = Offset.zero;
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

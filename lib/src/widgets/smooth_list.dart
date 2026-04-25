import 'package:flutter/widgets.dart';

import '../core/masonry_layout_engine.dart';
import '../core/smooth_session.dart';
import 'smooth_grid.dart';
import 'smooth_grid_delegate.dart';

/// A lightweight virtualized list for known variable item extents.
class SmoothList extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SmoothItemExtentBuilder itemExtentBuilder;
  final ScrollController? controller;
  final SmoothSessionController? sessionController;
  final ScrollPhysics? physics;
  final Axis scrollDirection;
  final bool shrinkWrap;
  final double? cacheExtent;
  final bool addRepaintBoundaries;
  final bool addAutomaticKeepAlives;
  final bool reorderable;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const SmoothList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtentBuilder,
    this.controller,
    this.sessionController,
    this.physics,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = false,
    this.cacheExtent,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = false,
    this.reorderable = false,
    this.onReorder,
  }) : assert(
          !reorderable || onReorder != null,
          'onReorder must be provided when reorderable is true',
        );

  @override
  State<SmoothList> createState() => _SmoothListState();
}

class _SmoothListState extends State<SmoothList> {
  ScrollController? _ownedController;

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
    _attachSessionController();
  }

  @override
  void didUpdateWidget(covariant SmoothList oldWidget) {
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
  }

  @override
  void dispose() {
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
    if (widget.reorderable) {
      return SmoothGrid(
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
        controller: _scrollController,
        sessionController: widget.sessionController,
        physics: widget.physics,
        scrollDirection: widget.scrollDirection,
        shrinkWrap: widget.shrinkWrap,
        cacheExtent: widget.cacheExtent,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        reorderable: true,
        onReorder: widget.onReorder,
        delegate: SmoothGridDelegate.count(
          crossAxisCount: 1,
          itemExtentBuilder: widget.itemExtentBuilder,
        ),
      );
    }

    final prototypeCache = <int, double>{};
    return ListView.builder(
      controller: _scrollController,
      physics: widget.physics,
      scrollDirection: widget.scrollDirection,
      shrinkWrap: widget.shrinkWrap,
      cacheExtent: widget.cacheExtent,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        final extent = prototypeCache.putIfAbsent(
          index,
          () => widget.itemExtentBuilder(index),
        );
        return SizedBox(
          height: widget.scrollDirection == Axis.vertical ? extent : null,
          width: widget.scrollDirection == Axis.horizontal ? extent : null,
          child: widget.itemBuilder(context, index),
        );
      },
    );
  }
}

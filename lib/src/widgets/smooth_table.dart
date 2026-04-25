import 'package:flutter/widgets.dart';

import '../core/smooth_session.dart';

/// Builds a virtualized table cell.
typedef SmoothTableCellBuilder =
    Widget Function(BuildContext context, int row, int column);

typedef SmoothTableExtentBuilder = double Function(int index);

/// A v1 virtualized table with vertical row virtualization and horizontal cell culling.
class SmoothTable extends StatefulWidget {
  final int rowCount;
  final int columnCount;
  final SmoothTableCellBuilder cellBuilder;
  final SmoothTableExtentBuilder rowExtentBuilder;
  final SmoothTableExtentBuilder columnExtentBuilder;
  final int pinnedRows;
  final int pinnedColumns;
  final ScrollController? verticalController;
  final ScrollController? horizontalController;
  final SmoothSessionController? sessionController;
  final double? cacheExtent;

  const SmoothTable({
    super.key,
    required this.rowCount,
    required this.columnCount,
    required this.cellBuilder,
    required this.rowExtentBuilder,
    required this.columnExtentBuilder,
    this.pinnedRows = 0,
    this.pinnedColumns = 0,
    this.verticalController,
    this.horizontalController,
    this.sessionController,
    this.cacheExtent,
  }) : assert(pinnedRows >= 0),
       assert(pinnedColumns >= 0);

  @override
  State<SmoothTable> createState() => _SmoothTableState();
}

class _SmoothTableState extends State<SmoothTable> {
  ScrollController? _ownedVerticalController;
  ScrollController? _ownedHorizontalController;
  double _horizontalOffset = 0;
  double _horizontalViewportWidth = 0;
  double _totalWidth = 0;
  double _pinnedWidth = 0;

  ScrollController get _verticalController =>
      widget.verticalController ?? _ownedVerticalController!;
  ScrollController get _horizontalController =>
      widget.horizontalController ?? _ownedHorizontalController!;

  @override
  void initState() {
    super.initState();
    if (widget.verticalController == null) {
      _ownedVerticalController = ScrollController(
        initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
      );
    }
    if (widget.horizontalController == null) {
      _ownedHorizontalController = ScrollController();
    }
    _horizontalController.addListener(_syncHorizontalOffset);
    _attachSessionController();
  }

  @override
  void didUpdateWidget(covariant SmoothTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verticalController != widget.verticalController) {
      oldWidget.sessionController?.detachScrollController();
      _ownedVerticalController?.dispose();
      _ownedVerticalController = widget.verticalController == null
          ? ScrollController(
              initialScrollOffset: widget.sessionController?.scrollOffset ?? 0,
            )
          : null;
      _attachSessionController();
    } else if (oldWidget.sessionController != widget.sessionController) {
      oldWidget.sessionController?.detachScrollController();
      _attachSessionController();
    }

    if (oldWidget.horizontalController != widget.horizontalController) {
      oldWidget.horizontalController?.removeListener(_syncHorizontalOffset);
      _ownedHorizontalController?.removeListener(_syncHorizontalOffset);
      _ownedHorizontalController?.dispose();
      _ownedHorizontalController = widget.horizontalController == null
          ? ScrollController()
          : null;
      _horizontalController.addListener(_syncHorizontalOffset);
    }
  }

  @override
  void dispose() {
    widget.sessionController?.detachScrollController();
    _horizontalController.removeListener(_syncHorizontalOffset);
    _ownedVerticalController?.dispose();
    _ownedHorizontalController?.dispose();
    super.dispose();
  }

  void _attachSessionController() {
    final sessionController = widget.sessionController;
    if (sessionController == null) return;
    sessionController.attachScrollController(_verticalController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sessionController.jumpToSavedOffset();
    });
  }

  void _syncHorizontalOffset() {
    if (!mounted) return;
    setState(() => _horizontalOffset = _horizontalController.offset);
  }

  void _handleHorizontalDrag(DragUpdateDetails details) {
    final maxOffset = (_totalWidth - _horizontalViewportWidth).clamp(
      0.0,
      double.infinity,
    );
    final next = (_horizontalOffset - details.delta.dx).clamp(0.0, maxOffset);
    if (next == _horizontalOffset) return;
    setState(() => _horizontalOffset = next);
    if (_horizontalController.hasClients) {
      _horizontalController.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _horizontalViewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0;
        _totalWidth = _sumColumnWidth(0, widget.columnCount);
        _pinnedWidth = _sumColumnWidth(
          0,
          widget.pinnedColumns.clamp(0, widget.columnCount),
        );
        final pinnedRows = widget.pinnedRows.clamp(0, widget.rowCount);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _handleHorizontalDrag,
          child: Column(
            children: [
              for (var row = 0; row < pinnedRows; row++) _buildRow(row),
              Expanded(
                child: RawScrollbar(
                  controller: _verticalController,
                  child: ListView.builder(
                    controller: _verticalController,
                    cacheExtent: widget.cacheExtent,
                    itemCount: widget.rowCount - pinnedRows,
                    itemBuilder: (context, rowOffset) {
                      return _buildRow(rowOffset + pinnedRows);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(int row) {
    return SizedBox(
      height: widget.rowExtentBuilder(row),
      child: _TableRow(
        row: row,
        columnCount: widget.columnCount,
        pinnedColumns: widget.pinnedColumns.clamp(0, widget.columnCount),
        pinnedWidth: _pinnedWidth,
        totalWidth: _totalWidth,
        horizontalOffset: _horizontalOffset,
        viewportWidth: _horizontalViewportWidth,
        columnExtentBuilder: widget.columnExtentBuilder,
        cellBuilder: widget.cellBuilder,
      ),
    );
  }

  double _sumColumnWidth(int start, int end) {
    var width = 0.0;
    for (var column = start; column < end; column++) {
      width += widget.columnExtentBuilder(column);
    }
    return width;
  }
}

class _TableRow extends StatelessWidget {
  final int row;
  final int columnCount;
  final int pinnedColumns;
  final double pinnedWidth;
  final double totalWidth;
  final double horizontalOffset;
  final double viewportWidth;
  final SmoothTableExtentBuilder columnExtentBuilder;
  final SmoothTableCellBuilder cellBuilder;

  const _TableRow({
    required this.row,
    required this.columnCount,
    required this.pinnedColumns,
    required this.pinnedWidth,
    required this.totalWidth,
    required this.horizontalOffset,
    required this.viewportWidth,
    required this.columnExtentBuilder,
    required this.cellBuilder,
  });

  @override
  Widget build(BuildContext context) {
    var x = 0.0;
    final scrollChildren = <Widget>[];
    final pinnedChildren = <Widget>[];
    final visibleStart = pinnedWidth + horizontalOffset - 300;
    final visibleEnd = pinnedWidth + horizontalOffset + viewportWidth + 300;
    for (var column = 0; column < columnCount; column++) {
      final width = columnExtentBuilder(column);
      final right = x + width;
      final isPinned = column < pinnedColumns;
      if (isPinned || (right >= visibleStart && x <= visibleEnd)) {
        final visualLeft = isPinned
            ? x
            : pinnedWidth + x - pinnedWidth - horizontalOffset;
        final child = Positioned(
          left: visualLeft,
          top: 0,
          width: width,
          bottom: 0,
          child: cellBuilder(context, row, column),
        );
        if (isPinned) {
          pinnedChildren.add(child);
        } else {
          scrollChildren.add(child);
        }
      }
      x = right;
    }

    return SizedBox(
      width: totalWidth > 0 ? totalWidth : x,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [...scrollChildren, ...pinnedChildren],
      ),
    );
  }
}

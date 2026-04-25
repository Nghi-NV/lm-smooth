import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

import 'demo_common.dart';

class SmoothTableDemoPage extends StatefulWidget {
  const SmoothTableDemoPage({super.key});

  @override
  State<SmoothTableDemoPage> createState() => _SmoothTableDemoPageState();
}

class _SmoothTableDemoPageState extends State<SmoothTableDemoPage> {
  final session = SmoothSessionController(id: 'smooth-table-demo');
  var pinnedRows = 1;
  var pinnedColumns = 1;

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('SmoothTable · pin R$pinnedRows C$pinnedColumns'),
        actions: [
          IconButton(
            tooltip: 'Toggle pinned header',
            icon: const Icon(Icons.vertical_align_top),
            onPressed: () =>
                setState(() => pinnedRows = pinnedRows == 0 ? 1 : 0),
          ),
          IconButton(
            tooltip: 'Toggle pinned first columns',
            icon: const Icon(Icons.view_column),
            onPressed: () =>
                setState(() => pinnedColumns = pinnedColumns == 1 ? 2 : 1),
          ),
        ],
      ),
      body: DemoGradientBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DemoHeroHeader(
                title: 'Analytics Table Showcase',
                subtitle: '20K × 200 culling with pinned styled cells.',
                icon: Icons.analytics,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0x2EFFFFFF)),
                          color: const Color(0x18000000),
                        ),
                        child: SmoothTable(
                          rowCount: 20000,
                          columnCount: 200,
                          pinnedRows: pinnedRows,
                          pinnedColumns: pinnedColumns,
                          sessionController: session,
                          cacheExtent: 800,
                          rowExtentBuilder: (row) => row == 0 ? 58 : 52,
                          columnExtentBuilder: (column) =>
                              column == 0 ? 118 : 132,
                          cellBuilder: _buildCell,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, int row, int column) {
    final isPinned = row < pinnedRows || column < pinnedColumns;
    final hash = ((row * 73856093) ^ (column * 19349663)) & 0xFFFFFFFF;
    final hue = (hash % 360).toDouble();
    final value = ((hash % 20000) / 100) - 100;
    final positive = value >= 0;
    final accent = HSLColor.fromAHSL(1, hue, 0.58, 0.46).toColor();

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPinned
              ? [const Color(0xFF3B2E69), const Color(0xFF172033)]
              : [accent.withValues(alpha: 0.26), const Color(0x1AFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1FFFFFFF), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (row == 0 || column == 0)
              Icon(
                row == 0 ? Icons.show_chart : demoIcons[row % demoIcons.length],
                size: 14,
                color: Colors.white70,
              ),
            if (row == 0 || column == 0) const SizedBox(width: 6),
            Flexible(
              child: Text(
                row == 0
                    ? 'Metric $column'
                    : column == 0
                    ? 'Portfolio $row'
                    : '${positive ? '+' : ''}${value.toStringAsFixed(1)}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isPinned ? 12 : 11,
                  color: isPinned
                      ? Colors.white
                      : (positive
                            ? const Color(0xFF8DFFB1)
                            : const Color(0xFFFF9D9D)),
                  fontWeight: isPinned ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

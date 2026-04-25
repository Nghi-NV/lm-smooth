import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

import 'demo_common.dart';

class GridDemoPage extends StatefulWidget {
  final int itemCount;

  const GridDemoPage({super.key, required this.itemCount});

  @override
  State<GridDemoPage> createState() => _GridDemoPageState();
}

class _GridDemoPageState extends State<GridDemoPage> {
  late int _itemCount = widget.itemCount;
  int _columns = 3;
  bool _reorderable = false;
  bool _useList = false; // A/B comparison: Grid vs ListView
  final _gridSessions = [
    SmoothSessionController(id: 'Grid Session A'),
    SmoothSessionController(id: 'Grid Session B'),
    SmoothSessionController(id: 'Grid Session C'),
  ];
  var _gridSessionIndex = 0;

  // Only used in reorderable mode — lazily initialized
  List<int>? _reorderItems;

  List<int> get _items => _reorderItems ??= List.generate(_itemCount, (i) => i);
  SmoothSessionController get _activeGridSession =>
      _gridSessions[_gridSessionIndex];

  void _updateItemCount(int count) {
    setState(() {
      _itemCount = count;
      _reorderItems = _reorderable ? List.generate(count, (i) => i) : null;
    });
  }

  @override
  void dispose() {
    for (final session in _gridSessions) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_activeGridSession.session.id} · ${_fmt(_itemCount)} · ${_useList ? "List" : "$_columns col"}${_reorderable ? ' · Drag' : ''}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.bookmark_added),
            tooltip: 'Grid session',
            onSelected: (index) => setState(() => _gridSessionIndex = index),
            itemBuilder: (_) => [
              for (var i = 0; i < _gridSessions.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Text(
                    '${_gridSessions[i].session.id} · offset ${_gridSessions[i].scrollOffset.toStringAsFixed(0)}',
                  ),
                ),
            ],
          ),
          // Grid/List toggle
          IconButton(
            icon: Icon(_useList ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _useList = !_useList),
            tooltip: _useList ? 'Switch to Grid' : 'Switch to List',
          ),
          // Column controls (only for grid mode)
          if (!_useList) ...[
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: _columns > 1 ? () => setState(() => _columns--) : null,
              tooltip: 'Less columns',
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _columns < 6 ? () => setState(() => _columns++) : null,
              tooltip: 'More columns',
            ),
          ],
          // Item count menu
          PopupMenuButton<int>(
            icon: const Icon(Icons.format_list_numbered),
            tooltip: 'Item count',
            onSelected: _updateItemCount,
            itemBuilder: (_) => [
              for (final n in [100, 500, 1000, 5000, 10000, 100000, 1000000])
                PopupMenuItem(value: n, child: Text('${_fmt(n)} items')),
            ],
          ),
        ],
      ),
      body: BackdropGroup(
        child: _useList ? _buildListView() : _buildSmoothGrid(),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => setState(() {
          _reorderable = !_reorderable;
          _reorderItems =
              _reorderable ? List.generate(_itemCount, (i) => i) : null;
        }),
        tooltip: _reorderable ? 'Disable drag' : 'Enable drag',
        child: Icon(_reorderable ? Icons.lock_open : Icons.drag_indicator),
      ),
    );
  }

  /// SmoothGrid mode
  Widget _buildSmoothGrid() {
    return SmoothGrid.count(
      key: ValueKey(_activeGridSession.session.id),
      itemCount: _itemCount,
      sessionController: _activeGridSession,
      reorderable: _reorderable,
      addAutomaticKeepAlives: false,
      cacheExtent: 1200,
      findChildIndexCallback: _reorderable
          ? (key) {
              if (key is ValueKey<int>) {
                final index = _items.indexOf(key.value);
                return index < 0 ? null : index;
              }
              return null;
            }
          : null,
      crossAxisCount: _columns,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      padding: const EdgeInsets.all(6),
      itemExtentBuilder: _reorderable
          ? (index) => heightForIndex(_items[index])
          : (index) => heightForIndex(index),
      itemBuilder: (context, index) {
        final itemIndex = _reorderable ? _items[index] : index;
        return SmoothGridTile(
          key: ValueKey(itemIndex),
          child: DemoItemCard(index: itemIndex),
        );
      },
      onReorder: _reorderable
          ? (oldIndex, newIndex) {
              setState(() {
                final item = _items.removeAt(oldIndex);
                final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
                _items.insert(insertAt, item);
              });
            }
          : null,
      onTap: _reorderable ? null : (index) => _showSnack(context, index),
    );
  }

  /// ListView baseline — same DemoItemCard widgets for A/B comparison
  Widget _buildListView() {
    return ListView.builder(
      itemCount: _itemCount,
      cacheExtent: 1200,
      itemBuilder: (context, index) {
        return Padding(
          key: ValueKey('list_item_$index'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: SizedBox(
            height: heightForIndex(index),
            child: DemoItemCard(index: index),
          ),
        );
      },
    );
  }

  void _showSnack(BuildContext context, int index) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tapped #$index'),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(0)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

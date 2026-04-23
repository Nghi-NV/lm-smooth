import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

void main() {
  runApp(const SmoothGridExampleApp());
}

class SmoothGridExampleApp extends StatelessWidget {
  const SmoothGridExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lm_smooth Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GridDemoPage(itemCount: 1000),
    );
  }
}

// ==================================================
// Grid Demo Page
// ==================================================

/// Deterministic hash → height 80-280px. Zero allocation, pure function.
double _heightForIndex(int index) {
  final h = ((index * 2654435761) & 0xFFFFFFFF) % 200;
  return 80.0 + h;
}

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

  // Only used in reorderable mode — lazily initialized
  List<int>? _reorderItems;

  List<int> get _items => _reorderItems ??= List.generate(_itemCount, (i) => i);

  void _updateItemCount(int count) {
    setState(() {
      _itemCount = count;
      _reorderItems = _reorderable ? List.generate(count, (i) => i) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_fmt(_itemCount)} · $_columns col${_reorderable ? ' · Drag' : ''}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          // Column controls
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
      body: SmoothGrid(
        itemCount: _itemCount,
        reorderable: _reorderable,
        addAutomaticKeepAlives: false, // ← critical for 1M items
        delegate: SmoothGridDelegate.count(
          crossAxisCount: _columns,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          padding: const EdgeInsets.all(6),
          itemExtentBuilder: _reorderable
              ? (index) => _heightForIndex(_items[index])
              : (index) => _heightForIndex(index), // ← direct, no list lookup
        ),
        itemBuilder: (context, index) {
          final itemIndex = _reorderable ? _items[index] : index;
          return SmoothGridTile(child: _ItemCard(index: itemIndex));
        },
        onReorder: _reorderable
            ? (oldIndex, newIndex) {
                setState(() {
                  final item = _items.removeAt(oldIndex);
                  final insertAt = newIndex > oldIndex
                      ? newIndex - 1
                      : newIndex;
                  _items.insert(insertAt, item);
                });
              }
            : null,
        onTap: _reorderable
            ? null
            : (index) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tapped #$index'),
                    duration: const Duration(milliseconds: 400),
                  ),
                );
              },
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => setState(() {
          _reorderable = !_reorderable;
          _reorderItems = _reorderable
              ? List.generate(_itemCount, (i) => i)
              : null;
        }),
        tooltip: _reorderable ? 'Disable drag' : 'Enable drag',
        child: Icon(_reorderable ? Icons.lock_open : Icons.drag_indicator),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(0)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

// ==================================================
// Rich Item Card — Zero-allocation design
// ==================================================

const _categories = [
  'Nature',
  'Travel',
  'Food',
  'Art',
  'Music',
  'Tech',
  'Sport',
  'Fashion',
  'Photo',
  'Design',
];

const _icons = [
  Icons.park,
  Icons.flight,
  Icons.restaurant,
  Icons.palette,
  Icons.music_note,
  Icons.computer,
  Icons.sports_soccer,
  Icons.checkroom,
  Icons.camera_alt,
  Icons.brush,
];

// Pre-computed static colors — avoid per-frame allocation
const _iconColor = Color(0x33FFFFFF); // white 0.2 alpha
const _chipBgColor = Color(0x44000000); // black26
const _chipTextStyle = TextStyle(
  color: Color(0xB3FFFFFF), // white70
  fontSize: 10,
  fontWeight: FontWeight.w500,
);
const _titleTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
const _subtitleColor = Color(0x99FFFFFF); // white 0.6
const _heartColor = Color(0xCCFF5252); // redAccent 0.8
const _likesColor = Color(0xB3FFFFFF); // white 0.7

class _ItemCard extends StatelessWidget {
  final int index;

  const _ItemCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final hash = ((index * 2654435761) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final catIdx = hash % _categories.length;
    final likes = 10 + (hash % 990);

    // Two-tone gradient — HSLColor allocation here is unavoidable
    // but these are only computed once per item build, not per frame
    final baseColor = HSLColor.fromAHSL(1, hue, 0.6, 0.35).toColor();
    final accentColor = HSLColor.fromAHSL(
      1,
      (hue + 40) % 360,
      0.7,
      0.25,
    ).toColor();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, accentColor],
        ),
      ),
      child: Stack(
        children: [
          // Center icon
          Center(child: Icon(_icons[catIdx], size: 36, color: _iconColor)),

          // Top-right category chip
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _chipBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_categories[catIdx], style: _chipTextStyle),
            ),
          ),

          // Bottom frosted glass bar — GPU stress test with BackdropFilter
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  color: const Color(0x4D000000),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Item #$index',
                              style: _titleTextStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_categories[catIdx]} collection',
                              style: const TextStyle(
                                color: _subtitleColor,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.favorite, size: 14, color: _heartColor),
                      const SizedBox(width: 3),
                      Text(
                        '$likes',
                        style: const TextStyle(
                          color: _likesColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

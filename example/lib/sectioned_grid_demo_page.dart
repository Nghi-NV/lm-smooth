import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

import 'demo_common.dart';

class SectionedGridDemoPage extends StatefulWidget {
  const SectionedGridDemoPage({super.key});

  @override
  State<SectionedGridDemoPage> createState() => _SectionedGridDemoPageState();
}

class _SectionedGridDemoPageState extends State<SectionedGridDemoPage> {
  var _pinnedHeaders = true;
  var _dragSort = false;
  var _activeDragSection = 0;
  late final List<List<int>> _itemsBySection = [
    for (final section in _sections)
      List.generate(section.count, (index) => section.seed + index),
  ];

  static const _sections = [
    _DemoSection('Today', 'Fresh work', 40, 0, Color(0xFF00C2A8)),
    _DemoSection('Design', 'Blur stress', 60, 1000, Color(0xFF7C4DFF)),
    _DemoSection('Backlog', 'Large feed', 120, 2000, Color(0xFFFFB300)),
    _DemoSection('Archive', 'Older items', 80, 3000, Color(0xFFFF5252)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070A0F),
      appBar: AppBar(
        title: Text('Session grid · ${_pinnedHeaders ? 'pinned' : 'inline'}'),
        actions: [
          IconButton(
            tooltip: _dragSort ? 'Disable drag sort' : 'Enable drag sort',
            icon: Icon(_dragSort ? Icons.lock_open : Icons.drag_indicator),
            onPressed: () => setState(() => _dragSort = !_dragSort),
          ),
          IconButton(
            tooltip:
                _pinnedHeaders ? 'Disable pin header' : 'Enable pin header',
            icon: Icon(
              _pinnedHeaders ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            onPressed: _dragSort
                ? null
                : () => setState(() => _pinnedHeaders = !_pinnedHeaders),
          ),
        ],
      ),
      body: BackdropGroup(
        child: _dragSort ? _buildDragSortView() : _buildPinnedSessionGrid(),
      ),
    );
  }

  Widget _buildPinnedSessionGrid() {
    return SmoothSectionedGrid(
      sections: [
        for (final section in _sections)
          SmoothGridSection(id: section.title, itemCount: section.count),
      ],
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      cacheExtent: 1200,
      pinnedHeaders: _pinnedHeaders,
      pinnedHeaderExtent: 64,
      headerBuilder: (context, sectionIndex) {
        final section = _sections[sectionIndex];
        return _SessionHeader(section: section, sectionIndex: sectionIndex);
      },
      itemExtentBuilder: (sectionIndex, itemIndex) {
        final section = _sections[sectionIndex];
        return heightForIndex(section.seed + itemIndex);
      },
      itemBuilder: (context, sectionIndex, itemIndex) {
        final section = _sections[sectionIndex];
        return SmoothGridTile(
          child: DemoItemCard(index: section.seed + itemIndex),
        );
      },
    );
  }

  Widget _buildDragSortView() {
    final section = _sections[_activeDragSection];
    final items = _itemsBySection[_activeDragSection];
    return Column(
      children: [
        _SessionStrip(
          sections: _sections,
          itemCounts: [for (final items in _itemsBySection) items.length],
          activeIndex: _activeDragSection,
          onChanged: (index) => setState(() => _activeDragSection = index),
        ),
        SizedBox(
          height: 56,
          child: _SessionHeader(
            section: section,
            sectionIndex: _activeDragSection,
            dragEnabled: true,
          ),
        ),
        Expanded(
          child: SmoothGrid.count(
            key: ValueKey('drag_session_${section.title}'),
            itemCount: items.length,
            reorderable: true,
            cacheExtent: 1200,
            findChildIndexCallback: (key) {
              if (key is ValueKey<int>) {
                final index = items.indexOf(key.value);
                return index < 0 ? null : index;
              }
              return null;
            },
            crossAxisCount: 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            itemExtentBuilder: (index) => heightForIndex(items[index]),
            itemBuilder: (context, index) {
              final item = items[index];
              return SmoothGridTile(
                key: ValueKey(item),
                child: DemoItemCard(index: item),
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final item = items.removeAt(oldIndex);
                final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
                items.insert(insertAt, item);
              });
            },
          ),
        ),
      ],
    );
  }
}

class _SessionStrip extends StatelessWidget {
  final List<_DemoSection> sections;
  final List<int> itemCounts;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  const _SessionStrip({
    required this.sections,
    required this.itemCounts,
    required this.activeIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF070A0F),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          scrollDirection: Axis.horizontal,
          itemCount: sections.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final section = sections[index];
            final selected = index == activeIndex;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 136,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? section.color : const Color(0x24FFFFFF),
                    width: selected ? 1.4 : 1,
                  ),
                  gradient: LinearGradient(
                    colors: selected
                        ? [
                            demoColorWithAlpha(section.color, 0.42),
                            const Color(0xFF111A24),
                          ]
                        : const [Color(0x22111A24), Color(0x14111A24)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.radio_button_checked : Icons.circle,
                      color: selected ? section.color : Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${itemCounts[index]} items',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DemoSection {
  final String title;
  final String subtitle;
  final int count;
  final int seed;
  final Color color;

  const _DemoSection(
    this.title,
    this.subtitle,
    this.count,
    this.seed,
    this.color,
  );
}

class _SessionHeader extends StatelessWidget {
  final _DemoSection section;
  final int sectionIndex;
  final bool dragEnabled;

  const _SessionHeader({
    required this.section,
    required this.sectionIndex,
    this.dragEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF070A0F),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: demoColorWithAlpha(section.color, 0.45)),
            gradient: LinearGradient(
              colors: [
                demoColorWithAlpha(section.color, 0.38),
                const Color(0xE6101820),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: demoColorWithAlpha(section.color, 0.26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${sectionIndex + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        section.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xAFFFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DemoMetricChip(
                    icon: dragEnabled ? Icons.drag_indicator : Icons.grid_view,
                    label: '${section.count}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

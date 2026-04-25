import 'package:flutter/material.dart';

import 'demo_common.dart';
import 'grid_demo_page.dart';
import 'horizontal_demo_page.dart';
import 'sectioned_grid_demo_page.dart';
import 'smooth_list_demo_page.dart';
import 'smooth_table_demo_page.dart';

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
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('lm_smooth showcases'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DemoGradientBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              const DemoHeroHeader(
                title: 'Virtual Views Toolkit',
                subtitle:
                    'Heavy polished demos for grid, sessions, horizontal list and table.',
                icon: Icons.auto_awesome,
              ),
              _DemoTile(
                title: 'SmoothGrid stress demo',
                subtitle: 'Masonry, 1K–1M items, reorder, blur-heavy cards',
                icon: Icons.grid_view,
                accent: const Color(0xFF7C4DFF),
                builder: (_) => const GridDemoPage(itemCount: 1000),
              ),
              _DemoTile(
                title: 'Pinned session grid',
                subtitle:
                    'One active sticky session header inside a rich masonry feed',
                icon: Icons.view_agenda,
                accent: const Color(0xFF00BFA5),
                builder: (_) => const SectionedGridDemoPage(),
              ),
              _DemoTile(
                title: 'Horizontal showcase',
                subtitle:
                    'Horizontal SmoothList virtualization with premium cards',
                icon: Icons.swap_horiz,
                accent: const Color(0xFFFFB300),
                builder: (_) => const HorizontalDemoPage(),
              ),
              _DemoTile(
                title: 'SmoothList feed',
                subtitle:
                    'Variable row extents with frosted glass timeline cards',
                icon: Icons.view_list,
                accent: const Color(0xFF40C4FF),
                builder: (_) => const SmoothListDemoPage(),
              ),
              _DemoTile(
                title: 'SmoothTable analytics',
                subtitle: 'Pinned rows/columns with styled financial cells',
                icon: Icons.table_chart,
                accent: const Color(0xFFFF5252),
                builder: (_) => const SmoothTableDemoPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final WidgetBuilder builder;

  const _DemoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: builder)),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x22FFFFFF)),
                gradient: LinearGradient(
                  colors: [
                    demoColorWithAlpha(accent, 0.42),
                    const Color(0x1FFFFFFF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0x22FFFFFF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(color: Color(0xB3FFFFFF)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

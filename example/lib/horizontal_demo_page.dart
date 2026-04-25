import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

import 'demo_common.dart';

class HorizontalDemoPage extends StatefulWidget {
  const HorizontalDemoPage({super.key});

  @override
  State<HorizontalDemoPage> createState() => _HorizontalDemoPageState();
}

class _HorizontalDemoPageState extends State<HorizontalDemoPage> {
  final session = SmoothSessionController(id: 'horizontal-list-demo');

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
        title: AnimatedBuilder(
          animation: session,
          builder: (context, _) => Text(
            'Horizontal SmoothList · ${session.scrollOffset.toStringAsFixed(0)} px',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
      body: DemoGradientBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DemoHeroHeader(
                title: 'Horizontal Carousel Stress',
                subtitle: '50K horizontal premium cards with frosted overlays.',
                icon: Icons.view_carousel,
              ),
              Expanded(
                child: SmoothList(
                  itemCount: 50000,
                  scrollDirection: Axis.horizontal,
                  sessionController: session,
                  cacheExtent: 1200,
                  itemExtentBuilder: (index) => 190 + (index % 5) * 34,
                  itemBuilder: (context, index) {
                    final width = 190.0 + (index % 5) * 34;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 16, 4, 24),
                      child: SizedBox(
                        width: width,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DemoItemCard(index: index),
                            Positioned(
                              left: 12,
                              top: 12,
                              child: DemoMetricChip(
                                icon: Icons.auto_awesome,
                                label: 'Card $index',
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 54,
                              child: DemoMetricChip(
                                icon: Icons.width_normal,
                                label: '${width.round()}w',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

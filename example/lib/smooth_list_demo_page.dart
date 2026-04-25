import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

import 'demo_common.dart';

class SmoothListDemoPage extends StatefulWidget {
  const SmoothListDemoPage({super.key});

  @override
  State<SmoothListDemoPage> createState() => _SmoothListDemoPageState();
}

class _SmoothListDemoPageState extends State<SmoothListDemoPage> {
  final session = SmoothSessionController(id: 'smooth-list-demo');

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
            'SmoothList · ${session.scrollOffset.toStringAsFixed(0)} px',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
      body: DemoGradientBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const DemoHeroHeader(
                title: 'Virtual Feed Showcase',
                subtitle:
                    '50K variable rows with blur, gradients and saved offset.',
                icon: Icons.dynamic_feed,
              ),
              Expanded(
                child: SmoothList(
                  itemCount: 50000,
                  sessionController: session,
                  cacheExtent: 1200,
                  itemExtentBuilder: (index) => 104 + (index % 5) * 12,
                  itemBuilder: (context, index) {
                    return DemoFeedCard(
                      index: index,
                      progress: ((index * 37) % 100) / 100,
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

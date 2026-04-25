import 'dart:ui';

import 'package:flutter/material.dart';

/// Deterministic hash → height 80-280px. Zero allocation, pure function.
double heightForIndex(int index) {
  final h = ((index * 2654435761) & 0xFFFFFFFF) % 200;
  return 80.0 + h;
}

const demoCategories = [
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

const demoIcons = [
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

const _iconColor = Color(0x33FFFFFF);
const _chipBgColor = Color(0x44000000);
const _chipTextStyle = TextStyle(
  color: Color(0xB3FFFFFF),
  fontSize: 10,
  fontWeight: FontWeight.w500,
);
const _titleTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
const _subtitleColor = Color(0x99FFFFFF);
const _heartColor = Color(0xCCFF5252);
const _likesColor = Color(0xB3FFFFFF);

Color demoColorWithAlpha(Color color, double alpha) {
  return color.withAlpha((alpha.clamp(0.0, 1.0) * 255).round());
}

class DemoItemCard extends StatelessWidget {
  final int index;

  const DemoItemCard({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    final hash = ((index * 2654435761) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final catIdx = hash % demoCategories.length;
    final likes = 10 + (hash % 990);

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
          Center(child: Icon(demoIcons[catIdx], size: 36, color: _iconColor)),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _chipBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(demoCategories[catIdx], style: _chipTextStyle),
            ),
          ),
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
                              '${demoCategories[catIdx]} collection',
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

class DemoGradientBackdrop extends StatelessWidget {
  final Widget child;

  const DemoGradientBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.35,
          colors: [Color(0xFF44318D), Color(0xFF101820), Color(0xFF070A0F)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: child,
    );
  }
}

class DemoHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> trailing;

  const DemoHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x2EFFFFFF)),
              gradient: const LinearGradient(
                colors: [Color(0x66FFFFFF), Color(0x14000000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xB3FFFFFF),
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DemoMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const DemoMetricChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0x24FFFFFF),
            border: Border.all(color: const Color(0x24FFFFFF)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white70),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DemoFeedCard extends StatelessWidget {
  final int index;
  final double progress;

  const DemoFeedCard({super.key, required this.index, required this.progress});

  @override
  Widget build(BuildContext context) {
    final hash = ((index * 2654435761) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final category = demoCategories[hash % demoCategories.length];
    final color = HSLColor.fromAHSL(1, hue, 0.58, 0.48).toColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x22FFFFFF)),
              gradient: LinearGradient(
                colors: [
                  demoColorWithAlpha(color, 0.62),
                  const Color(0x29212A38),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: DemoItemCard(index: index),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$category sprint card #$index',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            DemoMetricChip(
                              icon: Icons.bolt,
                              label: '${(progress * 100).round()}%',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: const Color(0x26FFFFFF),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            const DemoMetricChip(
                              icon: Icons.blur_on,
                              label: 'Backdrop blur',
                            ),
                            const SizedBox(width: 6),
                            DemoMetricChip(
                              icon: Icons.layers,
                              label: '${80 + index % 140} px',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

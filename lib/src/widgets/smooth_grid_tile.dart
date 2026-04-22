import 'package:flutter/widgets.dart';

/// A wrapper widget for items inside [SmoothGrid].
///
/// Automatically wraps children with:
/// - [RepaintBoundary] to isolate repaint scope
/// - [ValueKey] for element reuse during scroll recycling
///
/// Usage:
/// ```dart
/// SmoothGridTile(
///   child: Column(children: [
///     Icon(Icons.star),
///     Text('Item'),
///   ]),
/// )
/// ```
class SmoothGridTile extends StatelessWidget {
  final Widget child;

  /// Whether to add a [RepaintBoundary] around this tile.
  /// Default: true. Disable for very simple tiles to reduce layer count.
  final bool addRepaintBoundary;

  const SmoothGridTile({
    super.key,
    required this.child,
    this.addRepaintBoundary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (addRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}

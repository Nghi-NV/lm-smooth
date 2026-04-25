/// lm_smooth — High-performance staggered/masonry grid view for Flutter.
///
/// Renders 1M+ items smoothly on iOS and Android via:
/// - Pre-computed masonry layout with O(n) Shortest-Column-First algorithm
/// - Custom RenderSliver with O(log n) spatial index for viewport queries
/// - Float64List layout cache with zero GC pressure
/// - Isolate offloading for large datasets (>100K items)
///
/// ## Quick Start
/// ```dart
/// import 'package:lm_smooth/lm_smooth.dart';
///
/// SmoothGrid(
///   itemCount: 1000000,
///   itemBuilder: (context, index) => SmoothGridTile(
///     child: Text('Item $index'),
///   ),
///   delegate: SmoothGridDelegate.count(
///     crossAxisCount: 3,
///     mainAxisSpacing: 8,
///     crossAxisSpacing: 8,
///     itemExtentBuilder: (index) => 100 + (index % 5) * 30.0,
///   ),
///   onTap: (index) => print('Tapped $index'),
///   onLongPress: (index) => print('Long pressed $index'),
/// )
/// ```
library;

// Core
export 'src/core/layout_cache.dart';
export 'src/core/masonry_layout_engine.dart'
    show MasonryLayoutEngine, MasonryLayoutConfig, SmoothItemExtentBuilder;
export 'src/core/spatial_index.dart';
export 'src/core/layout_isolate.dart';
export 'src/core/smooth_geometry.dart';
export 'src/core/smooth_session.dart';

// Rendering
export 'src/rendering/render_smooth_grid.dart';
export 'src/rendering/smooth_grid_parent_data.dart';
export 'src/rendering/smooth_sliver_grid_delegate.dart';

// Widgets
export 'src/widgets/smooth_grid.dart';
export 'src/widgets/smooth_grid_delegate.dart';
export 'src/widgets/smooth_list.dart';
export 'src/widgets/smooth_table.dart';
export 'src/widgets/smooth_grid_tile.dart';

// Interaction
export 'src/interaction/gesture_recognizer.dart';
export 'src/interaction/drag_engine.dart';
export 'src/interaction/hit_tester.dart';
export 'src/interaction/auto_scroller.dart';

// Utils
export 'src/utils/constants.dart';

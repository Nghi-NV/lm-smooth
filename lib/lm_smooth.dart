/// High-performance virtualized masonry views for Flutter.
///
/// `lm_smooth` is designed for feeds and dashboards where item extents are
/// known ahead of time. The grid can precompute geometry, avoid runtime child
/// measurement, and keep scroll/reorder work predictable for large datasets.
library;

export 'src/core/masonry_layout_engine.dart' show SmoothItemExtentBuilder;
export 'src/core/smooth_session.dart';
export 'src/interaction/drag_engine.dart' show SmoothReorderConfig;
export 'src/widgets/smooth_grid.dart';
export 'src/widgets/smooth_grid_delegate.dart';
export 'src/widgets/smooth_grid_tile.dart';
export 'src/widgets/smooth_list.dart';
export 'src/widgets/smooth_table.dart';

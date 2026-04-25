# lm_smooth

High-performance staggered/masonry grid for Flutter, built for large datasets and smooth scrolling.

`lm_smooth` uses a custom `RenderSliver`, precomputed layout, a spatial index, and optional isolate-based layout computation so the grid can stay responsive even with very large item counts.

![lm_smooth example grid](doc/screenshots/example-grid.png)

## Features

- Masonry / staggered grid layout with fixed column count
- Custom render pipeline instead of `GridView` composition overhead
- Precomputed item geometry with O(1) rect lookup
- Spatial index for fast visible-range queries
- Optional isolate offload for very large datasets
- Reorder support with long-press drag, preview translation, and edge auto-scroll
- Optional view sessions for restoring scroll/selection/reorder draft state
- Sectioned masonry grids with multiple in-scroll session headers
- Experimental `SmoothList` and `SmoothTable` virtualized views
- Works well for feeds, galleries, boards, and uneven card layouts

## When To Use

Use `lm_smooth` when:

- your items have uneven heights
- you already know each item's extent up front
- your dataset is large enough that normal staggered/grid solutions start dropping frames
- you want a masonry grid with reorder support

Do not use it if your layout depends on measuring child widgets at runtime. This package is designed around precomputed heights.

## Installation

Add the dependency:

```yaml
dependencies:
  lm_smooth: ^0.1.0
```

Then import it:

```dart
import 'package:lm_smooth/lm_smooth.dart';
```

## Pub.dev Highlights

- Designed for uneven-height, masonry-style feeds
- Handles very large item counts with cached geometry and indexed visibility queries
- Includes built-in reorder support instead of requiring a separate drag-sort layer
- Ships with a runnable example app in [`example/`](./example)

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:lm_smooth/lm_smooth.dart';

class DemoPage extends StatelessWidget {
  DemoPage({super.key});

  final items = List.generate(1000, (i) => i);

  double _heightFor(int index) {
    return 100 + (index % 5) * 24.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SmoothGrid(
        itemCount: items.length,
        delegate: SmoothGridDelegate.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          padding: const EdgeInsets.all(8),
          itemExtentBuilder: (index) => _heightFor(items[index]),
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return SmoothGridTile(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blueGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text('Item $item'),
            ),
          );
        },
        onTap: (index) {
          debugPrint('Tapped ${items[index]}');
        },
      ),
    );
  }
}
```

## Reorder Example

To enable drag reorder, pass `reorderable: true` and update your data source inside `onReorder`.

```dart
class ReorderDemo extends StatefulWidget {
  const ReorderDemo({super.key});

  @override
  State<ReorderDemo> createState() => _ReorderDemoState();
}

class _ReorderDemoState extends State<ReorderDemo> {
  final items = List.generate(200, (i) => i);

  double _heightFor(int index) => 80 + (index % 6) * 20.0;

  @override
  Widget build(BuildContext context) {
    return SmoothGrid(
      itemCount: items.length,
      reorderable: true,
      reorderConfig: const SmoothReorderConfig(
        longPressDelay: Duration(milliseconds: 220),
      ),
      delegate: SmoothGridDelegate.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.all(8),
        itemExtentBuilder: (index) => _heightFor(items[index]),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return SmoothGridTile(
          child: Card(
            child: Center(child: Text('Item $item')),
          ),
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          final item = items.removeAt(oldIndex);
          final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
          items.insert(insertAt, item);
        });
      },
    );
  }
}
```

## API Overview

### `SmoothGrid`

Main widget for rendering the masonry grid.

Important parameters:

- `itemCount`: total item count
- `itemBuilder`: builds visible items only
- `delegate`: grid layout configuration
- `controller`: optional `ScrollController`
- `reorderable`: enables long-press drag reorder
- `onReorder`: commit reorder back into your data source
- `onTap`: optional tap callback
- `onLongPress`: optional long-press callback when reorder is disabled
- `cacheExtent`: overscan area
- `useIsolate`: force or disable isolate layout computation
- `sessionController`: optional `SmoothSessionController` for view-state restore

### `SmoothSectionedGrid`

SmoothGrid-like masonry layout for grouped feeds where each session/category/day
needs its own header inside the same scrollable viewport.

Important parameters:

- `sections`: ordered list of `SmoothGridSection` groups
- `headerBuilder`: builds each in-scroll section header
- `itemBuilder`: builds visible items for a specific section
- `itemExtentBuilder`: returns each section item's known height
- `crossAxisCount`, spacing, and `padding`: shared masonry layout settings
- `pinnedHeaders` and `pinnedHeaderExtent`: keep the active session header sticky while scrolling

### `SmoothList`

Known-extent virtualized list with optional session restore and one-column reorder.

### `SmoothTable`

Early 2D virtualized table API for large row/column datasets. Rows are virtualized vertically and cells are culled horizontally.

### `SmoothGridDelegate.count`

Layout delegate with:

- `crossAxisCount`
- `mainAxisSpacing`
- `crossAxisSpacing`
- `padding`
- `itemExtentBuilder`

### `SmoothReorderConfig`

Drag-reorder tuning:

- `longPressDelay`
- `liftScale`
- `ghostOpacity`
- `settleDuration`
- `translateDuration`
- `edgeScrollZone`
- `maxAutoScrollVelocity`
- `collisionHysteresis`

## Performance Notes

This package is fast because it avoids runtime measurement. To get good results:

- keep `itemExtentBuilder` cheap and deterministic
- precompute heights from your model data when possible
- avoid doing network/image metadata work inside `itemExtentBuilder`
- use stable keys for stateful children when reordering
- prefer simple item trees for very large feeds

For very large datasets, `lm_smooth` can offload layout computation to an isolate automatically.

## Current Constraints

- reorder support is currently focused on vertical `SmoothGrid`
- the layout model assumes heights are known in advance
- fixed-column masonry is supported; arbitrary adaptive breakpoints are not built in yet

## Example App

A runnable example is included in [`example/lib/main.dart`](./example/lib/main.dart). It demonstrates:

- 1K to 1M items
- grid/list comparison
- column switching
- reorder mode
- multiple session headers inside one scroll
- horizontal `SmoothList` virtualization
- varied card heights

Example screens are split into focused files:

- [`grid_demo_page.dart`](./example/lib/grid_demo_page.dart): SmoothGrid stress, reorder, sessions
- [`sectioned_grid_demo_page.dart`](./example/lib/sectioned_grid_demo_page.dart): pinned session headers in one scroll
- [`horizontal_demo_page.dart`](./example/lib/horizontal_demo_page.dart): horizontal SmoothList
- [`smooth_list_demo_page.dart`](./example/lib/smooth_list_demo_page.dart): vertical SmoothList
- [`smooth_table_demo_page.dart`](./example/lib/smooth_table_demo_page.dart): pinned SmoothTable

Run it with:

```bash
cd example
flutter run
```

## Publish Checklist

Before publishing, verify:

- `README.md` matches the current public API
- `CHANGELOG.md` describes the release accurately
- `pubspec.yaml` has correct repository metadata
- `flutter test` passes
- `dart pub publish --dry-run` completes without warnings you care about

## Why This Package Exists

Most Flutter masonry/grid solutions are convenient, but once the dataset gets large, scroll and layout cost become the bottleneck. `lm_smooth` takes a lower-level approach:

- custom sliver rendering
- cached geometry
- range queries via spatial index
- minimal per-frame work during scroll

The goal is not just feature parity. The goal is predictable performance.

## Contributing

Issues and PRs are welcome. Useful contributions include:

- performance benchmarks
- reorder UX polish
- more tests around large datasets
- docs and example improvements

## License

MIT

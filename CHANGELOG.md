## 0.1.0

Initial public release.

### Added

- `SmoothGrid` and `SmoothGrid.count` for fixed-column masonry layouts with known item extents.
- Lazy item building backed by a custom render sliver, layout cache, and spatial index.
- Optional isolate-based layout computation for very large grids.
- Long-press drag reorder for vertical `SmoothGrid`, including preview translation, settle animation, and edge auto-scroll.
- `SmoothSectionedGrid` for grouped masonry feeds with optional pinned section headers.
- `SmoothSessionController` for saving and restoring view scroll state.
- `SmoothList` for known-extent vertical or horizontal lists.
- `SmoothTable` for large row/column datasets with pinned rows and columns.
- Example app with grid, sectioned grid, horizontal list, vertical list, and table demos.
- Unit, widget, integration, and benchmark coverage for layout, scrolling, and reorder behavior.

### Notes

- Item extents must be known ahead of time; runtime child measurement is intentionally out of scope.
- Cross-section reorder and horizontal masonry reorder are not part of this initial release.

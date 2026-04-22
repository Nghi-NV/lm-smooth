/// Touch slop — minimum movement to start a drag gesture.
const double kSmoothDragSlop = 18.0;

/// Tap timeout — maximum duration for a tap gesture.
const Duration kSmoothTapTimeout = Duration(milliseconds: 150);

/// Long press timeout — minimum hold duration for long press.
const Duration kSmoothLongPressTimeout = Duration(milliseconds: 500);

/// Auto-scroll edge threshold — distance from viewport edge.
const double kSmoothAutoScrollEdge = 80.0;

/// Auto-scroll maximum speed (pixels per frame at 60 FPS).
const double kSmoothAutoScrollSpeed = 10.0;

/// Default overscan/cache extent (pixels beyond viewport).
const double kSmoothDefaultCacheExtent = 500.0;

/// Default chunk size for layout cache (must be power of 2).
const int kSmoothDefaultChunkSize = 4096;

/// Item count threshold for using Isolate computation.
const int kSmoothIsolateThreshold = 100000;

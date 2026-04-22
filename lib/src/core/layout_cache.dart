import 'dart:typed_data';
import 'dart:ui' show Rect;

/// Chunk-based layout cache using [Float64List] for zero-GC-pressure storage.
///
/// Each item occupies 4 doubles (x, y, width, height) = 32 bytes.
/// Items are stored in chunks of [chunkSize] to avoid single huge allocation.
///
/// For 1M items: ~32MB total — acceptable on mobile.
class LayoutCache {
  /// Number of items per chunk. Power of 2 for fast bit-shift division.
  static const int kDefaultChunkSize = 4096;

  /// Number of doubles per item: x, y, w, h
  static const int _stride = 4;

  final int chunkSize;
  final int _chunkShift;
  final int _chunkMask;
  final List<Float64List> _chunks = [];

  int _totalItems = 0;
  double _totalHeight = 0;

  /// Creates a [LayoutCache] with the given [chunkSize].
  /// [chunkSize] must be a power of 2.
  LayoutCache({this.chunkSize = kDefaultChunkSize})
      : _chunkShift = _log2(chunkSize),
        _chunkMask = chunkSize - 1 {
    assert(chunkSize > 0 && (chunkSize & (chunkSize - 1)) == 0,
        'chunkSize must be a power of 2');
  }

  /// Total number of items stored.
  int get totalItems => _totalItems;

  /// Total scrollable height (max y + height across all items).
  double get totalHeight => _totalHeight;

  /// Returns the layout [Rect] for item at [index].
  ///
  /// This is O(1) — direct array access with bit shifts.
  Rect getRect(int index) {
    assert(index >= 0 && index < _totalItems, 'Index $index out of range [0, $_totalItems)');
    final chunkIdx = index >> _chunkShift;
    final offset = (index & _chunkMask) * _stride;
    final chunk = _chunks[chunkIdx];
    return Rect.fromLTWH(
      chunk[offset],
      chunk[offset + 1],
      chunk[offset + 2],
      chunk[offset + 3],
    );
  }

  /// Returns only the Y offset for item at [index]. O(1).
  double getY(int index) {
    final chunkIdx = index >> _chunkShift;
    final offset = (index & _chunkMask) * _stride;
    return _chunks[chunkIdx][offset + 1];
  }

  /// Returns Y + Height (bottom edge) for item at [index]. O(1).
  double getBottom(int index) {
    final chunkIdx = index >> _chunkShift;
    final offset = (index & _chunkMask) * _stride;
    final chunk = _chunks[chunkIdx];
    return chunk[offset + 1] + chunk[offset + 3];
  }

  /// Sets the layout rect for item at [index].
  void setRect(int index, double x, double y, double w, double h) {
    _ensureCapacity(index + 1);
    final chunkIdx = index >> _chunkShift;
    final offset = (index & _chunkMask) * _stride;
    final chunk = _chunks[chunkIdx];
    chunk[offset] = x;
    chunk[offset + 1] = y;
    chunk[offset + 2] = w;
    chunk[offset + 3] = h;

    if (index >= _totalItems) {
      _totalItems = index + 1;
    }

    final bottom = y + h;
    if (bottom > _totalHeight) {
      _totalHeight = bottom;
    }
  }

  /// Bulk-set layout data from a pre-computed [Float64List].
  ///
  /// [data] must have length = itemCount * 4.
  /// This is used for Isolate transfer via [TransferableTypedData].
  void setFromFlatList(Float64List data, int itemCount) {
    _totalItems = itemCount;
    _chunks.clear();
    _totalHeight = 0;

    final itemsPerChunk = chunkSize;
    var remaining = itemCount;
    var srcOffset = 0;

    while (remaining > 0) {
      final count = remaining < itemsPerChunk ? remaining : itemsPerChunk;
      final chunk = Float64List(itemsPerChunk * _stride);

      // Copy data into chunk
      final copyLen = count * _stride;
      for (var i = 0; i < copyLen; i++) {
        chunk[i] = data[srcOffset + i];
      }

      _chunks.add(chunk);
      srcOffset += copyLen;
      remaining -= count;
    }

    // Compute total height
    _recomputeTotalHeight();
  }

  /// Exports all layout data as a flat [Float64List].
  /// Useful for Isolate transfer.
  Float64List toFlatList() {
    final result = Float64List(_totalItems * _stride);
    var dstOffset = 0;

    for (var chunkIdx = 0; chunkIdx < _chunks.length; chunkIdx++) {
      final chunk = _chunks[chunkIdx];
      final itemsInChunk = chunkIdx == _chunks.length - 1
          ? _totalItems - chunkIdx * chunkSize
          : chunkSize;
      final copyLen = itemsInChunk * _stride;

      for (var i = 0; i < copyLen; i++) {
        result[dstOffset + i] = chunk[i];
      }
      dstOffset += copyLen;
    }

    return result;
  }

  /// Clears all data and releases chunk memory.
  void clear() {
    _chunks.clear();
    _totalItems = 0;
    _totalHeight = 0;
  }

  /// Invalidates layout from [startIndex] onwards.
  /// Keeps data before [startIndex] intact and shrinks [_totalItems].
  void invalidateFrom(int startIndex) {
    if (startIndex >= _totalItems) return;
    _totalItems = startIndex;

    // Remove unnecessary chunks
    final neededChunks = (startIndex + chunkSize - 1) >> _chunkShift;
    while (_chunks.length > neededChunks + 1) {
      _chunks.removeLast();
    }

    _recomputeTotalHeight();
  }

  void _ensureCapacity(int requiredItems) {
    final requiredChunks = ((requiredItems - 1) >> _chunkShift) + 1;
    while (_chunks.length < requiredChunks) {
      _chunks.add(Float64List(chunkSize * _stride));
    }
  }

  void _recomputeTotalHeight() {
    _totalHeight = 0;
    for (var i = 0; i < _totalItems; i++) {
      final bottom = getBottom(i);
      if (bottom > _totalHeight) {
        _totalHeight = bottom;
      }
    }
  }

  static int _log2(int value) {
    var result = 0;
    var v = value;
    while (v > 1) {
      v >>= 1;
      result++;
    }
    return result;
  }
}

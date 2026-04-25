import 'package:flutter/widgets.dart';

/// Draft reorder state persisted by a smooth view session.
class SmoothReorderDraft {
  final int oldIndex;
  final int targetIndex;

  const SmoothReorderDraft({required this.oldIndex, required this.targetIndex});
}

/// Serializable-ish view state for Smooth virtualized widgets.
class SmoothViewSession {
  final String id;
  final double scrollOffset;
  final Set<Object> selectedKeys;
  final SmoothReorderDraft? reorderDraft;
  final Object? layoutCacheKey;
  final Size? viewportSize;

  const SmoothViewSession({
    required this.id,
    this.scrollOffset = 0,
    this.selectedKeys = const {},
    this.reorderDraft,
    this.layoutCacheKey,
    this.viewportSize,
  });

  SmoothViewSession copyWith({
    String? id,
    double? scrollOffset,
    Set<Object>? selectedKeys,
    SmoothReorderDraft? reorderDraft,
    bool clearReorderDraft = false,
    Object? layoutCacheKey,
    Size? viewportSize,
  }) {
    return SmoothViewSession(
      id: id ?? this.id,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      selectedKeys: selectedKeys ?? this.selectedKeys,
      reorderDraft: clearReorderDraft
          ? null
          : reorderDraft ?? this.reorderDraft,
      layoutCacheKey: layoutCacheKey ?? this.layoutCacheKey,
      viewportSize: viewportSize ?? this.viewportSize,
    );
  }
}

/// Controller that saves/restores per-view state without owning item data.
class SmoothSessionController extends ChangeNotifier {
  SmoothViewSession _session;
  ScrollController? _attachedController;

  SmoothSessionController({required String id})
    : _session = SmoothViewSession(id: id);

  SmoothViewSession get session => _session;
  double get scrollOffset => _session.scrollOffset;

  void attachScrollController(ScrollController controller) {
    if (identical(_attachedController, controller)) return;
    detachScrollController();
    _attachedController = controller;
    controller.addListener(_syncFromScrollController);
  }

  void detachScrollController() {
    final controller = _attachedController;
    if (controller == null) return;
    if (controller.hasClients) save(scrollOffset: controller.offset);
    controller.removeListener(_syncFromScrollController);
    _attachedController = null;
  }

  SmoothViewSession save({
    double? scrollOffset,
    Set<Object>? selectedKeys,
    SmoothReorderDraft? reorderDraft,
    bool clearReorderDraft = false,
    Object? layoutCacheKey,
    Size? viewportSize,
  }) {
    final next = _session.copyWith(
      scrollOffset: scrollOffset,
      selectedKeys: selectedKeys,
      reorderDraft: reorderDraft,
      clearReorderDraft: clearReorderDraft,
      layoutCacheKey: layoutCacheKey,
      viewportSize: viewportSize,
    );
    if (next == _session) return _session;
    _session = next;
    notifyListeners();
    return _session;
  }

  void restore(SmoothViewSession session) {
    _session = session;
    jumpToSavedOffset();
    notifyListeners();
  }

  void clear() {
    _session = SmoothViewSession(id: _session.id);
    notifyListeners();
  }

  void jumpToSavedOffset() {
    final controller = _attachedController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final target = _session.scrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    controller.jumpTo(target);
  }

  void _syncFromScrollController() {
    final controller = _attachedController;
    if (controller == null || !controller.hasClients) return;
    _session = _session.copyWith(scrollOffset: controller.offset);
  }

  @override
  void dispose() {
    detachScrollController();
    super.dispose();
  }
}

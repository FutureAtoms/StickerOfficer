/// Status of a single item in the bulk edit queue.
enum BulkEditItemStatus { pending, edited, skipped, removed }

/// Represents a single image in the bulk edit queue.
class BulkEditItem {
  final String originalPath;
  final BulkEditItemStatus status;
  final String? savedPath;

  const BulkEditItem({
    required this.originalPath,
    this.status = BulkEditItemStatus.pending,
    this.savedPath,
  });

  BulkEditItem copyWith({
    String? originalPath,
    BulkEditItemStatus? status,
    String? savedPath,
  }) {
    return BulkEditItem(
      originalPath: originalPath ?? this.originalPath,
      status: status ?? this.status,
      savedPath: savedPath ?? this.savedPath,
    );
  }

  @override
  String toString() =>
      'BulkEditItem(path: $originalPath, status: $status, saved: $savedPath)';
}

/// Manages a queue of images for bulk editing.
///
/// Items advance through the queue one at a time. Each item can be
/// edited (saved with a new path), skipped (original used), or removed.
class BulkEditQueue {
  final List<BulkEditItem> _items;
  int _currentIndex;

  BulkEditQueue(List<String> paths)
    : _items = paths.map((p) => BulkEditItem(originalPath: p)).toList(),
      _currentIndex = 0;

  /// All items in the queue.
  List<BulkEditItem> get items => List.unmodifiable(_items);

  /// Total number of items.
  int get total => _items.length;

  /// Whether the queue has been fully processed.
  bool get isComplete => _currentIndex >= _items.length;

  /// The current item, or null if complete.
  BulkEditItem? get currentItem => isComplete ? null : _items[_currentIndex];

  /// Current position (0-based).
  int get currentIndex => _currentIndex;

  /// Number of remaining (unprocessed) items.
  int get remaining => _items.length - _currentIndex;

  /// Count of items with a specific status.
  int countByStatus(BulkEditItemStatus status) =>
      _items.where((item) => item.status == status).length;

  /// Number of items that were edited or skipped (added to pack).
  int get savedCount =>
      countByStatus(BulkEditItemStatus.edited) +
      countByStatus(BulkEditItemStatus.skipped);

  /// Marks the current item with the given status and optional saved path,
  /// then advances to the next non-removed pending item.
  void markCurrentAndAdvance(BulkEditItemStatus status, {String? savedPath}) {
    if (isComplete) return;
    _items[_currentIndex] = _items[_currentIndex].copyWith(
      status: status,
      savedPath: savedPath,
    );
    _advance();
  }

  /// Advances past any already-processed items to find the next pending one.
  void _advance() {
    _currentIndex++;
    // Skip past any items that were already removed
    while (_currentIndex < _items.length &&
        _items[_currentIndex].status == BulkEditItemStatus.removed) {
      _currentIndex++;
    }
  }
}

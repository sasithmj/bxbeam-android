import 'dart:async';
import '../data/models/schedule_item.dart';

/// The PlaybackEngine acts as a central Ticker managing two queues:
/// a Default Loop and a Priority Queue.
class PlaybackEngine {
  Timer? _ticker;
  
  List<ScheduleItem> _defaultLoop = [];
  List<ScheduleItem> _priorityQueue = [];
  
  int _currentDefaultLoopIndex = 0;
  DateTime? _currentItemStartTime;
  ScheduleItem? _currentPlayingItem;

  // Stream controller to emit the currently playing URL to the presentation layer (BLoC)
  final StreamController<String> _currentUrlController = StreamController<String>.broadcast();
  Stream<String> get currentUrlStream => _currentUrlController.stream;

  /// Initialize the engine with the cached schedules from Isar
  void updateSchedules({
    required List<ScheduleItem> defaultLoop,
    required List<ScheduleItem> priorityQueue,
  }) {
    _defaultLoop = defaultLoop;
    _priorityQueue = priorityQueue;
    
    // Start the ticker (1s interval) if not already running
    _ticker ??= Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _onTick(Timer timer) {
    final now = DateTime.now();

    // 1. Conflict Resolution: Check Priority Queue first
    ScheduleItem? activePriorityItem;
    for (final item in _priorityQueue) {
      if (item.startTime != null && item.isPriority) {
        final endTime = item.startTime!.add(Duration(seconds: item.durationSeconds));
        // If currentTime falls within the scheduled item's time range
        if (now.isAfter(item.startTime!) && now.isBefore(endTime)) {
          activePriorityItem = item;
          break;
        }
      }
    }

    if (activePriorityItem != null) {
      // Play priority item if it's not the one currently playing
      if (_currentPlayingItem?.id != activePriorityItem.id) {
        _playItem(activePriorityItem);
      }
      return; // Skip default loop logic while priority item is playing
    }

    // 2. Handle Default Loop (Circular Buffer)
    if (_defaultLoop.isEmpty) return;

    // If we were playing nothing, or we were playing a priority item and its time elapsed
    if (_currentPlayingItem == null || _currentPlayingItem!.isPriority) {
      _playDefaultLoopItem();
    } else {
      // Check if current default item has finished its duration
      if (_currentItemStartTime != null) {
        final elapsed = now.difference(_currentItemStartTime!).inSeconds;
        if (elapsed >= _currentPlayingItem!.durationSeconds) {
          // Move to next item in the circular buffer
          _currentDefaultLoopIndex = (_currentDefaultLoopIndex + 1) % _defaultLoop.length;
          _playDefaultLoopItem();
        }
      }
    }
  }

  void _playDefaultLoopItem() {
    if (_defaultLoop.isEmpty) return;
    final itemToPlay = _defaultLoop[_currentDefaultLoopIndex];
    _playItem(itemToPlay);
  }

  void _playItem(ScheduleItem item) {
    _currentPlayingItem = item;
    _currentItemStartTime = DateTime.now();
    _currentUrlController.add(item.url);
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _currentUrlController.close();
  }
}

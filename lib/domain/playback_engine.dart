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
    
    if (defaultLoop.isEmpty && priorityQueue.isEmpty) {
      _currentPlayingItem = null;
      _currentItemStartTime = null;
    }
    
    // Start the ticker (1s interval) if not already running
    _ticker ??= Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _onTick(Timer timer) {
    final now = DateTime.now();

    // 1. Conflict Resolution: Check Priority Queue first
    ScheduleItem? activePriorityItem;
    for (final item in _priorityQueue) {
      if (item.startTime != null && item.isPriority) {
        // Construct the start time window for today
        final todayStart = DateTime(
          now.year,
          now.month,
          now.day,
          item.startTime!.hour,
          item.startTime!.minute,
          item.startTime!.second,
        );
        final todayEnd = todayStart.add(Duration(seconds: item.durationSeconds));

        // Construct the start time window for yesterday (to handle midnight-crossing schedules)
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));
        final yesterdayEnd = yesterdayStart.add(Duration(seconds: item.durationSeconds));

        final isTodayActive = now.isAfter(todayStart) && now.isBefore(todayEnd);
        final isYesterdayActive = now.isAfter(yesterdayStart) && now.isBefore(yesterdayEnd);

        print("PRIORITY_CHECK: title='${item.title}', "
              "originalStart='${item.startTime}', "
              "todayStart='$todayStart', todayEnd='$todayEnd', "
              "now='$now', "
              "isTodayActive=$isTodayActive, isYesterdayActive=$isYesterdayActive");

        // If currentTime falls within either the today or yesterday daily window
        if (isTodayActive || isYesterdayActive) {
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

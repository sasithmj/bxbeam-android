import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/playback_engine.dart';
import '../../data/services/isar_service.dart';
import 'playback_event.dart';
import 'playback_state.dart';

class PlaybackBloc extends Bloc<PlaybackEvent, PlaybackState> {
  final PlaybackEngine _playbackEngine;
  final IsarService _isarService;
  StreamSubscription<String>? _urlSubscription;

  PlaybackBloc({
    required PlaybackEngine playbackEngine,
    required IsarService isarService,
  })  : _playbackEngine = playbackEngine,
        _isarService = isarService,
        super(PlaybackInitial()) {
    
    // Register Event Handlers
    on<PlaybackStarted>(_onPlaybackStarted);
    on<PlaybackUrlUpdated>(_onPlaybackUrlUpdated);
    on<PlaybackSchedulesUpdated>(_onPlaybackSchedulesUpdated);

    // Listen to the engine's stream and pass it to the BLoC as events
    _urlSubscription = _playbackEngine.currentUrlStream.listen((url) {
      add(PlaybackUrlUpdated(url));
    });
  }

  Future<void> _onPlaybackStarted(PlaybackStarted event, Emitter<PlaybackState> emit) async {
    emit(PlaybackLoading());
    try {
      // 1. Fetch cached schedules from the local database
      final defaultLoop = await _isarService.getDefaultLoop();
      final priorityQueue = await _isarService.getPriorityQueue();

      if (defaultLoop.isEmpty && priorityQueue.isEmpty) {
        emit(PlaybackDeactivated());
        return;
      }

      // 2. Feed the schedules into the engine
      _playbackEngine.updateSchedules(
        defaultLoop: defaultLoop,
        priorityQueue: priorityQueue,
      );
      
      // Note: We don't emit a URL state yet. 
      // The PlaybackEngine's ticker will naturally emit a new URL on its next tick, 
      // triggering `PlaybackUrlUpdated`.
    } catch (e) {
      emit(PlaybackError("Failed to initialize playback from cache: $e"));
    }
  }

  void _onPlaybackUrlUpdated(PlaybackUrlUpdated event, Emitter<PlaybackState> emit) {
    // Tell the presentation layer (WebView) what URL to load!
    emit(PlaybackPlaying(event.url));
  }

  Future<void> _onPlaybackSchedulesUpdated(PlaybackSchedulesUpdated event, Emitter<PlaybackState> emit) async {
    try {
      // In a full implementation, you'd trigger a REST request here, 
      // save the response via _isarService.saveScheduleItems(newItems), 
      // and then reload the data:

      // For now, we just reload whatever is currently in Isar:
      final defaultLoop = await _isarService.getDefaultLoop();
      final priorityQueue = await _isarService.getPriorityQueue();

      if (defaultLoop.isEmpty && priorityQueue.isEmpty) {
        emit(PlaybackDeactivated());
        return;
      }

      _playbackEngine.updateSchedules(
        defaultLoop: defaultLoop,
        priorityQueue: priorityQueue,
      );
    } catch (e) {
      // Depending on requirements, we can silently fail or emit a warning state.
      // Often in an industrial kiosk, we want to fail silently and keep playing 
      // whatever is cached rather than showing a breaking error page.
    }
  }

  @override
  Future<void> close() {
    _urlSubscription?.cancel();
    _playbackEngine.dispose(); // Ensure the ticker stops when BLoC is destroyed
    return super.close();
  }
}

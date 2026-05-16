import 'dart:convert';
import 'dart:async';
import 'package:bxbeam/presentation/bloc/playback_state.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'isar_service.dart';
import '../models/schedule_item.dart';
import '../../presentation/bloc/playback_bloc.dart';
import '../../presentation/bloc/playback_event.dart';

class SyncService {
  final String deviceId;
  final String apiUrl;
  final String wsUrl;
  
  final IsarService _isarService;
  final PlaybackBloc _playbackBloc;
  
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;

  SyncService({
    
    required this.deviceId,
    required this.apiUrl,
    required this.wsUrl,
    required IsarService isarService,
    required PlaybackBloc playbackBloc,
  })  : _isarService = isarService,
        _playbackBloc = playbackBloc;

  /// Initializes background WebSocket listeners and Heartbeat timers
  void initialize() {
    _connectWebSocket();
    _startHeartbeat();
  }

  void _connectWebSocket() {
    try {
      // Connect to the signaling server
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/$deviceId'));
      
      _channel?.stream.listen(
        (message) {
          final event = jsonDecode(message);
          
          // SIGNALING: Server tells the device its schedule changed.
          if (event['type'] == 'UPDATE_SCHEDULE') {
            _fetchAndSyncSchedules(); // Trigger REST GET request
          }
        },
        onDone: () {
          // Reconnect logic when socket closes
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
        onError: (error) {
          // Reconnect logic on socket errors
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      Future.delayed(const Duration(seconds: 5), _connectWebSocket);
    }
  }

  /// REST Fetch: Pulls the latest schedules and writes to Isar local DB
  Future<void> _fetchAndSyncSchedules() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/schedules/$deviceId'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final List<ScheduleItem> newSchedules = [];
        for (var item in data['schedules']) {
          int durationSecs = item['duration'] ?? 60;
          bool isPriority = item['isPriority'] ?? false;

          newSchedules.add(ScheduleItem()
            ..scrId = deviceId
            ..type = 'url'
            ..source = item['url'] ?? ''
            ..durMin = (durationSecs / 60).ceil()
            ..scheduleType = isPriority ? 'Scheduled' : 'Default'
            ..startTime = item['startTime'] != null ? DateTime.parse(item['startTime']) : null
            ..title = 'REST Sync Item'
            ..createdAt = DateTime.now()
            ..srtOrd = 0
          );
        }

        // 1. Save to Offline Cache (Isar)
        await _isarService.saveScheduleItems(newSchedules);

        // 2. Tell the Engine to reload schedules
        _playbackBloc.add(PlaybackSchedulesUpdated());
      }
    } catch (e) {
      // OFFLINE SUPPORT:
      // If network fails, do nothing. The engine continues looping cached URLs in Isar.
      print("Sync failed. Continuing with offline cache. Error: $e");
    }
  }

  /// 60-Second Industrial Heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        final state = _playbackBloc.state;
        final currentUrl = state is PlaybackPlaying ? state.url : 'idle';
        
        // Report device health and currently playing content
        await http.post(
          Uri.parse('$apiUrl/heartbeat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'currentUrl': currentUrl,
            'batteryStatus': 100, // Normally fetched via 'battery_plus' package
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );
      } catch (_) {
        // Silently fail if offline
      }
    });
  }

  void dispose() {
    _channel?.sink.close();
    _heartbeatTimer?.cancel();
  }
}

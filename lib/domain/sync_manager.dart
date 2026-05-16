import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/dto/device_dto.dart';
import '../data/models/schedule_item.dart';
import '../data/services/api_service.dart';
import '../data/services/isar_service.dart';
import '../presentation/bloc/playback_bloc.dart';
import '../presentation/bloc/playback_event.dart';
import 'package:mac_address/mac_address.dart';

class SyncManager {
  final ApiService _apiService;
  final IsarService _isarService;
  final PlaybackBloc _playbackBloc;
  
  Timer? _refreshTimer;
  String? _screenId;

  SyncManager({
    required ApiService apiService,
    required IsarService isarService,
    required PlaybackBloc playbackBloc,
  })  : _apiService = apiService,
        _isarService = isarService,
        _playbackBloc = playbackBloc;

  Future<bool> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    bool isRegistered = await _checkAndRegisterDevice(prefs);

    if (isRegistered) {
      // Start the continuous sync loop
      _runSyncLoop();
    }
    return isRegistered;
  }
  
  Future<void> setScreenIdAndStart(String screenId) async {
    final prefs = await SharedPreferences.getInstance();
    _screenId = screenId;
    await prefs.setString('screen_id', screenId);
    _runSyncLoop();
  }

  Future<bool> _checkAndRegisterDevice(SharedPreferences prefs) async {
    try {
      // 1. Get real MAC address
      String mac = 'UNKNOWN_MAC';
      try {
        mac = await GetMac.macAddress;
      } catch (e) {
        print('Failed to get real MAC address: $e');
      }

      // Fallback if MAC address is unknown or invalid
      if (mac == 'UNKNOWN_MAC' || mac.isEmpty || mac == '02:00:00:00:00:00') {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          mac = androidInfo.id; // Using Android ID as unique device identifier fallback
        }
      }

      // 2. Check if device is already registered using the unique ID
      final registeredDevices = await _apiService.getRegisteredDevice(mac);
      
      bool deviceFound = false;
      if (registeredDevices.isNotEmpty) {
        final device = registeredDevices.first;
        // Compare the get device by mac response
        if (device.macAddress.toLowerCase() == mac.toLowerCase()) {
          _screenId = device.scrId;
          deviceFound = true;
          print("Device already registered. Screen ID: $_screenId");
        }
      }

      if (deviceFound) {
        if (_screenId != null && _screenId!.isNotEmpty) {
          await prefs.setString('screen_id', _screenId!);
        }
        return true;
      } else {
        // Device not found! Return false so the UI can show the registration form.
        return false;
      }
    } catch (e) {
      print("Failed to check/register device: $e");
      // Fallback to locally saved screenId if offline
      _screenId = prefs.getString('screen_id');
      return _screenId != null && _screenId!.isNotEmpty;
    }
  }

  void _runSyncLoop() async {
    if (_screenId == null || _screenId!.isEmpty) {
      print("Cannot run sync loop: screenId is missing. Retrying in 30s.");
      _refreshTimer = Timer(const Duration(seconds: 30), _runSyncLoop);
      return;
    }

    try {
      // 1. Fetch and apply schedules IMMEDIATELY upon starting the loop
      await _fetchAndApplySchedules();

      // 2. Determine how long to wait before doing it again
      print("Fetching next refresh time for $_screenId...");
      int nextRefreshSeconds = await _apiService.getNextRefresh(_screenId!);
      
      // Ensure we don't spam the server if it returns 0 or a negative number
      if (nextRefreshSeconds <= 5) nextRefreshSeconds = 60; 

      print("Next schedule refresh in $nextRefreshSeconds seconds.");

      // 3. Wait for the duration, then restart the loop
      _refreshTimer = Timer(Duration(seconds: nextRefreshSeconds), _runSyncLoop);

    } catch (e) {
      print("Failed in sync loop: $e. Retrying in 60s.");
      _refreshTimer = Timer(const Duration(seconds: 60), _runSyncLoop);
    }
  }

  Future<void> _fetchAndApplySchedules() async {
    try {
      print("Fetching full schedule data...");
      final schedules = await _apiService.getSchedules(_screenId!);
      
      if (schedules.isNotEmpty) {
        List<ScheduleItem> newSchedules = [];
        
        // Map DTOs to ScheduleItem models
        for (var dto in schedules) {
          newSchedules.add(
            ScheduleItem()
              ..scrId = dto.scrId
              ..type = dto.type
              ..source = dto.source
              ..durMin = dto.durMin
              ..scheduleType = dto.scheduleType
              ..startTime = dto.startTime
              ..title = dto.title
              ..createdAt = dto.createdAt
              ..srtOrd = dto.srtOrd
          );
        }

        // Save to Local DB
        await _isarService.saveScheduleItems(newSchedules);
        
        // Dispatch to BLoC to reload the engine
        _playbackBloc.add(PlaybackSchedulesUpdated());
        
        print("Schedules updated successfully: \${schedules.length} items.");
      }
    } catch (e) {
      print("Error fetching schedules: $e");
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
  }
}

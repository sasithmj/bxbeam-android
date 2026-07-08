import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/dto/schedule_dto.dart';
import '../data/models/schedule_item.dart';
import '../data/services/api_service.dart';
import '../data/services/isar_service.dart';
import '../presentation/bloc/playback_bloc.dart';
import '../presentation/bloc/playback_event.dart';

class SyncManager {
  final ApiService _apiService;
  final IsarService _isarService;
  final PlaybackBloc _playbackBloc;

  IsarService get isarService => _isarService;

  Timer? _refreshTimer;
  String? _screenId;

  static Future<String> getDeviceMac() async {
    final prefs = await SharedPreferences.getInstance();
    String? mac = prefs.getString('device_mac_address');
    if (mac == null || mac.isEmpty || mac == 'UNKNOWN_DEVICE_ID') {
      // Generate a persistent unique random 64-bit identifier for this installation
      final random = Random.secure();
      final values = List<int>.generate(8, (i) => random.nextInt(256));
      final hex = values
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      mac = 'BX-$hex';
      await prefs.setString('device_mac_address', mac);
    }

    return mac;
  }

  SyncManager({
    required ApiService apiService,
    required IsarService isarService,
    required PlaybackBloc playbackBloc,
  }) : _apiService = apiService,
       _isarService = isarService,
       _playbackBloc = playbackBloc;

  Future<bool> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Clean up any invalid/corrupted screen IDs from SharedPreferences (e.g. SQL error messages)
    final existingId = prefs.getString('screen_id');
    if (existingId != null &&
        (existingId.contains('truncated') ||
            existingId.contains('Error') ||
            !existingId.startsWith('SR'))) {
      print(
        "Clearing invalid/corrupted screen ID from SharedPreferences: $existingId",
      );
      await prefs.remove('screen_id');
      _screenId = null;
    } else {
      _screenId = existingId;
    }

    bool isRegistered = await _checkAndRegisterDevice(prefs);

    if (isRegistered) {
      // Start the continuous sync loop
      _runSyncLoop();
    }
    return isRegistered;
  }

  Future<void> setScreenIdAndStart(String screenId) async {
    if (!screenId.startsWith('SR')) {
      throw ArgumentError('Invalid Screen ID: $screenId');
    }
    final prefs = await SharedPreferences.getInstance();
    _screenId = screenId;
    await prefs.setString('screen_id', screenId);
    _runSyncLoop();
  }

  Future<bool> _checkAndRegisterDevice(SharedPreferences prefs) async {
    try {
      // 1. Get device identifier
      final mac = await getDeviceMac();

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
      // Fallback to locally saved screenId if offline and valid
      final fallbackId = prefs.getString('screen_id');
      if (fallbackId != null &&
          fallbackId.startsWith('SR') &&
          !fallbackId.contains(' ')) {
        _screenId = fallbackId;
        return true;
      }
      return false;
    }
  }

  bool _areDateTimesDifferent(DateTime? a, DateTime? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    return !a.isAtSameMomentAs(b);
  }

  bool _hasPlaylistChanged(List<ScheduleItem> oldItems, List<ScheduleDto> newItems) {
    if (oldItems.length != newItems.length) {
      print("Playlist change detected: length differs (${oldItems.length} vs ${newItems.length})");
      return true;
    }
    for (int i = 0; i < oldItems.length; i++) {
      final oldItem = oldItems[i];
      final newItem = newItems[i];
      
      if (oldItem.scrId != newItem.scrId) {
        print("Playlist change detected at index $i: scrId differs (${oldItem.scrId} vs ${newItem.scrId})");
        return true;
      }
      if (oldItem.type != newItem.type) {
        print("Playlist change detected at index $i: type differs (${oldItem.type} vs ${newItem.type})");
        return true;
      }
      if (oldItem.source != newItem.source) {
        print("Playlist change detected at index $i: source differs (${oldItem.source} vs ${newItem.source})");
        return true;
      }
      if (oldItem.durMin != newItem.durMin) {
        print("Playlist change detected at index $i: durMin differs (${oldItem.durMin} vs ${newItem.durMin})");
        return true;
      }
      if (oldItem.scheduleType != newItem.scheduleType) {
        print("Playlist change detected at index $i: scheduleType differs (${oldItem.scheduleType} vs ${newItem.scheduleType})");
        return true;
      }
      if (oldItem.title != newItem.title) {
        print("Playlist change detected at index $i: title differs (${oldItem.title} vs ${newItem.title})");
        return true;
      }
      if (oldItem.srtOrd != newItem.srtOrd) {
        print("Playlist change detected at index $i: srtOrd differs (${oldItem.srtOrd} vs ${newItem.srtOrd})");
        return true;
      }
      if (_areDateTimesDifferent(oldItem.startTime, newItem.startTime)) {
        print("Playlist change detected at index $i: startTime differs (${oldItem.startTime} vs ${newItem.startTime})");
        return true;
      }
    }
    return false;
  }

  void _runSyncLoop() async {
    if (_screenId == null || _screenId!.isEmpty) {
      print("Cannot run sync loop: screenId is missing. Retrying in 10s.");
      _refreshTimer = Timer(const Duration(seconds: 10), _runSyncLoop);
      return;
    }

    try {
      // 1. Fetch and apply schedules IMMEDIATELY upon starting the loop
      await _fetchAndApplySchedules();

      // 2. Poll every 10 seconds as requested
      print("Next schedule sync check in 10 seconds.");
      _refreshTimer = Timer(
        const Duration(seconds: 10),
        _runSyncLoop,
      );
    } catch (e) {
      print("Failed in sync loop: $e. Retrying in 10s.");
      _refreshTimer = Timer(const Duration(seconds: 10), _runSyncLoop);
    }
  }

  Future<void> _fetchAndApplySchedules() async {
    try {
      print("Fetching full schedule data...");
      final schedules = await _apiService.getSchedules(_screenId!);

      // Fetch currently cached items from Isar
      final cachedSchedules = await _isarService.getAllSchedules();

      // Sort both arrays deterministically to ensure a stable index-by-index comparison
      cachedSchedules.sort((a, b) => '${a.scheduleType}_${a.srtOrd}_${a.source}_${a.startTime?.millisecondsSinceEpoch}'.compareTo('${b.scheduleType}_${b.srtOrd}_${b.source}_${b.startTime?.millisecondsSinceEpoch}'));
      schedules.sort((a, b) => '${a.scheduleType}_${a.srtOrd}_${a.source}_${a.startTime?.millisecondsSinceEpoch}'.compareTo('${b.scheduleType}_${b.srtOrd}_${b.source}_${b.startTime?.millisecondsSinceEpoch}'));

      // Only perform database updates and trigger playback bloc reload if there is a change
      if (cachedSchedules.isEmpty || _hasPlaylistChanged(cachedSchedules, schedules)) {
        print("Playlist change detected! Updating local database...");
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
              ..srtOrd = dto.srtOrd,
          );
        }

        // Save to Local DB
        await _isarService.saveScheduleItems(newSchedules);

        // Dispatch to BLoC to reload the engine
        _playbackBloc.add(PlaybackSchedulesUpdated());
        print("Schedules updated successfully: ${schedules.length} items.");
      } else {
        print("No playlist changes detected. Keeping current playback active.");
      }
    } catch (e) {
      print("Error fetching schedules: $e");
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
  }
}

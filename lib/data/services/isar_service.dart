import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/schedule_item.dart';

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = openDB();
  }

  Future<Isar> openDB() async {
    // Check if an instance is already open to avoid conflicts
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      return await Isar.open(
        [ScheduleItemSchema],
        directory: dir.path,
        inspector: true, // Helpful for debugging
      );
    }
    return Future.value(Isar.getInstance());
  }

  /// Clears the current schedules and saves the new ones (used during sync).
  Future<void> saveScheduleItems(List<ScheduleItem> items) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.scheduleItems.clear();
      await isar.scheduleItems.putAll(items);
    });
  }

  /// Clears all schedules stored in Isar
  Future<void> clearAllSchedules() async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.scheduleItems.clear();
    });
  }

  /// Fetches all items in the database
  Future<List<ScheduleItem>> getAllSchedules() async {
    final isar = await db;
    return await isar.scheduleItems.where().findAll();
  }

  /// Fetches items for the Default Loop
  Future<List<ScheduleItem>> getDefaultLoop() async {
    final isar = await db;
    return await isar.scheduleItems.filter().isPriorityEqualTo(false).findAll();
  }

  /// Fetches items for the Priority Queue
  Future<List<ScheduleItem>> getPriorityQueue() async {
    final isar = await db;
    return await isar.scheduleItems.filter().isPriorityEqualTo(true).findAll();
  }
}

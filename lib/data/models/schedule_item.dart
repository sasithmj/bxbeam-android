import 'package:isar/isar.dart';

part 'schedule_item.g.dart';

@collection
class ScheduleItem {
  Id id = Isar.autoIncrement;

  late String scrId;
  late String type;
  late String source;
  late int durMin;
  late String scheduleType;
  DateTime? startTime;
  late String title;
  late DateTime createdAt;
  late int srtOrd;

  // Backward compatibility properties for existing app logic
  String get url => source;
  int get durationSeconds => durMin;
  bool get isPriority => scheduleType.trim().toLowerCase() == 'scheduled';
}

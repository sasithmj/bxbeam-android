class ScheduleDto {
  final String scrId;
  final String type;
  final String source;
  final int durMin;
  final String scheduleType;
  final DateTime? startTime;
  final String title;
  final DateTime createdAt;
  final int srtOrd;

  ScheduleDto({
    required this.scrId,
    required this.type,
    required this.source,
    required this.durMin,
    required this.scheduleType,
    this.startTime,
    required this.title,
    required this.createdAt,
    required this.srtOrd,
  });

  factory ScheduleDto.fromJson(Map<String, dynamic> json) {
    return ScheduleDto(
      scrId: json['ScrID'] as String? ?? '',
      type: json['Type'] as String? ?? '',
      source: json['Source'] as String? ?? '',
      durMin: json['DurMin'] as int? ?? 0,
      scheduleType: json['ScheduleType'] as String? ?? '',
      startTime: json['StartTime'] != null ? DateTime.tryParse(json['StartTime'] as String) : null,
      title: json['Title'] as String? ?? '',
      createdAt: json['CreatedAt'] != null ? DateTime.parse(json['CreatedAt'] as String) : DateTime.now(),
      srtOrd: json['srtOrd'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ScrID': scrId,
      'Type': type,
      'Source': source,
      'DurMin': durMin,
      'ScheduleType': scheduleType,
      'StartTime': startTime?.toIso8601String(),
      'Title': title,
      'CreatedAt': createdAt.toIso8601String(),
      'srtOrd': srtOrd,
    };
  }
}

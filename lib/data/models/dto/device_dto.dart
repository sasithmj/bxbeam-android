class DeviceDto {
  final String scrId;
  final String scrName;
  final String scrLoc;
  final String ipAddress;
  final String macAddress;
  final DateTime createdDate;
  final String? createdBy;
  final String scrStatus;
  final String onStatus;
  final String plantCode;

  DeviceDto({
    required this.scrId,
    required this.scrName,
    required this.scrLoc,
    required this.ipAddress,
    required this.macAddress,
    required this.createdDate,
    this.createdBy,
    required this.scrStatus,
    required this.onStatus,
    required this.plantCode,
  });

  factory DeviceDto.fromJson(Map<String, dynamic> json) {
    return DeviceDto(
      scrId: json['ScrID'] as String? ?? '',
      scrName: json['ScrName'] as String? ?? '',
      scrLoc: json['ScrLoc'] as String? ?? '',
      ipAddress: json['IPAddress'] as String? ?? '',
      macAddress: json['MACAddress'] as String? ?? '',
      createdDate: json['CreatedDate'] != null ? DateTime.parse(json['CreatedDate'] as String) : DateTime.now(),
      createdBy: json['CreatedBy'] as String?,
      scrStatus: json['ScrStatus'] as String? ?? '',
      onStatus: json['OnStatus'] as String? ?? '',
      plantCode: json['PlantCode'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ScrID': scrId,
      'ScrName': scrName,
      'ScrLoc': scrLoc,
      'IPAddress': ipAddress,
      'MACAddress': macAddress,
      'CreatedDate': createdDate.toIso8601String(),
      'CreatedBy': createdBy,
      'ScrStatus': scrStatus,
      'OnStatus': onStatus,
      'PlantCode': plantCode,
    };
  }
}

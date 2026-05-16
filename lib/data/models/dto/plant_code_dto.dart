class PlantCodeDto {
  final String plantCode;
  final String plantName;

  PlantCodeDto({
    required this.plantCode,
    required this.plantName,
  });

  factory PlantCodeDto.fromJson(Map<String, dynamic> json) {
    return PlantCodeDto(
      plantCode: json['PlantCode'] as String? ?? '',
      plantName: json['PlantName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'PlantCode': plantCode,
      'PlantName': plantName,
    };
  }
}

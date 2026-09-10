class BodyStats {
  final double weight;
  final double height;
  final double bmi;
  final double bmr;
  final double tdee;
  final double targetCal;
  final double activityLevel;
  final String? createdAt;

  BodyStats({
    required this.weight,
    required this.height,
    required this.bmi,
    required this.bmr,
    required this.tdee,
    this.targetCal = 0,
    this.activityLevel = 0,
    this.createdAt,
  });

  factory BodyStats.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
    return BodyStats(
      weight: d(json['weight']),
      height: d(json['height']),
      bmi: d(json['bmi']),
      bmr: d(json['bmr']),
      tdee: d(json['tdee']),
      targetCal: d(json['target_cal']),
      activityLevel: d(json['activity_level']),
      createdAt: json['created_at']?.toString(),
    );
  }
}

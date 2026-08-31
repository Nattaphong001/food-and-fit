import '../services/api_client.dart';

class WorkoutPlan {
  final int planId;
  final String planName;
  final int daysPerWeek;
  final int difficulty;
  final String description;
  final String? imageUrl;

  WorkoutPlan({
    required this.planId,
    required this.planName,
    required this.daysPerWeek,
    this.difficulty = 1,
    this.description = '',
    this.imageUrl,
  });

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        planId: json['wpt_id'] ?? json['plan_id'] ?? json['id'] ?? 0,
        planName: json['wpt_name'] ?? json['plan_name'] ?? '',
        daysPerWeek: json['wpt_days_per_week'] ?? json['plan_days_per_week'] ?? 3,
        difficulty: json['wpt_difficulty'] ?? json['difficulty'] ?? 1,
        description: json['wpt_description'] ?? json['description'] ?? '',
        imageUrl: ApiClient.prefixPath(json['wpt_image'] ?? json['image_url']),
      );

  Map<String, dynamic> toJson() => {
        'wpt_name': planName,
        'wpt_days_per_week': daysPerWeek,
        'wpt_difficulty': difficulty,
        'wpt_description': description,
      };
}

class PlanDetail {
  final int detailId;
  final int planId;
  final int dayNumber;
  final String dayName;
  final int? exerciseId;
  final int sets;
  final String reps; // VARCHAR e.g. "8-10", "12-15"
  final int restSeconds;
  final int order;
  final String? exerciseName;
  final String? imageUrl;

  PlanDetail({
    required this.detailId,
    required this.planId,
    required this.dayNumber,
    this.dayName = '',
    this.exerciseId,
    this.sets = 3,
    this.reps = '10',
    this.restSeconds = 90,
    this.order = 1,
    this.exerciseName,
    this.imageUrl,
  });

  factory PlanDetail.fromJson(Map<String, dynamic> json) => PlanDetail(
        detailId: json['ptd_id'] ?? json['det_id'] ?? json['id'] ?? 0,
        planId: json['wpt_id'] ?? json['plan_id'] ?? 0,
        dayNumber: json['ptd_day_number'] ?? json['det_day_number'] ?? json['day_number'] ?? 0,
        dayName: json['ptd_day_name'] ?? json['day_name'] ?? '',
        exerciseId: json['wet_id'] as int?,
        sets: json['ptd_sets'] ?? json['det_suggested_sets'] ?? 3,
        reps: (json['ptd_reps'] ?? json['det_suggested_reps'] ?? '10').toString(),
        restSeconds: json['ptd_rest_seconds'] ?? 90,
        order: json['ptd_order'] ?? 1,
        exerciseName: (json['weight_exercise'] as Map?)?['wet_name']
            ?? json['wet_name']
            ?? json['exercise_name'],
        imageUrl: ApiClient.prefixPath(
            (json['weight_exercise'] as Map?)?['wet_image']
            ?? json['wet_image']
            ?? json['image_url']),
      );

  Map<String, dynamic> toJson() => {
        'wpt_id': planId,
        'ptd_day_number': dayNumber,
        'ptd_day_name': dayName,
        'wet_id': exerciseId,
        'ptd_sets': sets,
        'ptd_reps': reps,
        'ptd_rest_seconds': restSeconds,
        'ptd_order': order,
      };
}

class UserWorkoutSchedule {
  final int scheduleId;
  final String scheduleDate;
  final int dayNumber;
  final int planId;
  final int exerciseId;
  final int sets;
  final String reps;
  final String? exerciseName;
  final String? imageUrl;

  UserWorkoutSchedule({
    required this.scheduleId,
    required this.scheduleDate,
    required this.dayNumber,
    required this.planId,
    required this.exerciseId,
    this.sets = 3,
    this.reps = '10',
    this.exerciseName,
    this.imageUrl,
  });

  factory UserWorkoutSchedule.fromJson(Map<String, dynamic> json) => UserWorkoutSchedule(
        scheduleId: json['wsch_id'] ?? json['schedule_id'] ?? json['id'] ?? 0,
        scheduleDate: json['wsch_date'] ?? json['schedule_date'] ?? '',
        dayNumber: json['wsch_day_number'] ?? json['day_number'] ?? 0,
        planId: json['plan_id'] ?? 0,
        exerciseId: json['wet_id'] ?? json['exercise_id'] ?? 0,
        sets: json['wsch_sets'] ?? json['sets'] ?? 3,
        reps: (json['wsch_reps'] ?? json['reps'] ?? '10').toString(),
        exerciseName: (json['weight_exercise'] as Map?)?['wet_name']?.toString()
            ?? json['wet_name']?.toString(),
        imageUrl: ApiClient.prefixPath(
            (json['weight_exercise'] as Map?)?['wet_image']?.toString()
            ?? json['wet_image']?.toString()),
      );

  Map<String, dynamic> toJson() => {
        'wsch_date': scheduleDate,
        'wsch_day_number': dayNumber,
        'plan_id': planId,
        'wet_id': exerciseId,
        'wsch_sets': sets,
        'wsch_reps': reps,
      };
}

class WorkoutResult {
  final int resultId;
  final int scheduleId;
  final int exerciseId;
  final String date;
  final int setNo;
  final int reps;
  final double weight;
  final double calories;
  final int? intensityLevel;
  final String? note;
  final String? exerciseName;
  final String? imageUrl;

  WorkoutResult({
    required this.resultId,
    required this.scheduleId,
    required this.exerciseId,
    this.date = '',
    required this.setNo,
    required this.reps,
    required this.weight,
    this.calories = 0,
    this.intensityLevel,
    this.note,
    this.exerciseName,
    this.imageUrl,
  });

  factory WorkoutResult.fromJson(Map<String, dynamic> json) => WorkoutResult(
        resultId: json['wtrs_id'] ?? json['result_id'] ?? json['id'] ?? 0,
        scheduleId: json['wsch_id'] ?? json['schedule_id'] ?? 0,
        exerciseId: json['wet_id'] ?? json['exercise_id'] ?? 0,
        date: json['wtrs_date']?.toString() ?? json['date']?.toString() ?? '',
        setNo: json['wtrs_set_no'] ?? json['set_no'] ?? 1,
        reps: json['wtrs_reps'] ?? json['reps'] ?? 0,
        weight: (json['wtrs_weight'] ?? json['weight'] ?? 0).toDouble(),
        calories: (json['wtrs_calories'] ?? json['calories'] ?? 0).toDouble(),
        intensityLevel: json['wtrs_intensity_level'] as int?
            ?? json['intensity_level'] as int?,
        note: json['wtrs_note']?.toString() ?? json['note']?.toString(),
        exerciseName: (json['weight_exercise'] as Map?)?['wet_name']?.toString()
            ?? json['wet_name']?.toString() ?? json['exercise_name']?.toString(),
        imageUrl: ApiClient.prefixPath(
            (json['weight_exercise'] as Map?)?['wet_image']?.toString()
            ?? json['wet_image']?.toString() ?? json['image_url']?.toString()),
      );

  Map<String, dynamic> toJson() => {
        'wsch_id': scheduleId,
        'wtrs_set_no': setNo,
        'wtrs_reps': reps,
        'wtrs_weight': weight,
        'wtrs_intensity_level': intensityLevel,
        'wtrs_note': note,
      };
}

class CardioResult {
  final int resultId;
  final int cardioTypeId;
  final double duration;
  final double distance;
  final double caloriesBurned;
  final String date;
  final String? cardioTypeName;
  final String? imageUrl;

  CardioResult({
    required this.resultId,
    required this.cardioTypeId,
    required this.duration,
    required this.distance,
    required this.caloriesBurned,
    required this.date,
    this.cardioTypeName,
    this.imageUrl,
  });

  factory CardioResult.fromJson(Map<String, dynamic> json) => CardioResult(
        resultId: json['cdors_id'] ?? json['result_id'] ?? json['id'] ?? 0,
        cardioTypeId: json['cdo_id'] ?? json['cardio_type_id'] ?? 0,
        duration: (json['cdors_duration'] ?? json['duration'] ?? 0).toDouble(),
        distance: (json['cdors_distance'] ?? json['distance'] ?? 0).toDouble(),
        caloriesBurned:
            (json['cdors_calories'] ?? json['calories_burned'] ?? 0).toDouble(),
        date: json['cdors_date'] ?? json['date'] ?? '',
        cardioTypeName: (json['cardio_type'] as Map?)?['cdo_name']
            ?? json['cdo_name'] ?? json['type_name'],
        imageUrl: ApiClient.prefixPath(
            (json['cardio_type'] as Map?)?['cdo_image']
            ?? json['cdo_image'] ?? json['image_url']),
      );

  Map<String, dynamic> toJson() => {
        'cdo_id': cardioTypeId,
        'cdors_duration': duration.toInt(),
        'cdors_distance': distance,
        'date': date,
      };
}

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
  final int dayNumber;
  final int planId;
  final int exerciseId;
  final int sets;
  final String reps;
  final String? exerciseName;
  final String? imageUrl;

  UserWorkoutSchedule({
    required this.scheduleId,
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
  final int? durationSeconds; // wtrs_duration — เวลารวมทั้งเซสชัน (ทุกเซตของเซสชันเดียวกันเก็บค่าเท่ากัน)
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
    this.durationSeconds,
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
        durationSeconds: (json['wtrs_duration'] ?? json['duration_seconds']) as int?,
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
        // cdors_duration จาก API เป็นวินาที (เปลี่ยนจากนาที 2026-09-14) แปลงเป็นนาทีตรงนี้จุดเดียว
        // ให้ field `duration` ของโมเดลนี้ยังคงความหมาย "นาที" เหมือนเดิม — จุดแสดงผลอื่นทั้งหมด
        // (workout_view.dart, dashboard_view.dart, cardio_activity_detail_view.dart) ไม่ต้องแก้
        duration: json['cdors_duration'] != null
            ? (json['cdors_duration'] as num).toDouble() / 60.0
            : (json['duration'] as num? ?? 0).toDouble(),
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
        // duration (นาที) แปลงกลับเป็นวินาทีตอนส่ง API (cdors_duration เป็นวินาที 2026-09-14)
        'cdors_duration': (duration * 60).round(),
        'cdors_distance': distance,
        'date': date,
      };
}

/// เวลาฝึกรวม (วินาที) ของเซตที่ให้มา — ทุกเซตของเซสชันเดียวกันเก็บ `wtrs_duration` ค่าเดียวกัน
/// จึงนับแต่ละเซสชันครั้งเดียว เดิมเช็ค "duration เท่ากับแถวก่อนหน้าไหม" เพื่อสรุปว่าเป็นเซสชัน
/// เดียวกัน แต่ 2 เซสชันคนละรอบวันเดียวกัน (ท่าเดิม รอบเช้า/เย็น) มี duration บังเอิญเท่ากันได้
/// (โดยเฉพาะเซตสั้นๆ ที่จับเวลาใกล้เคียงกัน) ทำให้รวมเวลาขาดไปทั้งเซสชัน — ไม่มี session id จริง
/// ส่งมาจาก backend ให้ใช้ตรงๆ (wtrs_set_no เดินต่อเนื่องข้ามรอบในวันเดียวกัน ไม่รีเซ็ต)
/// เปลี่ยนมาเช็ค resultId (wtrs_id, auto-increment) ติดกันแทน — เซตของเซสชันเดียวกันถูกบันทึกในคำขอ
/// เดียวกัน (1 transaction) จึงได้ id ต่อเนื่องกันเป๊ะเสมอ ส่วนเซสชันที่แยกกันจริงจะมี activity อื่น
/// ของระบบ (ผู้ใช้คนอื่น/ท่าอื่น) แทรกกลาง id เกือบทุกครั้ง ทนทานกว่าการเทียบค่า duration ที่บังเอิญ
/// ตรงกันได้ คืน 0 ถ้าไม่มีข้อมูลเวลา (ข้อมูลเก่า) — ผู้เรียกควรซ่อนช่องเวลาเมื่อได้ 0
int sessionDurationSeconds(Iterable<WorkoutResult> sets) {
  final ordered = sets.toList()..sort((a, b) => a.resultId.compareTo(b.resultId));
  var total = 0;
  int? prevId;
  for (final r in ordered) {
    final d = r.durationSeconds;
    if (d == null || d <= 0) {
      prevId = null;
      continue;
    }
    if (prevId == null || r.resultId != prevId + 1) total += d;
    prevId = r.resultId;
  }
  return total;
}

/// แสดงเวลาจริงไม่ปัดขึ้น ใช้ร่วมกันทั้งเวทและคาร์ดิโอ:
/// < 1 นาที `45 วินาที` · < 1 ชม. `2 นาที 50 วินาที` (วินาทีเป็น 0 → `3 นาที`) · ≥ 1 ชม. `1 ชม. 5 นาที`
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return '$s วินาที';
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return m > 0 ? '$h ชม. $m นาที' : '$h ชม.';
  return sec > 0 ? '$m นาที $sec วินาที' : '$m นาที';
}

/// สำหรับ `CardioResult.duration` ที่โมเดลแปลงจากวินาทีเป็นนาที (double) แล้ว
String formatDurationMinutes(double minutes) => formatDuration((minutes * 60).round());

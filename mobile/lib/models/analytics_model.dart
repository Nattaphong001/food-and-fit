class DailyAnalytics {
  final double totalCaloriesIn;
  final double totalCaloriesOut;
  final double bmi;
  final double bmr;
  final double tdee;
  final double targetTdee;
  final double weight;
  final int goalType; // 1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก(เพิ่มกล้ามเนื้อ), 3=รักษาน้ำหนัก
  final double baseline;
  final double exerciseBurn;
  final double balance;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final double proteinPercent;
  final double carbsPercent;
  final double fatPercent;
  final bool isBmrEstimated;

  DailyAnalytics({
    required this.totalCaloriesIn,
    required this.totalCaloriesOut,
    required this.bmi,
    required this.bmr,
    required this.tdee,
    required this.targetTdee,
    required this.weight,
    required this.goalType,
    required this.baseline,
    required this.exerciseBurn,
    required this.balance,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.proteinPercent,
    required this.carbsPercent,
    required this.fatPercent,
    required this.isBmrEstimated,
  });

  factory DailyAnalytics.fromJson(Map<String, dynamic> json) {
    final macros = json['macros'] as Map<String, dynamic>? ?? {};
    final protein = (macros['total_protein'] ?? 0).toDouble();
    final carbs = (macros['total_carbs'] ?? 0).toDouble();
    final fat = (macros['total_fat'] ?? 0).toDouble();
    final totalMacros = protein + carbs + fat;
    return DailyAnalytics(
      totalCaloriesIn: (json['total_calories_in'] ?? 0).toDouble(),
      totalCaloriesOut: (json['total_calories_out'] ?? 0).toDouble(),
      bmi: (json['bmi'] ?? 0).toDouble(),
      bmr: (json['bmr'] ?? 0).toDouble(),
      tdee: (json['tdee'] ?? 0).toDouble(),
      targetTdee: (json['target_tdee'] ?? 0).toDouble(),
      weight: (json['weight'] ?? 0).toDouble(),
      goalType: (json['goal_type'] ?? 1) as int,
      baseline: (json['baseline'] ?? 0).toDouble(),
      exerciseBurn: (json['exercise_burn'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      totalProtein: protein,
      totalCarbs: carbs,
      totalFat: fat,
      proteinPercent: totalMacros > 0 ? protein / totalMacros * 100 : 0,
      carbsPercent: totalMacros > 0 ? carbs / totalMacros * 100 : 0,
      fatPercent: totalMacros > 0 ? fat / totalMacros * 100 : 0,
      isBmrEstimated: json['is_bmr_estimated'] as bool? ?? false,
    );
  }
}

// ── Meal Breakdown ─────────────────────────────────────────────────────────
class MealBreakdown {
  final int mealType; // 1=เช้า 2=กลางวัน 3=เย็น 4=ว่าง
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int count;

  const MealBreakdown({
    required this.mealType,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.count,
  });

  String get mealName {
    switch (mealType) {
      case 1: return 'มื้อเช้า';
      case 2: return 'มื้อกลางวัน';
      case 3: return 'มื้อเย็น';
      case 4: return 'ของว่าง';
      default: return 'อื่นๆ';
    }
  }

  String get mealEmoji {
    switch (mealType) {
      case 1: return '🌅';
      case 2: return '☀️';
      case 3: return '🌙';
      case 4: return '🍎';
      default: return '🍽️';
    }
  }

  factory MealBreakdown.fromJson(Map<String, dynamic> json) => MealBreakdown(
        mealType: (json['meal_type'] ?? 0) as int,
        calories: (json['calories'] ?? 0).toDouble(),
        protein: (json['protein'] ?? 0).toDouble(),
        carbs: (json['carbs'] ?? 0).toDouble(),
        fat: (json['fat'] ?? 0).toDouble(),
        count: (json['count'] ?? 0) as int,
      );
}

// ── Weekly Data ─────────────────────────────────────────────────────────────
class WeeklyDataPoint {
  final String date;
  final double calories;
  final double caloriesOut;
  final double cardioOut;
  final double weightOut;
  final double protein;
  final double carbs;
  final double fat;
  final double targetTdee; // เป้าหมายที่มีผลใช้งานจริง ณ วันนั้น (ไม่ใช่เป้าหมายปัจจุบัน) — ใช้วาดเส้น target แบบสลับตรงวันเปลี่ยนเป้าหมาย

  WeeklyDataPoint({
    required this.date,
    required this.calories,
    required this.caloriesOut,
    this.cardioOut = 0,
    this.weightOut = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.targetTdee = 0,
  });

  factory WeeklyDataPoint.fromJson(Map<String, dynamic> json) => WeeklyDataPoint(
        date: json['date'] ?? '',
        calories: (json['calories_in'] ?? json['calories'] ?? 0).toDouble(),
        caloriesOut: (json['calories_out'] ?? 0).toDouble(),
        cardioOut: (json['cardio_out'] ?? 0).toDouble(),
        weightOut: (json['weight_out'] ?? 0).toDouble(),
        protein: (json['protein'] ?? 0).toDouble(),
        carbs: (json['carbs'] ?? 0).toDouble(),
        fat: (json['fat'] ?? 0).toDouble(),
        targetTdee: (json['target_tdee'] ?? 0).toDouble(),
      );
}

class WeeklyAnalytics {
  final List<WeeklyDataPoint> weekData;
  final double weeklyAvgCalories;
  final double weeklyAvgCaloriesOut;

  WeeklyAnalytics({
    required this.weekData,
    required this.weeklyAvgCalories,
    required this.weeklyAvgCaloriesOut,
  });

  factory WeeklyAnalytics.fromJson(Map<String, dynamic> json) {
    final rawList = (json['data'] as List<dynamic>? ?? []);
    final weekData = rawList
        .map((e) => WeeklyDataPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final avgIn = weekData.isEmpty
        ? 0.0
        : weekData.fold(0.0, (sum, e) => sum + e.calories) / weekData.length;
    final avgOut = weekData.isEmpty
        ? 0.0
        : weekData.fold(0.0, (sum, e) => sum + e.caloriesOut) / weekData.length;
    return WeeklyAnalytics(
      weekData: weekData,
      weeklyAvgCalories: avgIn,
      weeklyAvgCaloriesOut: avgOut,
    );
  }
}

// ── Monthly Data ────────────────────────────────────────────────────────────
class MonthlyDataPoint {
  final String date;
  final double calories;
  final double caloriesOut;
  final double cardioOut;
  final double weightOut;
  final double protein;
  final double carbs;
  final double fat;
  final double targetTdee; // เป้าหมายที่มีผลใช้งานจริง ณ วันนั้น (ไม่ใช่เป้าหมายปัจจุบัน) — ใช้วาดเส้น target แบบสลับตรงวันเปลี่ยนเป้าหมาย

  MonthlyDataPoint({
    required this.date,
    required this.calories,
    required this.caloriesOut,
    this.cardioOut = 0,
    this.weightOut = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.targetTdee = 0,
  });

  factory MonthlyDataPoint.fromJson(Map<String, dynamic> json) => MonthlyDataPoint(
        date: json['date'] ?? '',
        calories: (json['calories_in'] ?? json['calories'] ?? 0).toDouble(),
        caloriesOut: (json['calories_out'] ?? 0).toDouble(),
        cardioOut: (json['cardio_out'] ?? 0).toDouble(),
        weightOut: (json['weight_out'] ?? 0).toDouble(),
        protein: (json['protein'] ?? 0).toDouble(),
        carbs: (json['carbs'] ?? 0).toDouble(),
        fat: (json['fat'] ?? 0).toDouble(),
        targetTdee: (json['target_tdee'] ?? 0).toDouble(),
      );
}

class MonthlyAnalytics {
  final List<MonthlyDataPoint> monthData;
  // ยังไม่มีจุดไหนในแอปเรียกใช้ 2 field นี้เลย (ตรวจแล้ว 2026-08-17 — คำสั่งที่ 19.4) คงไว้
  // เพราะ backend ส่งมาแล้วและอาจต้องใช้ในรายงานรายเดือนภายหลัง ห้ามลบทิ้ง
  // นิยามตัวหาร: เฉลี่ยด้วยจำนวนวันที่มีบันทึกจริง (monthData.length ตอน parse ก่อน densify)
  // ไม่ใช่จำนวนวันปฏิทินของเดือน — เหตุผลเดียวกับ weeklyAvgCalories (ดู _densify ใน
  // new_dashboard_view.dart, คำสั่งที่ 19)
  final double monthlyAvgCalories;
  final double monthlyAvgCaloriesOut;

  MonthlyAnalytics({
    required this.monthData,
    required this.monthlyAvgCalories,
    required this.monthlyAvgCaloriesOut,
  });

  factory MonthlyAnalytics.fromJson(Map<String, dynamic> json) {
    final rawList = (json['data'] as List<dynamic>? ?? []);
    final monthData = rawList
        .map((e) => MonthlyDataPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final avgIn = monthData.isEmpty
        ? 0.0
        : monthData.fold(0.0, (sum, e) => sum + e.calories) / monthData.length;
    final avgOut = monthData.isEmpty
        ? 0.0
        : monthData.fold(0.0, (sum, e) => sum + e.caloriesOut) / monthData.length;
    return MonthlyAnalytics(
      monthData: monthData,
      monthlyAvgCalories: avgIn,
      monthlyAvgCaloriesOut: avgOut,
    );
  }
}

// ── Monthly Comparison ──────────────────────────────────────────────────────
class MonthStat {
  final double avgCal;
  final int workoutDays;
  final double avgCardio;
  final double avgWeight;
  // จำนวนวันที่มีบันทึกอาหารจริงในเดือนนั้น — avgCal หารด้วยตัวนี้ ไม่ใช่จำนวนวันปฏิทิน
  // ("ไม่มีข้อมูล" ไม่เท่ากับ "ศูนย์" — คำสั่งที่ 19)
  final int recordedDays;

  const MonthStat({
    required this.avgCal,
    required this.workoutDays,
    required this.avgCardio,
    required this.avgWeight,
    this.recordedDays = 0,
  });

  factory MonthStat.fromJson(Map<String, dynamic> json) => MonthStat(
        avgCal: (json['avg_cal'] ?? 0).toDouble(),
        workoutDays: (json['workout_days'] ?? 0) as int,
        avgCardio: (json['avg_cardio'] ?? 0).toDouble(),
        avgWeight: (json['avg_weight'] ?? 0).toDouble(),
        recordedDays: (json['recorded_days'] ?? 0) as int,
      );
}

class MonthlyComparison {
  final MonthStat thisMonth;
  final MonthStat lastMonth;
  final double calChangePct;
  final int workoutChange;

  const MonthlyComparison({
    required this.thisMonth,
    required this.lastMonth,
    required this.calChangePct,
    required this.workoutChange,
  });

  factory MonthlyComparison.fromJson(Map<String, dynamic> json) => MonthlyComparison(
        thisMonth: MonthStat.fromJson(json['this_month'] as Map<String, dynamic>? ?? {}),
        lastMonth: MonthStat.fromJson(json['last_month'] as Map<String, dynamic>? ?? {}),
        calChangePct: (json['cal_change_pct'] ?? 0).toDouble(),
        workoutChange: (json['workout_change'] ?? 0) as int,
      );
}

// ── 1RM History ─────────────────────────────────────────────────────────────
class OneRMPoint {
  final String date;
  final double best1rm;
  final double bestWeight;
  final int bestReps;

  const OneRMPoint({
    required this.date,
    required this.best1rm,
    required this.bestWeight,
    required this.bestReps,
  });

  factory OneRMPoint.fromJson(Map<String, dynamic> json) => OneRMPoint(
        date: json['date'] ?? '',
        best1rm: (json['best_1rm'] ?? 0).toDouble(),
        bestWeight: (json['best_weight'] ?? 0).toDouble(),
        bestReps: (json['best_reps'] ?? 0) as int,
      );
}

// ── Muscle Group Coverage ───────────────────────────────────────────────────
class MuscleGroupCoverage {
  final int mugId;
  final String mugName;
  final int mugZone; // 1=บน 2=ล่าง 3=แกนกลาง
  final int trainedDays;
  final String lastTrained;

  const MuscleGroupCoverage({
    required this.mugId,
    required this.mugName,
    required this.mugZone,
    required this.trainedDays,
    required this.lastTrained,
  });

  String get zoneName {
    switch (mugZone) {
      case 1: return 'ส่วนบน';
      case 2: return 'ส่วนล่าง';
      case 3: return 'แกนกลาง';
      default: return '';
    }
  }

  factory MuscleGroupCoverage.fromJson(Map<String, dynamic> json) => MuscleGroupCoverage(
        mugId: (json['mug_id'] ?? 0) as int,
        mugName: json['mug_name'] ?? '',
        mugZone: (json['mug_zone'] ?? 0) as int,
        trainedDays: (json['trained_days'] ?? 0) as int,
        lastTrained: json['last_trained'] ?? '',
      );
}

// ── Progress Report ─────────────────────────────────────────────────────────
class ProgressReport {
  final double weightChange;
  final double calorieAvg;
  final int workoutCount;
  final double progressPercent;
  final List<BodyPoint> bodyHistory;

  ProgressReport({
    required this.weightChange,
    required this.calorieAvg,
    required this.workoutCount,
    required this.progressPercent,
    this.bodyHistory = const [],
  });

  factory ProgressReport.fromJson(Map<String, dynamic> json) => ProgressReport(
        weightChange: (json['weight_change'] ?? 0).toDouble(),
        calorieAvg: (json['calorie_avg'] ?? 0).toDouble(),
        workoutCount: (json['workout_count'] ?? 0) as int,
        progressPercent: (json['progress_percent'] ?? 0).toDouble(),
        bodyHistory: (json['body_history'] as List<dynamic>? ?? [])
            .map((e) => BodyPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class BodyPoint {
  final String date;
  final double weight;
  final double bmi;
  final double activityLevel;
  final int target; // 1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก — ใช้เทียบจุดก่อนหน้าเพื่อ mark วันที่เปลี่ยนกิจกรรม/เป้าหมายบนกราฟ

  const BodyPoint({
    required this.date,
    required this.weight,
    required this.bmi,
    this.activityLevel = 0,
    this.target = 0,
  });

  factory BodyPoint.fromJson(Map<String, dynamic> json) => BodyPoint(
        date: json['date'] ?? '',
        weight: (json['weight'] ?? 0).toDouble(),
        bmi: (json['bmi'] ?? 0).toDouble(),
        activityLevel: (json['activity_level'] ?? 0).toDouble(),
        target: (json['target'] ?? 0) as int,
      );
}

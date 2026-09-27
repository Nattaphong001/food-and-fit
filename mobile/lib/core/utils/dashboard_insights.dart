// สูตร/คำนวณสำหรับ dashboard_view.dart — แยกออกจาก widget state เพื่อให้ทดสอบ/อ่านง่ายขึ้น
// ไม่ใช่ formula-guard (BMI/BMR/TDEE ฯลฯ อยู่ที่ health_calculations.dart) ไฟล์นี้เก็บเฉพาะ logic
// เฉพาะทางของหน้า dashboard เอง (streak, insight, densify ฯลฯ)

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../models/analytics_model.dart';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// เติมวันที่ที่ไม่มีข้อมูลให้เป็นจุดค่า 0 เพื่อให้ชุดข้อมูลมีจำนวนวันครบตามช่วงเวลา
/// จำเป็นเพราะ date_list ฝั่ง SQL (dailySumRangeSQL/dailySumBetweenSQL) เป็น UNION ของวันที่
/// ที่มีบันทึกจริงอย่างน้อย 1 รายการ (nutrition/cardio/weight) เท่านั้น — วันที่ไม่มีกิจกรรม
/// เลยจะหายไปทั้งแถว ไม่ได้คืนมาเป็น 0 ทุกจุดที่สมมติว่าจำนวนแถว = จำนวนวันในช่วงจะพัง
/// ถ้าไม่เติมช่องว่างนี้ก่อน (คำสั่งที่ 17)
///
/// ⚠️ ห้ามเอาผลลัพธ์จากฟังก์ชันนี้ไปหาร "ค่าเฉลี่ยปริมาณ" (เช่น weeklyAvgCalories) เพราะ
/// densify เติม 0 ให้วันที่ไม่มีบันทึก ซึ่ง "ไม่มีข้อมูล" ไม่เท่ากับ "ศูนย์" — การหารด้วย
/// ความยาวชุด dense จะเป็นการยืนยันว่าวันนั้นกิน/เผา 0 kcal จริง ทั้งที่ความจริงคือไม่รู้
/// (ดูคำสั่งที่ 19) ใช้ผลลัพธ์นี้ได้เฉพาะกับสองประเภทงาน:
///   1. กราฟที่ต้องมีจุดครบทุกวันเพื่อไม่ให้เส้น/แท่งบิดเบือน (เว้นช่องว่างให้ถูกวัน)
///   2. เมตริกที่ "วัดการปฏิบัติ" ไม่ใช่ "วัดปริมาณ" เช่น เป้าหมายรายสัปดาห์/ความสม่ำเสมอ/
///      Adherence/streak ซึ่งวันที่ไม่บันทึก = ไม่ได้ทำตามเป้าจริง ตัวหาร 7 วันปฏิทินถูกต้อง
///      (ดู weeklyGoalDays ด้านล่างเทียบ)
/// ส่วนค่าเฉลี่ยปริมาณ (weeklyAvgCalories/monthlyAvgCalories/cmp.avgCal) ต้องหารด้วย
/// "จำนวนวันที่บันทึกจริง" เท่านั้น — คำนวณจากชุดข้อมูลดิบก่อน densify
List<T> densify<T>({
  required List<T> raw,
  required DateTime start,
  required DateTime end,
  required String Function(T) dateOf,
  required T Function(String date) emptyOf,
}) {
  final byDate = {for (final item in raw) dateOf(item).split('T').first: item};
  final out = <T>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final key = isoDate(d);
    out.add(byDate[key] ?? emptyOf(key));
  }
  return out;
}

Map<String, dynamic> asApiFailure(Object e) => {'success': false, 'message': e.toString()};

/// นับ streak วันติดกันของเดือนปัจจุบันเท่านั้น (badge หัวหน้าจอไม่ขึ้นกับ tab/period ที่กำลังดู)
/// currentMonthPts ต้องเป็นชุดที่ densify แล้ว (ครบทุกวันไม่มีช่องว่าง) และตัดจบที่วันนี้เสมอ
/// สำหรับเดือนปัจจุบัน — เรียกเฉพาะตอน selectedMonth ตรงกับเดือน/ปีปัจจุบันจริงเท่านั้น (คืน 0
/// ถ้าไม่ใช่ เพื่อกัน badge โชว์ streak ของเดือนอื่นที่ผู้ใช้กำลังเลื่อนดูอยู่)
int activeStreak({
  required DateTime selectedMonth,
  required List<MonthlyDataPoint> currentMonthPts,
  required List<MonthlyDataPoint> prevMonthPts,
}) {
  final now = DateTime.now();
  if (selectedMonth.year != now.year || selectedMonth.month != now.month) return 0;
  final pts = currentMonthPts;
  if (pts.isEmpty) return 0;
  bool active(MonthlyDataPoint p) => p.calories > 0 || p.weightOut > 0 || p.cardioOut > 0;

  // pts เป็นชุด densify แล้ว จึงมีครบทุกวันแบบไม่มีช่องว่าง — pts.last คือ "วันนี้" เสมอ
  // เดินถอยหลังทีละวันแล้วเจอวันว่าง (ไม่มีบันทึกจริง) เมื่อไหร่ = ขาดตอนจริง หยุดนับทันที
  //
  // ข้อยกเว้น: ถ้า "วันนี้" ยังไม่มีบันทึก ยังไม่ถือว่าขาดตอน (วันนี้ยังไม่จบ) ให้เริ่มนับจาก
  // เมื่อวานแทน ตามมาตรฐานแอปนับ streak ทั่วไป (เช่น Duolingo) — ถือว่าขาดตอนจริงก็ต่อเมื่อ
  // เมื่อวานก็ไม่มีข้อมูลด้วย
  int start = pts.length - 1;
  if (!active(pts[start])) start--;

  int s = 0;
  bool continuedFromDay1 = start >= 0;
  for (int i = start; i >= 0; i--) {
    if (active(pts[i])) {
      s++;
    } else {
      continuedFromDay1 = false;
      break;
    }
  }
  // ถ้าฝึกต่อเนื่องตั้งแต่วันที่ 1 ของเดือนนี้ (หรือเมื่อวาน กรณีวันนี้ยังไม่บันทึก) ไม่มีวันขาด
  // เลย ให้นับต่อจาก monthData ของเดือนก่อนหน้า กันไม่ให้ streak รีเซ็ตทุกครั้งที่ข้ามเดือน
  if (continuedFromDay1) {
    for (int i = prevMonthPts.length - 1; i >= 0; i--) {
      if (active(prevMonthPts[i])) {
        s++;
      } else {
        break;
      }
    }
  }
  return s;
}

// ตัวหาร 7 วันปฏิทินที่ใช้ในนี้ถูกต้องแล้ว — คนละนิยามกับค่าเฉลี่ยปริมาณ (weeklyAvgCalories
// เป็นต้น) ที่ต้องหารด้วยจำนวนวันที่บันทึกจริงเท่านั้น (ดูหมายเหตุเหนือ densify) เพราะตรงนี้
// "วัดการปฏิบัติตามเป้า" ไม่ใช่ "วัดปริมาณ" — วันที่ไม่บันทึก = ไม่ได้ทำตามเป้าจริง ไม่ใช่
// ไม่มีข้อมูล ห้ามแก้ให้ไปหารด้วยจำนวนวันที่บันทึกเพื่อให้ "สอดคล้องกัน" กับตัวหารฝั่งค่าเฉลี่ย
int weeklyGoalDays({
  required List<WeeklyDataPoint> weekPts,
  required double targetCalories,
  required double tolerance,
}) {
  return weekPts.where((e) {
    return targetCalories > 0 &&
        e.calories >= targetCalories * (1 - tolerance) &&
        e.calories <= targetCalories * (1 + tolerance);
  }).length;
}

double adherenceRate({required int workoutDaysThisWeek, required int activePlanDays}) {
  final target = activePlanDays < 1 ? 1 : activePlanDays;
  return (workoutDaysThisWeek / target).clamp(0.0, 1.0);
}

List<double> fillTargetGaps(List<double> raw) {
  final out = List<double>.filled(raw.length, 0);
  double last = 0;
  for (int i = 0; i < raw.length; i++) {
    if (raw[i] > 0) last = raw[i];
    out[i] = last;
  }
  // วันแรกๆ ที่ยังไม่เจอค่าจริงเลย (last ยังเป็น 0) ให้ backfill จากค่าแรกที่เจอแทน
  final firstKnown = out.firstWhere((v) => v > 0, orElse: () => 0);
  for (int i = 0; i < out.length; i++) {
    if (out[i] == 0) out[i] = firstKnown;
  }
  return out;
}

/// ข้อความ/สี/ไอคอน insight บนแดชบอร์ด — ประเมินจากพลังงานนำเข้า/โปรตีน/เผาผลาญวันนี้
(String?, Color, IconData) computeInsight({
  required DailyAnalytics? daily,
  required double targetProtein,
  required double targetCalories,
  required double tolerance,
  required int workoutDaysThisWeek,
  required bool weeklyDataAvailable,
}) {
  if (daily == null) return (null, AppColors.primaryGreen, Icons.lightbulb_outline_rounded);
  final d = daily;

  // ยังไม่มีข้อมูลนำเข้า — ไม่ประเมินผล เพื่อไม่ให้แนะนำจากค่า 0
  if (d.totalCaloriesIn <= 0) {
    return (
      'ยังไม่ได้บันทึกอาหารวันนี้ — บันทึกเพื่อดูผลวิเคราะห์สมดุลพลังงาน',
      AppColors.textMuted,
      Icons.edit_note_rounded,
    );
  }
  if (d.totalProtein < targetProtein * 0.6) {
    return (
      'โปรตีนน้อยไป — เพิ่มอีก ${(targetProtein - d.totalProtein).round()}g ช่วยรักษากล้ามเนื้อ',
      const Color(0xFF5B8CFF),
      Icons.fitness_center_rounded,
    );
  }
  if (d.totalCaloriesIn > targetCalories * (1 + tolerance)) {
    return (
      'พลังงานเกินเป้า +${(d.totalCaloriesIn - targetCalories).round()}kcal — ลองเดิน 30 นาทีเพิ่ม',
      Colors.orange,
      Icons.directions_walk_rounded,
    );
  }
  if (workoutDaysThisWeek == 0 && weeklyDataAvailable) {
    return (
      'สัปดาห์นี้ยังไม่ได้ออกกำลังกายเลย — เริ่มเบาๆ วันนี้เลย!',
      Colors.orange,
      Icons.emoji_events_rounded,
    );
  }
  if (d.exerciseBurn > 300) {
    return (
      'เผาผลาญจากการออกกำลังกาย ${d.exerciseBurn.round()}kcal — ยอดเยี่ยม! 🔥',
      AppColors.primaryGreen,
      Icons.local_fire_department_rounded,
    );
  }
  return (null, AppColors.primaryGreen, Icons.lightbulb_outline_rounded);
}

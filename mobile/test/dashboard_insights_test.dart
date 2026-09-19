import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/utils/dashboard_insights.dart' as di;
import 'package:myapp/models/analytics_model.dart';

void main() {
  group('isSameDay', () {
    test('same y/m/d, different time -> true', () {
      expect(di.isSameDay(DateTime(2026, 9, 19, 8), DateTime(2026, 9, 19, 23)), isTrue);
    });
    test('different day -> false', () {
      expect(di.isSameDay(DateTime(2026, 9, 19), DateTime(2026, 9, 20)), isFalse);
    });
  });

  group('isoDate', () {
    test('pads month/day to 2 digits', () {
      expect(di.isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('densify', () {
    test('fills missing days with emptyOf, keeps existing raw values', () {
      final raw = [
        MonthlyDataPoint(date: '2026-09-01', calories: 100, caloriesOut: 50),
        MonthlyDataPoint(date: '2026-09-03', calories: 200, caloriesOut: 80),
      ];
      final result = di.densify<MonthlyDataPoint>(
        raw: raw,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 3),
        dateOf: (e) => e.date,
        emptyOf: (date) => MonthlyDataPoint(date: date, calories: 0, caloriesOut: 0),
      );
      expect(result.length, 3);
      expect(result[0].calories, 100);
      expect(result[1].date, '2026-09-02');
      expect(result[1].calories, 0); // เติมช่องว่าง
      expect(result[2].calories, 200);
    });
  });

  group('fillTargetGaps', () {
    test('carries last known value forward and backfills leading zeros', () {
      final result = di.fillTargetGaps([0, 0, 2000, 0, 2200]);
      expect(result, [2000, 2000, 2000, 2000, 2200]);
    });

    test('all zero stays zero (no known value to backfill)', () {
      expect(di.fillTargetGaps([0, 0, 0]), [0, 0, 0]);
    });
  });

  group('macroTargetPct', () {
    test('goalType 1 = ลดน้ำหนัก', () {
      expect(di.macroTargetPct(1), {'protein': 0.40, 'carb': 0.35, 'fat': 0.25});
    });
    test('goalType 2 = เพิ่มน้ำหนัก', () {
      expect(di.macroTargetPct(2), {'protein': 0.30, 'carb': 0.50, 'fat': 0.20});
    });
    test('goalType 3 = รักษาน้ำหนัก', () {
      expect(di.macroTargetPct(3), {'protein': 0.20, 'carb': 0.50, 'fat': 0.30});
    });
    test('goalType เพี้ยน (ไม่ใช่ 1/2/3) -> ห้ามเดา คืน 0 ทั้งชุด', () {
      expect(di.macroTargetPct(99), {'protein': 0.0, 'carb': 0.0, 'fat': 0.0});
    });
  });

  group('weeklyGoalDays', () {
    test('counts only days within ±tolerance of target', () {
      final pts = [
        WeeklyDataPoint(date: '2026-09-01', calories: 2000, caloriesOut: 0), // ตรงเป้า
        WeeklyDataPoint(date: '2026-09-02', calories: 2199, caloriesOut: 0), // ในช่วง +10%
        WeeklyDataPoint(date: '2026-09-03', calories: 2500, caloriesOut: 0), // เกิน +10%
        WeeklyDataPoint(date: '2026-09-04', calories: 1000, caloriesOut: 0), // ต่ำกว่า -10%
      ];
      final days = di.weeklyGoalDays(weekPts: pts, targetCalories: 2000, tolerance: 0.10);
      expect(days, 2);
    });

    test('targetCalories <= 0 -> ไม่มีวันไหนนับ (ยังไม่ตั้งเป้าหมาย)', () {
      final pts = [WeeklyDataPoint(date: '2026-09-01', calories: 0, caloriesOut: 0)];
      expect(di.weeklyGoalDays(weekPts: pts, targetCalories: 0, tolerance: 0.10), 0);
    });
  });

  group('adherenceRate', () {
    test('clamps at 1.0 even if workoutDays exceeds target', () {
      expect(di.adherenceRate(workoutDaysThisWeek: 5, activePlanDays: 3), 1.0);
    });
    test('normal ratio', () {
      expect(di.adherenceRate(workoutDaysThisWeek: 1, activePlanDays: 4), 0.25);
    });
    test('activePlanDays < 1 -> ใช้ 1 กันหารด้วยศูนย์', () {
      expect(di.adherenceRate(workoutDaysThisWeek: 1, activePlanDays: 0), 1.0);
    });
  });

  group('activeStreak', () {
    test('selectedMonth ไม่ตรงเดือนปัจจุบัน -> คืน 0 เสมอ', () {
      final notThisMonth = DateTime(2020, 1, 1);
      final pts = [MonthlyDataPoint(date: '2020-01-01', calories: 500, caloriesOut: 0)];
      expect(
        di.activeStreak(selectedMonth: notThisMonth, currentMonthPts: pts, prevMonthPts: const []),
        0,
      );
    });

    test('เดือนปัจจุบัน, วันนี้มีบันทึกต่อเนื่อง 3 วัน -> streak 3', () {
      final now = DateTime.now();
      final pts = [
        MonthlyDataPoint(date: di.isoDate(now.subtract(const Duration(days: 2))), calories: 500, caloriesOut: 0),
        MonthlyDataPoint(date: di.isoDate(now.subtract(const Duration(days: 1))), calories: 500, caloriesOut: 0),
        MonthlyDataPoint(date: di.isoDate(now), calories: 500, caloriesOut: 0),
      ];
      expect(
        di.activeStreak(selectedMonth: DateTime(now.year, now.month, 1), currentMonthPts: pts, prevMonthPts: const []),
        3,
      );
    });

    test('วันนี้ยังไม่บันทึก แต่เมื่อวานบันทึก -> ยังนับ streak ต่อจากเมื่อวาน (ไม่รีเซ็ตเป็น 0)', () {
      final now = DateTime.now();
      final pts = [
        MonthlyDataPoint(date: di.isoDate(now.subtract(const Duration(days: 1))), calories: 500, caloriesOut: 0),
        MonthlyDataPoint(date: di.isoDate(now), calories: 0, caloriesOut: 0), // วันนี้ยังไม่บันทึก
      ];
      expect(
        di.activeStreak(selectedMonth: DateTime(now.year, now.month, 1), currentMonthPts: pts, prevMonthPts: const []),
        1,
      );
    });
  });

  DailyAnalytics dailyFixture({
    double totalCaloriesIn = 1800,
    double totalProtein = 100,
    double exerciseBurn = 0,
  }) =>
      DailyAnalytics(
        totalCaloriesIn: totalCaloriesIn,
        totalCaloriesOut: 0,
        bmi: 22,
        bmr: 1500,
        tdee: 2000,
        targetTdee: 2000,
        weight: 65,
        goalType: 1,
        baseline: 1800,
        exerciseBurn: exerciseBurn,
        balance: 0,
        totalProtein: totalProtein,
        totalCarbs: 0,
        totalFat: 0,
        proteinPercent: 0,
        carbsPercent: 0,
        fatPercent: 0,
        isBmrEstimated: false,
      );

  group('computeInsight', () {
    test('daily เป็น null -> ไม่มีข้อความ', () {
      final (msg, _, _) = di.computeInsight(
        daily: null,
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 1,
        weeklyDataAvailable: true,
      );
      expect(msg, isNull);
    });

    test('ยังไม่กินอะไรเลย (caloriesIn <= 0) -> เตือนให้บันทึกอาหาร', () {
      final (msg, _, _) = di.computeInsight(
        daily: dailyFixture(totalCaloriesIn: 0),
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 1,
        weeklyDataAvailable: true,
      );
      expect(msg, contains('ยังไม่ได้บันทึกอาหารวันนี้'));
    });

    test('โปรตีนต่ำกว่า 60% ของเป้า -> เตือนโปรตีนน้อยไปก่อนเรื่องอื่น', () {
      final (msg, _, _) = di.computeInsight(
        daily: dailyFixture(totalCaloriesIn: 1800, totalProtein: 50),
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 1,
        weeklyDataAvailable: true,
      );
      expect(msg, contains('โปรตีนน้อยไป'));
    });

    test('พลังงานเกินเป้า +10% -> เตือนพลังงานเกินเป้า', () {
      final (msg, _, _) = di.computeInsight(
        daily: dailyFixture(totalCaloriesIn: 2300, totalProtein: 100),
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 1,
        weeklyDataAvailable: true,
      );
      expect(msg, contains('พลังงานเกินเป้า'));
    });

    test('ไม่ได้ออกกำลังกายเลยทั้งสัปดาห์ (มีข้อมูลสัปดาห์แล้ว) -> เตือนให้ออกกำลังกาย', () {
      final (msg, _, _) = di.computeInsight(
        daily: dailyFixture(totalCaloriesIn: 1900, totalProtein: 100),
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 0,
        weeklyDataAvailable: true,
      );
      expect(msg, contains('ยังไม่ได้ออกกำลังกายเลย'));
    });

    test('ทุกอย่างปกติ+เผาผลาญเยอะ -> ชมเชย', () {
      final (msg, _, _) = di.computeInsight(
        daily: dailyFixture(totalCaloriesIn: 1900, totalProtein: 100, exerciseBurn: 400),
        targetProtein: 100,
        targetCalories: 2000,
        tolerance: 0.10,
        workoutDaysThisWeek: 3,
        weeklyDataAvailable: true,
      );
      expect(msg, contains('เผาผลาญจากการออกกำลังกาย'));
    });
  });
}

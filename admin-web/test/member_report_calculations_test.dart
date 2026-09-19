import 'package:flutter_test/flutter_test.dart';
import 'package:myapp_admin/core/utils/member_report_calculations.dart' as report_calc;

void main() {
  group('bmrAscending', () {
    test('dedupes by mbh_record_date, keeps highest mbh_id per day, sorts ascending', () {
      final raw = [
        {'mbh_id': 3, 'mbh_record_date': '2026-09-02', 'mbh_bmi': 22.0},
        {'mbh_id': 2, 'mbh_record_date': '2026-09-01', 'mbh_bmi': 21.0}, // แถวผี (ก่อน mbh_id 1)
        {'mbh_id': 1, 'mbh_record_date': '2026-09-01', 'mbh_bmi': 20.5},
      ];
      final result = report_calc.bmrAscending(raw);
      expect(result.length, 2); // เหลือ 2 วัน ไม่ใช่ 3 แถว
      expect(result[0]['mbh_record_date'], '2026-09-01');
      expect(result[0]['mbh_id'], 2); // แถวผีที่ mbh_id สูงกว่าในวันเดียวกันชนะ
      expect(result[1]['mbh_record_date'], '2026-09-02');
    });

    test('empty input -> empty output', () {
      expect(report_calc.bmrAscending([]), isEmpty);
    });
  });

  group('bmiChangePoints', () {
    test('filters out rows where BMI is unchanged from previous point', () {
      final ascending = [
        {'mbh_id': 1, 'mbh_bmi': 22.0},
        {'mbh_id': 2, 'mbh_bmi': 22.0}, // ไม่เปลี่ยน (แก้ activity_level/target เฉยๆ) — ตัดออก
        {'mbh_id': 3, 'mbh_bmi': 21.5}, // เปลี่ยนจริง — เก็บไว้
        {'mbh_id': 4, 'mbh_bmi': 21.5}, // ไม่เปลี่ยนอีก — ตัดออก
      ];
      final result = report_calc.bmiChangePoints(ascending);
      expect(result.length, 2);
      expect(result[0]['mbh_id'], 1);
      expect(result[1]['mbh_id'], 3);
    });

    test('rows with null mbh_bmi are skipped', () {
      final ascending = [
        {'mbh_id': 1, 'mbh_bmi': null},
        {'mbh_id': 2, 'mbh_bmi': 22.0},
      ];
      final result = report_calc.bmiChangePoints(ascending);
      expect(result.length, 1);
      expect(result[0]['mbh_id'], 2);
    });
  });

  group('niceDayInterval', () {
    test('span <= 6 days -> interval of 1 day', () {
      const dayMs = 86400000.0;
      expect(report_calc.niceDayInterval(0, dayMs * 5), dayMs);
    });

    test('span of 30 days -> interval rounds up to ~5 days (≈6 labels)', () {
      const dayMs = 86400000.0;
      final interval = report_calc.niceDayInterval(0, dayMs * 30);
      expect(interval, dayMs * 5);
    });
  });
}

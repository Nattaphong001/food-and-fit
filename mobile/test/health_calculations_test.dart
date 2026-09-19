import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/utils/health_calculations.dart';

// ทดสอบสูตรที่ยังอยู่ฝั่ง Dart (ข้อยกเว้นของ formula-guard) — ค่าคาดหวังตรงกับเทสต์ฝั่ง Go
// (backend/services/calculator_test.go) เพื่อให้ 2 ฝั่งให้ผลตรงกันเสมอ
void main() {
  group('trainingVolume', () {
    test('Σ น้ำหนัก × Reps ต่อเซต (ตัวอย่าง FORMULAS.md: 60 กก. × 10 ครั้ง × 4 เซต = 2400)', () {
      final sets = List.generate(4, (_) => (weight: 60.0, reps: 10));
      expect(trainingVolume(sets), 2400);
    });

    test('ไม่มีเซตได้ 0', () {
      expect(trainingVolume(const []), 0);
    });

    test('ท่า bodyweight (น้ำหนัก 0) ไม่ทำให้ Volume ติดลบ/เพี้ยน', () {
      expect(trainingVolume([(weight: 0.0, reps: 20), (weight: 20.0, reps: 5)]), 100);
    });
  });

  group('cardioNetKcal — ตรงกับ services.NetEnergyKcal', () {
    test('จ๊อกกิ้ง 8.3 METs 30 นาที 70 กก. = 268.275', () {
      expect(cardioNetKcal(mets: 8.3, weightKg: 70, minutes: 30), closeTo(268.275, 0.001));
    });

    test('กระโดดเชือก 12.3 METs 30 นาที 70 กก. = 415.275 (ตรงผล API จริง)', () {
      expect(cardioNetKcal(mets: 12.3, weightKg: 70, minutes: 30), closeTo(415.275, 0.001));
    });

    test('METs ≤ 1 ได้ 0 ไม่ติดลบ', () {
      expect(cardioNetKcal(mets: 1.0, weightKg: 70, minutes: 30), 0);
      expect(cardioNetKcal(mets: 0.5, weightKg: 70, minutes: 30), 0);
    });
  });

  group('estimateOneRepMax (Epley)', () {
    test('60 กก. × 10 ครั้ง = 80.00', () {
      expect(estimateOneRepMax(60, 10), 80.0);
    });
  });

  group('bmiLabel เกณฑ์เอเชีย-แปซิฟิก', () {
    test('ขอบเขต 18.5 / 23.0 / 25.0', () {
      expect(bmiLabel(18.4), 'ผอมเกินไป');
      expect(bmiLabel(18.5), 'สมส่วน');
      expect(bmiLabel(22.9), 'สมส่วน');
      expect(bmiLabel(23.0), 'น้ำหนักเกิน');
      expect(bmiLabel(24.9), 'น้ำหนักเกิน');
      expect(bmiLabel(25.0), 'โรคอ้วน');
      expect(bmiLabel(0), '-');
    });
  });
}

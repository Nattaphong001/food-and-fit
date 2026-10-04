// ตัวช่วยคำนวณ/แสดงผลฝั่ง client — เฉพาะที่ควรอยู่ฝั่ง Dart จริง (ดู ../../../../CLAUDE.md ข้อ 2 และ
// .claude/skills/formula-guard): BMI/BMR/TDEE/เป้าหมายพลังงาน **ไม่คำนวณที่นี่** ต้องเรียก API เสมอ
// (backend services.CalculateGoals เป็นเจ้าของ) — ฟังก์ชัน calcBmr/calcTdee/calcTargetCalories เดิมที่เป็น
// fallback ซ้ำสูตร backend ถูกลบแล้ว (2026-09-19)
//
// ข้อยกเว้นที่คำนวณฝั่ง Dart ได้ (แสดงผลสด/preview ก่อนบันทึก backend ยังเป็นเจ้าของค่าที่บันทึกจริงเสมอ):
//   • Training Volume  → trainingVolume()
//   • Estimated 1RM    → estimateOneRepMax()
//   • Cardio Burn      → cardioNetKcal() (ตรงกับ services.CalculateCardioCalories เป๊ะ)
//   • สถานะ Energy Balance ±10% → energyBalanceStatus()

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

double bmiProgress(double bmi) {
  if (bmi <= 0) return -1;
  if (bmi < 18.5) return (bmi / 18.5 * 0.25).clamp(0.0, 0.25);
  if (bmi < 23) return (0.25 + ((bmi - 18.5) / 4.5) * 0.25).clamp(0.25, 0.50);
  if (bmi < 25) return (0.50 + ((bmi - 23) / 2.0) * 0.25).clamp(0.50, 0.75);
  return (0.75 + ((bmi - 25) / 15.0)).clamp(0.75, 0.99);
}

String bmiLabel(double bmi) {
  if (bmi <= 0) return '-';
  if (bmi < 18.5) return 'ผอมเกินไป';
  if (bmi < 23) return 'สมส่วน';
  if (bmi < 25) return 'น้ำหนักเกิน';
  return 'โรคอ้วน';
}

// สีตามเกณฑ์เดียวกับ bmiLabel() เป๊ะ — เดิม dashboard_view.dart มี _bmiColor แยกเขียนเกณฑ์ซ้ำเอง
// (18.5/23.0/25.0) หลุด sync กับ bmiLabel ได้ง่ายถ้าใครแก้จุดเดียว (เกิดมาแล้วครั้งหนึ่งกับ label
// ก่อนย้ายมารวมที่นี่ — ดูคอมเมนต์เดิมใน dashboard_view.dart) รวมมาไว้จุดเดียวกันแทน
Color bmiColor(double bmi) {
  if (bmi <= 0) return AppColors.textMuted;
  if (bmi < 18.5) return Colors.blueAccent;
  if (bmi < 23.0) return AppColors.primaryGreen;
  if (bmi < 25.0) return Colors.orange;
  return Colors.redAccent;
}

/// เกณฑ์ประเมินสถานะสมดุลพลังงาน ±10% ตามบทที่ 2 หัวข้อ 2.1.4.7
const double kEnergyBalanceTolerance = 0.10;

// สถานะ Energy Balance เทียบเป้าหมาย ±10% — ใช้ร่วมกันทั้ง dashboard_view.dart/nutrition_view.dart
// เดิมแต่ละหน้าคำนวณเอง คนละสี/คนละข้อความ (dashboard: แดง/ส้ม/เขียว "เกินเป้า/ต่ำกว่าเป้า/ตามเป้า"
// vs nutrition: ส้ม/ฟ้า/เขียว "เกินเป้า/ต่ำกว่าเป้า/ตามแผน") รวมมาไว้จุดเดียว ยึดตามเวอร์ชัน
// dashboard_view.dart เดิม (มีคอมเมนต์อ้างอิงบทที่ 2 ตรงๆ)
(String, Color) energyBalanceStatus(double caloriesIn, double target) {
  if (target <= 0) return ('-', AppColors.textMuted);
  final ratio = caloriesIn / target;
  if (ratio > 1 + kEnergyBalanceTolerance) return ('เกินเป้า', Colors.redAccent);
  if (ratio < 1 - kEnergyBalanceTolerance) return ('ต่ำกว่าเป้า', Colors.orange);
  return ('ตามเป้า', AppColors.primaryGreen);
}

// Estimated 1RM แบบ Dual-Formula (บทที่ 2 ข้อ 2.1.4.10, แก้ 2026-10-01 จาก Epley อย่างเดียว) — ตัวเลข
// ต้องตรงกับ services.EstimateOneRepMax ฝั่ง Go เป๊ะ (มีเทสต์ 2 ฝั่งล็อกค่าเดียวกัน):
//   reps 1-10  → Epley: weight × (1 + reps/30)
//   reps 11-20 → Desgorces: 100 × weight / (83.7677 × e^(−0.0338 × reps) + 17.6846)
//   reps > 20, reps < 1 หรือน้ำหนัก ≤ 0 → 0 (ประเมินไม่ได้ — ผู้เรียกต้องซ่อน/ข้ามค่า 0)
// แสดงผลอย่างเดียว ไม่บันทึก DB (กฎเหล็กข้อ 8.2) — เดิมเขียนสูตรนี้ซ้ำ 3 จุดใน
// weight_training_detail_view.dart/weight_training_exercise_view.dart รวมมาไว้จุดเดียว
const int kEpleyMaxReps = 10;
const int kDesgorcesMaxReps = 20;

double estimateOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps < 1 || reps > kDesgorcesMaxReps) return 0;
  final double est = reps <= kEpleyMaxReps
      ? weightKg * (1 + reps / 30)
      : 100 * weightKg / (83.7677 * math.exp(-0.0338 * reps) + 17.6846);
  return double.parse(est.toStringAsFixed(2));
}

// Training Volume = Σ (น้ำหนักที่ยก × Reps) ต่อเซต (บทที่ 2 ข้อ 2.1.4.13) — แสดงผลอย่างเดียว ไม่บันทึก DB
// (กฎเหล็กข้อ 8.2) เดิม inline ซ้ำ 4 ที่ใน view (dashboard_view, weight_training_detail_view,
// weight_training_exercise_view, workout_view) รวมมาไว้จุดเดียว — sets คือรายการ (น้ำหนัก, Reps) ต่อเซต
double trainingVolume(Iterable<({double weight, int reps})> sets) {
  double total = 0;
  for (final s in sets) {
    total += s.weight * s.reps;
  }
  return total;
}

// ค่าคงที่สูตร ACSM (บทที่ 2 ข้อ 2.1.4.10) — ต้องตรงกับ METOxygenMlPerKgPerMin / METKcalDivisor ใน
// backend/services/calculator.go
const double kMetOxygenMlPerKgPerMin = 3.5;
const double kMetKcalDivisor = 200.0;

// Cardio Burn (NET) สำหรับโชว์ตัวเลขวิ่งสดระหว่างออกกำลังกาย = (METs − 1) × 3.5 × น้ำหนัก(kg) / 200 × นาที
// ตรงกับ services.NetEnergyKcal ฝั่ง backend เป๊ะ (clamp METs ≤ 1 เป็น 0) — backend คำนวณค่าที่บันทึกจริงใหม่
// จาก DB ทุกครั้ง ไม่เชื่อค่านี้ (ไม่ได้ส่งขึ้น API) METs ต้องมาจาก DB (cardio.cdo_mets) เท่านั้น
double cardioNetKcal({required double mets, required double weightKg, required double minutes}) {
  if (mets <= 1) return 0;
  return ((mets - 1) * kMetOxygenMlPerKgPerMin * weightKg / kMetKcalDivisor) * minutes;
}

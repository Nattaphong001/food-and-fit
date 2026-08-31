// สูตรคำนวณสุขภาพฝั่ง client (fallback เมื่อ backend ยังไม่ส่งค่ามา)
// ต้องตรงกับ services/calculator.go (CalculateGoals) ฝั่ง backend เสมอ

double calcBmr({
  required double weightKg,
  required double heightCm,
  required double age,
  required bool isMale,
}) {
  final base = (10 * weightKg) + (6.25 * heightCm) - (5 * age);
  return isMale ? base + 5 : base - 161;
}

// ค่า Activity Factor ตามสูตรจริง (ห้ามแก้ตัวเลขชุดนี้)
const _activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];

// D1 เดิม (`mbs_activity_level` เคยเป็น DECIMAL(3,2) ปัดเศษ 1.375→1.38, 1.725→1.73) แก้แล้ว
// จริงที่ DB — คอลัมน์เป็น DECIMAL(4,3) เก็บเต็มความละเอียดแล้ว (ยืนยัน 2026-08-20)
// ยังคง snap ไว้เพราะ backend validation (helpers/validation.go ValidateActivityLevel) เช็คแค่
// ช่วง 1.2-1.9 ไม่ได้บังคับว่าต้องเป็น 1 ใน 5 ค่ามาตรฐาน — ถ้ามีช่องทางอื่นส่งค่ากลางๆ เช่น 1.6
// เข้ามาได้ ฝั่ง client จะ snap เข้าค่าที่ใกล้ที่สุดเสมอเพื่อกันไม่ให้ fallback TDEE เพี้ยนจาก 5 ค่าจริง
double _snapActivityFactor(double level) {
  return _activityFactors.reduce((a, b) => (level - a).abs() <= (level - b).abs() ? a : b);
}

double calcTdee({required double bmr, required double activityLevel}) {
  final mult = activityLevel > 0 ? _snapActivityFactor(activityLevel) : 1.55;
  return bmr > 0 ? bmr * mult : 0;
}

/// target: 1 = ลดน้ำหนัก (-20% ของ TDEE, ไม่ต่ำกว่า BMR), 2 = เพิ่มน้ำหนัก/กล้ามเนื้อ (+15%), อื่นๆ = รักษาน้ำหนัก
double calcTargetCalories({
  required double tdee,
  required double bmr,
  required int target,
}) {
  if (tdee <= 0) return 0;
  if (target == 1) {
    final deficit = tdee - (tdee * 0.20);
    return deficit < bmr ? bmr : deficit;
  }
  if (target == 2) return tdee + (tdee * 0.15);
  return tdee;
}

double bmiProgress(double bmi) {
  if (bmi <= 0) return -1;
  if (bmi < 18.5) return (bmi / 18.5 * 0.25).clamp(0.0, 0.25);
  if (bmi < 23) return (0.25 + ((bmi - 18.5) / 4.5) * 0.25).clamp(0.25, 0.50);
  if (bmi < 25) return (0.50 + ((bmi - 23) / 2.0) * 0.25).clamp(0.50, 0.75);
  return (0.75 + ((bmi - 25) / 15.0)).clamp(0.75, 0.99);
}

String bmiLabel(double bmi) {
  if (bmi <= 0) return '-';
  if (bmi < 18.5) return 'ผอม';
  if (bmi < 23) return 'ปกติ';
  if (bmi < 25) return 'น้ำหนักเกิน';
  return 'โรคอ้วน';
}

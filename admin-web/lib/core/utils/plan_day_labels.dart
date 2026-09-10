// วันฝึกของแผนมาตรฐานแบบภาษาคน (จันทร์/พุธ/ศุกร์ ฯลฯ) — ต้องตรงกับ planDayWeekday
// ฝั่ง Go (food_and_fit_api/controllers/workout_controller.go) ซึ่งใช้แปลง
// ptd_day_number (1..N ลำดับในแผน) -> วันจริงในสัปดาห์ตอน copy ไปให้สมาชิก
// ใช้ร่วมกันระหว่างหน้ารายการแผนกับหน้ารายละเอียดแผน กันหลุด sync กันตอนแก้ทีหลัง
// (อ่านอย่างเดียว ไม่กระทบการคำนวณ/endpoint เดิม)
const kThaiDayNames = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

const Map<int, List<int>> kPlanDayWeekday = {
  2: [1, 4],
  3: [1, 3, 5],
  4: [1, 2, 4, 5],
  5: [1, 2, 3, 4, 5],
  6: [1, 2, 3, 4, 5, 6],
};

// daysPerWeek ที่ไม่มีใน map (1, 7) ใช้ ptd_day_number ตรงตัว
String planDayLabel(int dayNumber, int daysPerWeek) {
  final wds = kPlanDayWeekday[daysPerWeek];
  if (wds == null) return 'วัน $dayNumber';
  final idx = dayNumber - 1;
  if (idx < 0 || idx >= wds.length) return 'วัน $dayNumber';
  final wd = wds[idx];
  return wd >= 1 && wd <= 7 ? 'วัน${kThaiDayNames[wd - 1]}' : 'วัน $dayNumber';
}

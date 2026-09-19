// สูตร/คำนวณสำหรับกราฟ BMR/TDEE/BMI ใน member_detail_view.dart — แยกออกจาก widget state
// เพื่อให้ทดสอบ/อ่านง่ายขึ้น เป็น pure function ล้วน ไม่แตะ widget/state

// --------------------------------------------
// [FEATURE] REPORT
// [FUNCTION] bmrAscending
// [DESCRIPTION] safety net ฝั่ง client เท่านั้น — ต้นตอ (backend เคย insert member_bmr_history
//               ซ้ำ 2 แถวต่อการบันทึกข้อมูลร่างกาย 1 ครั้ง) แก้แล้วที่ member_controller.go
//               (FIX-DOUBLE-WRITE) นี่กันไว้เผื่อแถวผีเก่าที่เกิดก่อนวันแก้ยังค้างอยู่ใน DB
//               (ไม่ได้ backfill/ลบข้อมูลเก่า) — endpoint นี้ไม่ได้ส่ง mbs_id มาด้วย จึงจัดกลุ่ม
//               ตาม mbh_record_date แทน (1 วัน = 1 จุดข้อมูลตามสคีมาอยู่แล้ว เป็นคีย์เดียวกับที่
//               แถวผีชนกันจริง) เก็บเฉพาะแถวที่ mbh_id สูงสุดของแต่ละวัน (แถวจริงที่เกิดทีหลังเสมอ)
//               แล้วเรียง mbh_id ascending
// [INPUT] bmrHistory (List จาก GET /admin/members/:id, backend คืนใหม่→เก่า)
// [OUTPUT] List<Map> เรียงเก่า→ใหม่ตาม mbh_id, ไม่มีวันซ้ำ
// [TABLES] member_bmr_history
// [RELATED] BMR_TDEE
// --------------------------------------------
List<Map> bmrAscending(List<dynamic> bmrHistory) {
  final byDate = <String, Map>{};
  for (final e in bmrHistory) {
    final row = e as Map;
    final date = (row['mbh_record_date'] ?? '').toString();
    final id = (row['mbh_id'] as num?)?.toInt() ?? 0;
    final existingId = (byDate[date]?['mbh_id'] as num?)?.toInt() ?? -1;
    if (id > existingId) byDate[date] = row;
  }
  final deduped = byDate.values.toList()
    ..sort((a, b) => ((a['mbh_id'] as num?)?.toInt() ?? 0).compareTo((b['mbh_id'] as num?)?.toInt() ?? 0));
  return deduped;
}

// --------------------------------------------
// [FEATURE] REPORT
// [FUNCTION] bmiChangePoints
// [DESCRIPTION] กรอง bmrAscending ให้เหลือเฉพาะจุดที่ BMI เปลี่ยนจากแถวก่อนหน้าจริง — BMI
//               เป็นฟังก์ชันของน้ำหนัก/ส่วนสูงเท่านั้น การแก้ activity_level/target ไม่ทำให้ BMI
//               เปลี่ยน ถ้าพล็อตทุกแถวเหมือนกราฟ BMR/TDEE จะเห็นจุดแบนราบซ้ำๆ ที่ไม่สื่อความหมายอะไรเพิ่ม
// [INPUT] ascending (ผลลัพธ์จาก bmrAscending)
// [OUTPUT] List<Map> เฉพาะแถวที่ mbh_bmi ต่างจากแถวก่อนหน้าในลำดับเวลา
// [RELATED] BMR_TDEE
// --------------------------------------------
List<Map> bmiChangePoints(List<Map> ascending) {
  final result = <Map>[];
  double? lastBmi;
  for (final row in ascending) {
    final bmi = (row['mbh_bmi'] as num?)?.toDouble();
    if (bmi == null) continue;
    if (lastBmi == null || bmi != lastBmi) {
      result.add(row);
      lastBmi = bmi;
    }
  }
  return result;
}

// --------------------------------------------
// [FEATURE] REPORT
// [FUNCTION] niceDayInterval
// [DESCRIPTION] คำนวณระยะห่าง label แกน X (หน่วยมิลลิวินาที) ให้ได้ประมาณ 6 label กระจายทั่วช่วง
//               วันที่จริง ปัดขึ้นเป็นจำนวนวันเต็มเสมอ กัน label วันที่ซ้ำกันตอนแก้ข้อมูลถี่ๆ
//               ในช่วงสั้น (แกน X เดิมใช้ index ทำให้จุดห่าง 1 วันกับ 3 เดือนถูกวาดห่างเท่ากัน
//               สัดส่วนแนวโน้มบิด — เปลี่ยนมาใช้ millisecondsSinceEpoch จริงแล้ว)
// [INPUT] minX, maxX: มิลลิวินาทีของจุดแรก/จุดสุดท้ายบนกราฟ
// [OUTPUT] double — ค่า interval ส่งให้ SideTitles
// [RELATED] BMR_TDEE
// --------------------------------------------
double niceDayInterval(double minX, double maxX) {
  const dayMs = 86400000.0;
  final spanDays = ((maxX - minX) / dayMs).ceil();
  if (spanDays <= 6) return dayMs;
  return (spanDays / 6).ceil() * dayMs;
}

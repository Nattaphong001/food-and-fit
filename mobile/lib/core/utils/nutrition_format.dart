// [FEATURE] FOOD_LOG
// ทำหน้าที่: แปลง "จำนวนหน่วยเสิร์ฟ" (dntt_quantity ฝั่งบันทึกจริง / qty ในตะกร้าก่อนบันทึก)
// เป็นปริมาณจริงที่ผู้ใช้อ่านเข้าใจ — จุดเดียวที่ทุกหน้าเรียกใช้ กันแต่ละหน้าคูณ/ปัดทศนิยมไม่ตรงกัน
//
// ปริมาณจริง = จำนวนหน่วยเสิร์ฟ × ntt_serving_weight (กรัม = 100 ทุกแถว, ออนซ์แล้วแต่ขนาดแก้ว
// จริงของเมนู 6/16/20 — ต้องอ่านจาก DB เสมอ ห้าม hardcode 100 ทุกหน่วยเหมือนโค้ดเดิม)
String servingAmountLabel(double servings, int servingWeight, String unit) {
  // servingWeight <= 0 เกิดตอนอาหารกรอกเอง (ไม่มีแถวใน nutrition ให้ผูก) ถือว่า servings
  // ที่ส่งมาคือปริมาณจริงอยู่แล้ว ไม่ต้องคูณซ้ำ
  final amount = servings * (servingWeight > 0 ? servingWeight : 1);
  final text = amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(1);
  return '$text $unit';
}

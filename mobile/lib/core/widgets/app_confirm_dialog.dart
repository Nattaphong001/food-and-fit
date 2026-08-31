// AppConfirmDialog — dialog ยืนยันการกระทำที่มีผลกระทบ/ย้อนกลับไม่ได้ (blocking modal)
// Component กลางแทนโค้ด Dialog ซ้ำๆ ที่เคยกระจายอยู่หลายไฟล์ (reset แผน, จบการฝึก, ลบแผน, logout)
// หน้าตาเดิมทุกจุดเป๊ะ (header วงกลมไอคอน + เนื้อหา + ปุ่ม Outlined/Elevated) แค่รวมจุดแก้ไว้ที่เดียว
//
// ปุ่ม: ซ้าย = ยกเลิก (Outlined), ขวา = ยืนยัน (Elevated) — ลำดับนี้ใช้กับ reset แผน/จบการฝึก/ลบแผน/logout
// เท่านั้น ไม่รวม dialog "ออกจากการฝึก" ที่สลับลำดับปุ่มไว้ต่างจากนี้โดยตั้งใจ (ของเดิม)
//
// color: สื่อความหมายของการกระทำ ห้ามใช้แดงพร่ำเพรื่อกับทุก dialog — แดง (default) เฉพาะ
// action ที่ทำลาย/สูญเสียข้อมูลจริง (ลบ, รีเซ็ต, ออกจากการฝึกที่ยังไม่บันทึก) ส่วน action ที่ไม่ได้
// ทำลายอะไร (จบการฝึกสำเร็จ, logout) ต้องส่ง color อื่นเข้ามาที่ตรงความหมายกว่า (เขียว/ฟ้า)
// ตัวหนังสือปุ่มยืนยันคำนวณอัตโนมัติจากความสว่างของ color กันปัญหาอ่านไม่ออก (เช่น primaryGreen สว่างมาก
// ต้องใช้ตัวหนังสือดำ ไม่ใช่ขาว)

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String content,
  String confirmLabel = 'ยืนยัน',
  String cancelLabel = 'ยกเลิก',
  Color color = AppColors.error,
}) async {
  final buttonTextColor = _buttonTextColorFor(color);

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dialogIconHeader(icon: icon, title: title, color: color),
          _dialogContentText(content),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(cancelLabel,
                        style: const TextStyle(color: AppColors.textBody, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(confirmLabel,
                        style: TextStyle(color: buttonTextColor, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return confirm == true;
}

// AppNoticeDialog — dialog แจ้งเตือนให้ "รับทราบ" อย่างเดียว (Acknowledge) ไม่ใช่ถาม yes/no
// ใช้ตอนบล็อกการกระทำเพราะติดเงื่อนไข (เช่น ลบไม่ได้เพราะมีข้อมูลเชื่อมอยู่) — คนละแบบกับ
// showAppConfirmDialog ที่ต้องมี 2 ทางเลือก ปุ่มเดียวเต็มความกว้างด้านล่าง สี default เป็น
// alertWarning (ส้ม) เพราะความหมายคือ "ติดเงื่อนไข" ไม่ใช่ทำลายข้อมูล (แดง) หรือยืนยันการกระทำ
Future<void> showAppNoticeDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String content,
  String buttonLabel = 'รับทราบ',
  Color color = AppColors.alertWarning,
}) async {
  final buttonTextColor = _buttonTextColorFor(color);

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dialogIconHeader(icon: icon, title: title, color: color),
          _dialogContentText(content),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(buttonLabel,
                    style: TextStyle(color: buttonTextColor, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ตัวหนังสือปุ่มคำนวณอัตโนมัติจากความสว่างของ color กันปัญหาอ่านไม่ออก
// (เช่น primaryGreen สว่างมาก ต้องใช้ตัวหนังสือดำ ไม่ใช่ขาว)
Color _buttonTextColorFor(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.light ? Colors.black : Colors.white;

Widget _dialogIconHeader({required IconData icon, required String title, required Color color}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24),
    color: color.withValues(alpha: 0.08),
    child: Column(
      children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 2)],
          ),
          child: Icon(icon, size: 30, color: color),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
      ],
    ),
  );
}

Widget _dialogContentText(String content) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    child: Text(
      content,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, color: AppColors.textBody, height: 1.6),
    ),
  );
}

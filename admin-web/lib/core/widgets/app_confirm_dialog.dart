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
import 'package:flutter/services.dart';
import '../theme/theme.dart';

// showAdminDialog — ห่อ showDialog ธรรมดาให้กด Esc ปิดได้ (คีย์บอร์ดลัดมาตรฐานฝั่งเว็บ Admin)
// ใช้แทน showDialog(...) ตรงๆ ในทุกหน้าที่เปิดฟอร์มเพิ่ม/แก้ไข — เนื้อหา dialog ข้างในไม่ต้องแก้อะไร
Future<T?> showAdminDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(ctx).pop(),
          ),
        },
        child: Builder(builder: builder),
      ),
    ),
  );
}

Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String content,
  String confirmLabel = 'ยืนยัน',
  String cancelLabel = 'ยกเลิก',
  Color color = AppColors.danger,
}) async {
  final buttonTextColor = _buttonTextColorFor(color);

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      clipBehavior: Clip.hardEdge,
      // ล็อกความกว้างไว้ — ไม่งั้น Row(Expanded ปุ่ม) ข้างในจะดึง Dialog ให้ยืดเต็มจอ (เห็นชัดบนเว็บ
      // จอกว้าง เพราะ Row มี mainAxisSize.max เป็นค่าเริ่มต้น ไม่สนใจ Column(mainAxisSize.min) ข้างนอก)
      child: SizedBox(
        width: 400,
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
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Text(cancelLabel),
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
  Color color = AppColors.warningText,
}) async {
  final buttonTextColor = _buttonTextColorFor(color);

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 400,
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
        Text(title, style: AppTextStyles.cardTitle),
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
      style: AppTextStyles.body.copyWith(height: 1.6),
    ),
  );
}

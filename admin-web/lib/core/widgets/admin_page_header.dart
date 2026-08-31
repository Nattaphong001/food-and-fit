// AdminPageHeader — แถวบนสุดมาตรฐานของหน้าจัดการข้อมูล Admin (จอกว้าง)
// [Breadcrumb + ชื่อหน้า] ชิดซ้าย, [ปุ่ม "เพิ่มใหม่"] ชิดขวา — โครงเดียวกันทุกหน้า

import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AdminPageHeader extends StatelessWidget {
  final List<String> breadcrumb;
  final VoidCallback? onAdd;
  final String addLabel;
  // ปุ่ม/ไอคอนก่อน breadcrumb — ใช้กับหน้า push-based ที่ต้องมีปุ่ม back (เช่นรายละเอียดสมาชิก)
  // default null ไม่กระทบหน้าอื่นที่ใช้ AdminPageHeader อยู่แล้ว
  final Widget? leading;
  // ปุ่มเสริมชิดขวาก่อนปุ่ม "เพิ่มใหม่" (เช่นปุ่มเข้าโหมด "เลือก" ของ bulk action — COMMON_UI)
  // default ว่างเปล่า ไม่กระทบหน้าอื่นที่ใช้ AdminPageHeader อยู่แล้ว
  final List<Widget> trailingActions;

  const AdminPageHeader({
    super.key,
    required this.breadcrumb,
    this.onAdd,
    this.addLabel = 'เพิ่มรายการ',
    this.leading,
    this.trailingActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < breadcrumb.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                    ),
                  Text(
                    breadcrumb[i],
                    style: i == breadcrumb.length - 1
                        ? AppTextStyles.pageTitle
                        : AppTextStyles.kpiLabel,
                  ),
                ],
              ],
            ),
          ),
          for (final action in trailingActions) ...[const SizedBox(width: 12), action],
          if (onAdd != null) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(addLabel),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

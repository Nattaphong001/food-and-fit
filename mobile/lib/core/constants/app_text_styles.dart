import 'package:flutter/material.dart';
import 'app_colors.dart';

/// สไตล์ข้อความหัวข้อมาตรฐาน — ใช้กับ AppBar title / page header ทุกหน้า
class AppTextStyles {
  static const String fontFamily = 'Inter';

  /// หัวข้อหลักของหน้า (AppBar title / page header)
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: AppColors.textDark,
  );

  /// หัวข้อรอง/คำอธิบายใต้หัวข้อหลัก
  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: AppColors.textMuted,
  );
}

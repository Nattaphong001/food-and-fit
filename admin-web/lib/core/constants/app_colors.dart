import 'package:flutter/material.dart';

// Design system: โทนเขียวสลับเทา ยึดสเปก "Admin Report Screens" —
// เทาคือสีหลักของหน้า (~80%) เขียวเต็มความอิ่มตัวใช้ Action หลักจุดเดียวต่อหน้าจอ
class AppColors {
  // ─── Primary ───────────────────────────────────────────────────────────────
  /// สีเขียวหลัก — ใช้กับปุ่ม, Active tab, เส้น highlight, กราฟชุดแรก
  static const Color primaryGreen = Color(0xFF10B981);

  /// เขียวอ่อน — กราฟชุดที่สอง (โทนเดียวกับ primaryGreen) เช่น สัดส่วนที่ 2 ของโดนัทชาร์ต
  static const Color primaryLight = Color(0xFFA7F3D0);

  // ─── Background & Surface ──────────────────────────────────────────────────
  /// พื้นหลังหน้าจอหลัก
  static const Color background = Color(0xFFF9FAFB);

  /// พื้นหลังการ์ดอ่อน (video row, table row, hover)
  static const Color surfaceLight = Color(0xFFF3F4F6);

  /// พื้นหลัง Dialog ฟอร์ม
  static const Color dialogBackground = Color(0xFFF3F4F6);

  /// พื้นแถวคู่ในตาราง Admin (แถวสลับสีอ่อนๆ ให้ไล่สายตาข้ามจอกว้างได้)
  static const Color rowStripe = Color(0xFFF9FAFB);

  // ─── Text ──────────────────────────────────────────────────────────────────
  /// ข้อความหลัก สีเข้ม เช่น ตัวเลขในการ์ดสรุป
  static const Color textDark = Color(0xFF111827);

  /// ข้อความรอง / คำอธิบาย / เนื้อหาในตาราง
  static const Color textBody = Color(0xFF374151);

  /// ข้อความ muted / placeholder / inactive tab / ป้ายกำกับ
  static const Color textMuted = Color(0xFF6B7280);

  // ─── Border & Divider ──────────────────────────────────────────────────────
  /// เส้นคั่น / border card / เส้นตารางกริดในกราฟ
  static const Color divider = Color(0xFFE5E7EB);

  /// border ช่องกรอกข้อมูล
  static const Color inputBorder = Color(0xFFE5E7EB);

  // ─── Feedback ──────────────────────────────────────────────────────────────
  /// สีแดง — ปุ่มจบการฝึก / error / ระงับการใช้งาน / ลบ
  static const Color error = Color(0xFFEF4444);

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — สำเร็จ ใช้เขียวแบรนด์ตรงๆ
  static const Color alertSuccess = primaryGreen;

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — ผิดพลาด
  /// เข้มกว่า AppColors.error โดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~4.8:1 (WCAG AA)
  static const Color alertError = Color(0xFFDC2626);

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — คำเตือน
  /// เข้มกว่าสีส้มทั่วไปโดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~5.2:1 (WCAG AA)
  static const Color alertWarning = Color(0xFFC2410C);

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — ข้อมูลทั่วไป
  /// เข้มกว่าฟ้าทั่วไปโดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~5.2:1 (WCAG AA)
  static const Color alertInfo = Color(0xFF2563EB);

  /// สีเขียวอ่อน — badge แคลอรี่
  static const Color calorieBadgeBg = Color(0xFFECFDF5);

  /// ข้อความใน badge แคลอรี่
  static const Color calorieBadgeText = primaryGreen;
}

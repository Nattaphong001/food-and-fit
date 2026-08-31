import 'package:flutter/material.dart';

class AppColors {
  // ─── Primary ───────────────────────────────────────────────────────────────
  /// สีเขียวหลัก — ใช้กับปุ่ม, Active tab, เส้น highlight
  static const Color primaryGreen = Color(0xFF2BEE8C);

  /// สีเขียวรอง — ใช้กับ bullet, indicator dot, เส้นคั่น, FAB
  static const Color accentGreen = Color(0xFF00F28A);

  // ─── Background & Surface ──────────────────────────────────────────────────
  /// พื้นหลังหน้าจอหลัก
  static const Color background = Color(0xFFF7F8FA);

  /// การ์ดสีเทา (detail card, content card)
  static const Color cardBackground = Color(0xFFECECEC);

  /// พื้นหลังการ์ดอ่อน (video row, table row)
  static const Color surfaceLight = Color(0xFFF6F6F6);

  /// พื้นหลัง Scaffold อ่อนมาก
  static const Color scaffoldGrey = Color(0xFFF9F9F9);

  // ─── Text ──────────────────────────────────────────────────────────────────
  /// ข้อความหลัก สีเข้ม
  static const Color textDark = Color(0xFF1A1A1A);

  /// ข้อความรอง / คำอธิบาย
  static const Color textBody = Color(0xFF686868);

  /// ข้อความ muted / placeholder / inactive tab
  static const Color textMuted = Color(0xFFA0A1A5);

  /// ข้อความสีฟ้าเทา (filter inactive)
  static const Color textBlueGrey = Color(0xFF8F9BB3);

  // ─── Border & Divider ──────────────────────────────────────────────────────
  /// เส้นคั่น / border card
  static const Color divider = Color(0xFFD0D0D2);

  /// border ช่องกรอกข้อมูล
  static const Color inputBorder = Color(0xFFD9D9D9);

  // ─── Accent — Workout Type Cards ───────────────────────────────────────────
  /// พื้นหลังการ์ดเวทเทรนนิ่ง
  static const Color weightBg = Color(0xFFFFEDD6);

  /// ไอคอนเวทเทรนนิ่ง
  static const Color weightIcon = Color(0xFFF77019);

  /// พื้นหลังการ์ดคาร์ดิโอ
  static const Color cardioBg = Color(0xFFE1ECFD);

  /// ไอคอนคาร์ดิโอ
  static const Color cardioIcon = Color(0xFF5898F6);

  // ─── Feedback ──────────────────────────────────────────────────────────────
  /// สีแดง — ปุ่มจบการฝึก / error
  static const Color error = Colors.redAccent;

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — สำเร็จ
  /// ใช้เขียวแบรนด์ primaryGreen ตรงๆ ตามที่ผู้ใช้ยืนยัน (contrast ตัวเลขต่ำ ~1.5:1 แต่ตัวหนังสือขาวหนา+ตัวเล็ก
  /// ยังอ่านออกจริงในแอป ผู้ใช้เช็คแล้วเลือกแบบนี้)
  static const Color alertSuccess = primaryGreen;

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — ผิดพลาด
  /// เข้มกว่า AppColors.error (Colors.redAccent) โดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~4.8:1 (WCAG AA)
  static const Color alertError = Color(0xFFDC2626);

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — คำเตือน
  /// เข้มกว่าสีส้มทั่วไปโดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~5.2:1 (WCAG AA)
  static const Color alertWarning = Color(0xFFC2410C);

  /// สีการ์ดแจ้งเตือน AppAlert (top_flash.dart) — ข้อมูลทั่วไป
  /// เข้มกว่าฟ้าทั่วไปโดยตั้งใจ — ต้องคู่กับตัวหนังสือขาว ได้ contrast ~5.2:1 (WCAG AA)
  static const Color alertInfo = Color(0xFF2563EB);

  /// สีเขียวอ่อน — badge แคลอรี่
  static const Color calorieBadgeBg = Color(0xFFE0F5E9);

  /// ข้อความใน badge แคลอรี่
  static const Color calorieBadgeText = Color(0xFF2BCC81);

  /// Progress bar พื้นหลัง (คาร์ดิโอ goal card)
  static const Color progressTrack = Color(0xFF339860);

  /// Progress bar fill (คาร์ดิโอ goal card)
  static const Color progressFill = Color(0xFFFF8C00);

  // ─── Status Badges (Schedule View) ─────────────────────────────────────────
  /// สีเขียว — ท่าฝึกที่ทำเสร็จแล้ว (Done)
  static const Color statusDoneBg = calorieBadgeBg; // ใช้โทนอ่อนร่วมกันได้
  static const Color statusDoneText = calorieBadgeText;

  /// สีส้ม — ท่าฝึกที่ทำไม่ครบ (Partial)
  static const Color statusPartialBg = weightBg; // ใช้พื้นส้มอ่อนจาก weightBg
  static const Color statusPartialText = weightIcon; // ดึงสีส้มเข้มจากไอคอนเวท

  /// สีเทา — ท่าฝึกที่ยังไม่ได้ทำ (Pending)
  static const Color statusPendingBg = surfaceLight;
  static const Color statusPendingText = textMuted;
}

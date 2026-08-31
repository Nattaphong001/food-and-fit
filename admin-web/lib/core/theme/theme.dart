// ══════════════════════════════════════════════
// [PAGE] THEME : ธีมกลางของแอปพลิเคชัน (Design System)
// [PAGE_PURPOSE] รวมศูนย์การกำหนดสี ตัวอักษร ระยะห่าง และสไตล์ของ Widget
//                ทั้งหมด เพื่อให้ทุกหน้าจอใช้ค่าชุดเดียวกัน ไม่ต้องประกาศ
//                สีหรือขนาดตัวอักษรซ้ำในแต่ละหน้า
// [PAGE_ROUTE] lib/core/theme/theme.dart
// [USES_FEATURES] COMMON_UI
// ══════════════════════════════════════════════
//
// วิธีใช้งาน:
//   MaterialApp(
//     theme: AppTheme.light,
//     home: const AdminDashboardScreen(),
//   );
//
// หมายเหตุเรื่องเวอร์ชัน Flutter:
//   ไฟล์นี้เขียนสำหรับ Flutter 3.27 ขึ้นไป ซึ่งเปลี่ยนชนิดของ theme ย่อย
//   จาก CardTheme / DialogTheme / TabBarTheme เป็น CardThemeData /
//   DialogThemeData / TabBarThemeData
//   หากใช้ Flutter เวอร์ชันเก่ากว่านั้น ให้ตัดคำว่า "Data" ท้ายชื่อคลาส
//   ทั้ง 3 จุดออก (คอมไพเลอร์จะฟ้องจุดที่ต้องแก้ให้เอง)

import 'package:flutter/material.dart';

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AppColors
// [DESCRIPTION] ชุดสีกลางของระบบ แบ่งเป็น 4 กลุ่ม คือ สีหลัก (เขียว),
//               สีเทาสำหรับข้อความและพื้นหลัง, สีสถานะ และสีสำหรับกราฟ
//               หลักการ: สีเทาคือสีหลักของหน้า (ประมาณ 80% ของพื้นที่)
//               ส่วนสีเขียวเต็มความอิ่มตัวใช้ได้จุดเดียวต่อหน้าจอเท่านั้น
// [OUTPUT] ค่าคงที่สี (Color) สำหรับเรียกใช้ทั้งแอป
// --------------------------------------------
class AppColors {
  AppColors._();

  // ---------- สีหลัก (Primary / Brand) ----------
  /// เขียวเข้ม ใช้กับข้อความบนพื้นอ่อน และสถานะ hover ของปุ่ม
  static const Color primaryDark = Color(0xFF059669);

  /// เขียวหลัก ใช้กับปุ่มหลัก (Action หลักของหน้า) และแท่ง/เส้นกราฟชุดแรก
  /// กฎ: หนึ่งหน้าจอ ใช้ปุ่มพื้นสีนี้ได้เพียงปุ่มเดียว
  static const Color primary = Color(0xFF10B981);

  /// เขียวอ่อน ใช้กับกราฟชุดที่สอง เพื่อให้อยู่ในตระกูลสีเดียวกับชุดแรก
  static const Color primaryLight = Color(0xFFA7F3D0);

  /// เขียวอ่อนมาก ใช้เป็นพื้นหลังของเมนูที่กำลังเลือกอยู่ และป้ายสถานะ
  static const Color primarySurface = Color(0xFFECFDF5);

  // ---------- สีเทา (Neutral) ----------
  /// ข้อความสำคัญที่สุด เช่น ตัวเลขในการ์ดสรุป (KPI)
  static const Color textPrimary = Color(0xFF111827);

  /// ข้อความเนื้อหาทั่วไป เช่น ข้อมูลในตาราง
  static const Color textSecondary = Color(0xFF374151);

  /// ป้ายกำกับ หัวตาราง ข้อความประกอบ และไอคอนที่ไม่ต้องการเน้น
  static const Color textMuted = Color(0xFF6B7280);

  /// ข้อความหรือปุ่มที่ถูกปิดการใช้งาน
  static const Color textDisabled = Color(0xFF9CA3AF);

  /// เส้นขอบการ์ด เส้นคั่นตาราง และเส้นตารางกริดในกราฟ
  static const Color border = Color(0xFFE5E7EB);

  /// พื้นหลังของหน้า (ใต้การ์ด)
  static const Color background = Color(0xFFF9FAFB);

  /// พื้นหลังของการ์ดและตาราง
  static const Color surface = Color(0xFFFFFFFF);

  /// พื้นหลังของแถวตารางเมื่อเอาเมาส์ชี้ และพื้นหลังกราฟส่วนที่ไม่เน้น
  static const Color surfaceHover = Color(0xFFF3F4F6);

  // ---------- สีสถานะ (Semantic) ----------
  // กฎ: ใช้เมื่อ "สื่อความหมาย" เท่านั้น ห้ามใช้เพื่อความสวยงาม
  // คู่ *Text คือสีตัวอักษร/ไอคอนบนพื้นสีหลักหรือพื้นเข้ม จูน contrast ให้ผ่าน
  // WCAG AA (≥ 4.5:1) กับทั้งพื้นขาวและตัวหนังสือขาวบนพื้นสีหลักแล้ว ห้ามใช้
  // ตัวหลัก (success/warning/danger/info) เป็นสีตัวอักษรบนพื้นอ่อนโดยตรง
  /// สำเร็จ / บัญชีปกติ / อยู่ในเกณฑ์สมส่วน
  static const Color success = Color(0xFF10B981);
  static const Color successSurface = Color(0xFFECFDF5);
  static const Color successText = Color(0xFF059669);

  /// เฝ้าระวัง / รอยืนยันตัวตน / น้ำหนักเกิน
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSurface = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFFC2410C);

  /// ผิดปกติ / บัญชีถูกระงับ / ลบข้อมูล / โรคอ้วน
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerSurface = Color(0xFFFEF2F2);
  static const Color dangerText = Color(0xFFDC2626);

  /// ข้อมูลทั่วไป / ลิงก์ / ผอมเกินไป
  static const Color info = Color(0xFF3B82F6);
  static const Color infoSurface = Color(0xFFEFF6FF);
  static const Color infoText = Color(0xFF2563EB);

  // ---------- สีสำหรับกราฟ (Chart) ----------
  /// พลังงานพื้นฐาน (Baseline Expenditure = BMR x 1.2) ในกราฟแท่งซ้อน
  static const Color chartBaseline = Color(0xFFD1D5DB);

  /// พลังงานจากการออกกำลังกาย (Exercise Burn) ในกราฟแท่งซ้อน
  static const Color chartExercise = Color(0xFF10B981);

  /// พลังงานที่รับเข้า (Energy In) จากการบันทึกโภชนาการ
  static const Color chartEnergyIn = Color(0xFF6EE7B7);

  /// เส้นเป้าหมาย (Target Calories) ที่ลากทับกราฟเพื่อเปรียบเทียบ
  // ยังไม่ถูกเรียกใช้ — สงวนไว้สำหรับเส้นเป้าหมาย (Target Calories)
  // ในหน้ารายงานทั่วไปฝั่ง member (ดู spec-หน้ารายงานทั่วไป.md ข้อ 1)
  static const Color chartTargetLine = Color(0xFFF59E0B);

  // ---------- Skeleton (สถานะกำลังโหลด) ----------
  // แยกจาก border/surfaceHover โดยตั้งใจแม้ค่าจะเท่ากันตอนนี้ — เพื่อไม่ให้ผูก
  // (couple) กับสีเส้นขอบ/พื้นหัวตาราง ถ้าวันหนึ่งปรับสีใดสีหนึ่งจะได้ไม่กระทบกัน
  /// พื้นของกล่องโครงร่างขณะโหลด
  static const Color skeletonBase = Color(0xFFE5E7EB);

  /// แถบไฮไลต์ที่กวาดผ่านขณะ shimmer — ต้องอ่อนกว่า skeletonBase ชัดเจน
  static const Color skeletonHighlight = Color(0xFFF3F4F6);
}

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AppSpacing / AppRadius
// [DESCRIPTION] ค่าระยะห่างและความโค้งมุมมาตรฐาน ยึดทวีคูณของ 4
//               เพื่อให้ทุกหน้าจอมีจังหวะการเว้นระยะเท่ากัน
// [OUTPUT] ค่าคงที่ตัวเลข (double) สำหรับ padding / margin / borderRadius
// --------------------------------------------
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0; // ระยะระหว่างการ์ดในแถวเดียวกัน
  static const double lg = 24.0; // ระยะระหว่างแถว และ padding รอบเนื้อหา
  static const double xl = 32.0;

  /// ระยะขอบในของการ์ด
  static const EdgeInsets cardPadding = EdgeInsets.all(20.0);

  /// ระยะขอบในของพื้นที่เนื้อหาหลัก (ถัดจาก Sidebar)
  static const EdgeInsets pagePadding = EdgeInsets.all(24.0);
}

class AppRadius {
  AppRadius._();

  static const double sm = 6.0; // ป้ายสถานะ (Badge), ชิป
  static const double md = 8.0; // ปุ่ม, ช่องกรอกข้อมูล
  static const double lg = 12.0; // การ์ด, ตาราง

  static final BorderRadius cardRadius = BorderRadius.circular(lg);
  static final BorderRadius buttonRadius = BorderRadius.circular(md);
  static final BorderRadius badgeRadius = BorderRadius.circular(sm);
}

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AppTextStyles
// [DESCRIPTION] ชุดรูปแบบตัวอักษรของระบบ จำกัดไว้เพียง 4 ขนาดหลัก
//               และ 3 น้ำหนัก เพื่อไม่ให้หน้าจอดูรก
// [OUTPUT] TextStyle สำหรับนำไปใช้กับ Widget โดยตรง
// --------------------------------------------
class AppTextStyles {
  AppTextStyles._();

  /// ตัวเลขในการ์ดสรุป (KPI) เช่น "1,248"
  static const TextStyle kpiValue = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// หน่วยที่ต่อท้ายตัวเลข KPI เช่น "คน" "kcal" — ต้องเล็กและจางกว่าตัวเลข
  static const TextStyle kpiUnit = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// ป้ายกำกับเหนือตัวเลข KPI เช่น "ผู้ใช้งาน"
  static const TextStyle kpiLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// ชื่อหน้าใน Header bar
  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// หัวข้อของการ์ด เช่น "พลังงานรวมทุกผู้ใช้"
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// เนื้อหาทั่วไป และข้อมูลในแถวตาราง
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  /// หัวคอลัมน์ของตาราง
  static const TextStyle tableHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  /// ข้อความประกอบ ป้ายกำกับแกนกราฟ และคำอธิบายใต้ภาพ
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  /// หัวข้อกลุ่มเมนูใน Sidebar เช่น "เวทเทรนนิ่ง" "คาร์ดิโอ"
  static const TextStyle sidebarSection = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textDisabled,
    letterSpacing: 0.5,
  );
}

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AppBmiPalette.colorOf / labelOf
// [DESCRIPTION] กำหนดสีและคำแปลผลของค่าดัชนีมวลกาย (BMI) ตามเกณฑ์มาตรฐาน
//               สำหรับประชากรเอเชีย-แปซิฟิก เพื่อให้กราฟการกระจาย BMI
//               ในหน้ารายงานสถิติสุขภาพใช้สีตรงกันทั้งระบบ
// [INPUT] bmi : double (ค่าดัชนีมวลกาย)
// [OUTPUT] Color สำหรับแท่งกราฟ และ String สำหรับข้อความแปลผล
// [FORMULA] เกณฑ์ตามบทที่ 2 หัวข้อ 2.1.4.1
//           ผอมเกินไป < 18.5 | สมส่วน 18.5-22.9 |
//           น้ำหนักเกิน 23.0-24.9 | โรคอ้วน >= 25.0
// [RELATED] BMR_TDEE, REPORT
// --------------------------------------------
class AppBmiPalette {
  AppBmiPalette._();

  static Color colorOf(double bmi) {
    if (bmi < 18.5) return AppColors.info;
    if (bmi < 23.0) return AppColors.success;
    if (bmi < 25.0) return AppColors.warning;
    return AppColors.danger;
  }

  static String labelOf(double bmi) {
    if (bmi < 18.5) return 'ผอมเกินไป';
    if (bmi < 23.0) return 'สมส่วน';
    if (bmi < 25.0) return 'น้ำหนักเกิน';
    return 'โรคอ้วน';
  }
}

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AppTheme.light
// [DESCRIPTION] ประกอบค่าสี ตัวอักษร และสไตล์ Widget ทั้งหมดเข้าเป็น
//               ThemeData ชุดเดียว สำหรับส่งให้ MaterialApp
// [OUTPUT] ThemeData ที่ใช้ได้ทันทีทั้งฝั่งผู้ดูแลระบบและฝั่งผู้ออกกำลังกาย
// --------------------------------------------
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primarySurface,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.primaryDark,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        onError: Colors.white,
        outline: AppColors.border,
      ),

      textTheme: base.textTheme.copyWith(
        headlineSmall: AppTextStyles.kpiValue,
        titleLarge: AppTextStyles.pageTitle,
        titleMedium: AppTextStyles.cardTitle,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.caption,
        labelMedium: AppTextStyles.kpiLabel,
      ),

      // การ์ด: ไม่มีเงา ใช้เส้นขอบบางแทน
      // เหตุผล: แดชบอร์ดที่การ์ดทุกใบมีเงาจะดูรกและอ่านลำดับชั้นยาก
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ปุ่มหลัก (พื้นเขียว) — ใช้ได้ปุ่มเดียวต่อหน้าจอ เช่น "Export PDF"
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
      ),

      // ปุ่มรอง (เส้นขอบ) — ใช้กับ Action อื่น ๆ ที่เหลือทั้งหมดในหน้า
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),

      // ตัวกรองช่วงเวลา: วัน / สัปดาห์ / เดือน / กำหนดเอง
      // ตัวที่เลือกใช้พื้นเขียวอ่อน ไม่ใช่เขียวทึบ เพื่อไม่ให้แย่งความสนใจ
      // จากปุ่ม Action หลัก
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primarySurface;
            }
            return AppColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryDark;
            }
            return AppColors.textMuted;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textDisabled),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.buttonRadius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.buttonRadius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.buttonRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),

      dataTableTheme: DataTableThemeData(
        headingRowColor:
            const WidgetStatePropertyAll(AppColors.surfaceHover),
        headingTextStyle: AppTextStyles.tableHeader,
        dataTextStyle: AppTextStyles.body,
        dividerThickness: 1,
        headingRowHeight: 48,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 52,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHover,
        labelStyle: AppTextStyles.caption,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.badgeRadius),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        elevation: 8,
      ),
    );
  }
}

// ══════════════════════════════════════════════
// ตารางสรุปดัชนีฟีเจอร์ของไฟล์นี้ (Feature Index)
//
// | FEATURE_TAG | ชื่อฟังก์ชัน/คลาส        | บรรทัดที่ (โดยประมาณ) |
// |-------------|--------------------------|----------------------|
// | COMMON_UI   | AppColors                | 30                   |
// | COMMON_UI   | AppSpacing               | 128                  |
// | COMMON_UI   | AppRadius                | 148                  |
// | COMMON_UI   | AppTextStyles            | 167                  |
// | COMMON_UI   | AppBadgeStyle.of         | 245                  |
// | COMMON_UI   | AppBmiPalette.colorOf    | 292                  |
// | COMMON_UI   | AppTheme.light           | 322                  |
// ══════════════════════════════════════════════
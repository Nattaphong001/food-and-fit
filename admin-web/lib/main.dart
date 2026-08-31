import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/theme.dart';
import 'services/admin_auth_service.dart';
import 'services/nutrition_service.dart';
import 'services/exercise_service.dart';
import 'views/login_view.dart';
import 'views/admin_shell_view.dart';
import 'views/admin_splash_view.dart';

// ปิด scrollbar อัตโนมัติที่ Flutter web/desktop แปะให้ทุก Scrollable โดย default —
// เพราะซ้อนกับ Scrollbar ที่ใส่เองแบบตั้งใจ (เช่น sidebar, AdminDataTable) กลายเป็นแท่งคู่
// ให้ทุกจุดที่ต้องการ scrollbar ใส่ Scrollbar widget เองแบบตั้งใจแทน
class _NoAutoScrollbarBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // เปิด semantics tree ค้างไว้เสมอ — Flutter Web ปกติ render เป็น canvas ล้วน
  // ไม่ expose widget (avatar, dropdown menu ฯลฯ) ให้ DOM/ARIA เห็น มีแค่ text field
  // ที่ auto-expose ให้ ผลคือ browser automation (TestSprite/Playwright) และ screen reader
  // คลิก/อ่าน widget แบบ custom ไม่ได้ บังคับเปิดไว้ตั้งแต่ start ตัดปัญหานี้ทั้งหมด
  RendererBinding.instance.ensureSemantics();
  await initializeDateFormatting('th', null);
  await GetStorage.init();
  Get.put(AdminAuthService());
  Get.lazyPut(() => NutritionService(), fenix: true);
  Get.lazyPut(() => ExerciseService(), fenix: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Food & Fit — Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: _NoAutoScrollbarBehavior(),
      locale: const Locale('th'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th'), Locale('en')],
      home: const AuthGate(),
    );
  }
}

// เช็ค session ค้างอยู่ก่อนตัดสินใจว่าจะพาไปหน้า login หรือหน้า admin shell
// (กันปัญหา refresh หน้าเว็บแล้วหลุด login ทั้งที่ token ยัง valid)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final auth = AdminAuthService.to;
      if (auth.isCheckingSession.value) {
        return const AdminSplashView();
      }
      return auth.isLoggedIn.value ? const AdminShellView() : const LoginView();
    });
  }
}

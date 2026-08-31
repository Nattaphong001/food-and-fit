import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_fonts/google_fonts.dart';

// Import ส่วนของ Core, Services และ Views
import 'core/constants/app_colors.dart';
import 'core/widgets/undo_snackbar.dart';
import 'services/auth_service.dart';
import 'services/member_service.dart';
import 'services/nutrition_service.dart';
import 'services/workout_service.dart';
import 'services/exercise_service.dart';
import 'services/analytics_service.dart';
import 'services/local_notification_service.dart';
import 'services/notification_service.dart';

// Views
import 'views/auth/welcome_view.dart';
import 'views/auth/login_view.dart';
import 'views/auth/register_view.dart';
import 'views/auth/forgot_password_view.dart';
import 'views/member/onboarding/personalize_profile_view.dart';
import 'views/member/onboarding/onboarding_result_view.dart';
import 'shell/main_shell.dart';
// import 'views/admin/admin_dashboard_view.dart'; // ปิด UI แอดมิน (ปิดทางเข้าถึง)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await LocalNotificationService.to.init();

  // ลงทะเบียน Services
  Get.put(AuthService());
  Get.lazyPut(() => MemberService(), fenix: true);
  Get.lazyPut(() => NutritionService(), fenix: true);
  Get.lazyPut(() => WorkoutService(), fenix: true);
  Get.lazyPut(() => ExerciseService(), fenix: true);
  Get.lazyPut(() => AnalyticsService(), fenix: true);
  Get.put(NotificationService());

  runApp(const GenZFitApp());
}

class GenZFitApp extends StatelessWidget {
  const GenZFitApp({super.key});

  // เดิม initialRoute ฝัง '/welcome' ตายตัวเสมอ ไม่เคยเช็ค token ที่ persist ไว้ใน
  // GetStorage เลย ทำให้ทุกครั้งที่แอปโดน kill กระบวนการเต็มรูป (force-stop, สไวป์ทิ้งจาก
  // recent apps, OS kill พื้นหลังตอนหน่วยความจำตึง, restart เครื่อง) ผู้ใช้หลุดไปหน้า Welcome
  // ต้อง login ใหม่ทุกครั้งทั้งที่ token ยังไม่หมดอายุ — เซสชันที่ทำค้างอยู่ (เช่นกำลังจับเวลา
  // ออกกำลังกาย) หายไปเงียบๆ ไปด้วย (พบจากทดสอบจริงบนเครื่อง 2026-08-21)
  // AuthService.onInit() (เรียกจาก Get.put ใน main() ก่อน runApp) ทำ checkLoginStatus()
  // แบบ synchronous ไปแล้ว (อ่าน GetStorage เสร็จก่อนถึงบรรทัดนี้เสมอ) จึงอ่านค่าที่นี่ได้ตรงๆ
  // ไม่ต้องรอ async — ตรรกะ role/profile-complete เดียวกับที่ login_view.dart ใช้ตอน login
  // สำเร็จ (บรรทัด 91-99) เพื่อให้ cold start กับ login สด พาไปหน้าเดียวกันเสมอ
  String _resolveInitialRoute() {
    final auth = AuthService.to;
    if (!auth.isLoggedIn.value) return '/welcome';
    // if (auth.userRole.value == 'admin') return '/admin/dashboard'; // ปิด UI แอดมิน (ปิดทางเข้าถึง)
    return auth.isProfileComplete.value ? '/home' : '/onboarding';
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Food And Fit App',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [undoRouteObserver],
      locale: const Locale('th', 'TH'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('th', 'TH'),
        Locale('en', 'US'),
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.10),
        ),
        child: child!,
      ),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryGreen,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: AppColors.primaryGreen,
        ),
        textTheme: GoogleFonts.kanitTextTheme(ThemeData.light().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.grey, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen, 
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      
      initialRoute: _resolveInitialRoute(),
      getPages: [
        GetPage(name: '/welcome', page: () => const WelcomeView()),
        GetPage(name: '/login', page: () => const LoginView()),
        GetPage(name: '/register', page: () => const RegisterView()),
        GetPage(name: '/forgot-password', page: () => const ForgotPasswordView()),
        GetPage(name: '/onboarding', page: () => const PersonalizeProfileView()),
        GetPage(name: '/onboarding-result', page: () => const OnboardingResultView()),
        GetPage(name: '/home', page: () => const MainShell()),
        // GetPage(name: '/admin/dashboard', page: () => const AdminDashboardView()), // ปิด UI แอดมิน
      ],
    );
  }
}
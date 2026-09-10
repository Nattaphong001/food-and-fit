import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/app_fab.dart';
import '../core/widgets/bottom_nav_bar.dart';
import '../services/daily_notification_engine.dart';
import '../services/local_notification_service.dart';
import '../services/notification_service.dart';
import '../services/workout_service.dart';
import '../views/member/home/home_view.dart';
import '../views/member/nutrition/nutrition_view.dart';
import '../views/member/workout/workout_view.dart';
import '../views/member/dashboard/new_dashboard_view.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late final ValueNotifier<int> _homeRefresh;
  late final ValueNotifier<int> _dashboardRefresh;
  // บอกแท็บ Nutrition/Dashboard ให้โหลดใหม่เมื่อผู้ใช้แก้ข้อมูลร่างกาย/เป้าหมายจากหน้า Home
  // (แยกจาก _dashboardRefresh เพราะตัวนั้นถูก NutritionView bump เองหลังบันทึกอาหารอยู่แล้ว
  // ถ้าใช้ตัวเดียวกันฟังด้วยจะวนลูปโหลดซ้ำตัวเอง)
  late final ValueNotifier<int> _profileRefresh;
  late final List<Widget> _pages;
  final _nutritionKey = GlobalKey<NutritionViewState>();

  @override
  void initState() {
    super.initState();
    _homeRefresh = ValueNotifier<int>(0);
    _dashboardRefresh = ValueNotifier<int>(0);
    _profileRefresh = ValueNotifier<int>(0);
    _pages = [
      HomeView(refreshNotifier: _homeRefresh, profileRefreshNotifier: _profileRefresh),
      NutritionView(key: _nutritionKey, dashboardRefreshNotifier: _dashboardRefresh,
          profileRefreshNotifier: _profileRefresh),
      WorkoutView(dashboardRefreshNotifier: _dashboardRefresh),
      NewDashboardView(refreshNotifier: _dashboardRefresh, profileRefreshNotifier: _profileRefresh),
    ];
    _checkDailyWorkoutReminder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.to.refreshCount();
    });
    ever(NotificationService.to.targetTab, (int? idx) {
      if (idx != null && mounted) {
        if (idx == 0) _homeRefresh.value++;
        if (idx == 3) _dashboardRefresh.value++;
        setState(() => _currentIndex = idx);
        NotificationService.to.targetTab.value = null;
      }
    });
  }

  // ตรวจสอบและแสดง workout notification เมื่อเปิดแอพวันใหม่
  Future<void> _checkDailyWorkoutReminder() async {
    // รอให้ frame แรก render เสร็จก่อนแสดง SnackBar
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasActivePlan = WorkoutService.to.hasActivePlan;
      await LocalNotificationService.to.checkWorkoutReminder(
        hasActivePlan: hasActivePlan,
        context: context,
      );
      await DailyNotificationEngine.to.check();
    });
  }

  @override
  void dispose() {
    _homeRefresh.dispose();
    _dashboardRefresh.dispose();
    _profileRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // เนื้อหาแต่ละหน้าเลื่อนทะลุลอดหลัง navbar แคปซูลได้จริง — พื้นหลังทึบเดิมของแต่ละหน้าย้าย
      // มารวมไว้ที่นี่ที่เดียว (หน้าย่อยตั้ง backgroundColor: transparent หมดแล้ว) เพราะถ้าแต่ละหน้า
      // ยังทาสีทึบเต็มจอเอง BackdropFilter ของ navbar จะเห็นแต่สีพื้นเรียบๆ เหมือนทึบตลอดไม่ว่าจะ
      // เลื่อนแค่ไหน
      extendBody: true,
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // ปุ่ม + เพิ่มอาหาร ยกลอยสูงกว่าตำแหน่งเกาะปกติ (ตาม AppBottomNavBar.raiseOffset) ให้ตรง
      // กับหลุมโค้งมนที่เจาะไว้ใน _NotchedPillClipper พอดี — โชว์เฉพาะหน้าอาหาร (index 1)
      floatingActionButton: _currentIndex == 1
          ? AppFab(onPressed: () => _nutritionKey.currentState?.addFood())
          : null,
      floatingActionButtonLocation: const _RaisedCenterDockedFabLocation(),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          // trigger refresh ทั้งตอนสลับเข้ามาแท็บนี้ และตอนแตะซ้ำขณะอยู่แท็บนี้อยู่แล้ว
          if (index == 0) _homeRefresh.value++;
          if (index == 3) _dashboardRefresh.value++;
          setState(() => _currentIndex = index);
        },
      ),
    );
  }
}

// เหมือน centerDocked ปกติ แต่ยกปุ่มขึ้นอีก raiseOffset px ให้ตรงกับหลุมโค้งมนที่ AppBottomNavBar
// เจาะไว้สูงกว่าขอบบนแคปซูลปกติ (ดู _NotchedPillClipper ในไฟล์ bottom_nav_bar.dart)
class _RaisedCenterDockedFabLocation extends FloatingActionButtonLocation {
  const _RaisedCenterDockedFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base = FloatingActionButtonLocation.centerDocked.getOffset(scaffoldGeometry);
    return Offset(base.dx, base.dy - AppBottomNavBar.raiseOffset);
  }
}

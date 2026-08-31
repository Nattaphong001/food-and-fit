import 'package:get/get.dart';

/// เก็บ "ธงสกปรก" (dirty flag) กลาง ไว้สำหรับให้แท็บ Home/Dashboard ตัดสินใจว่า
/// ต้องยิง API โหลดข้อมูลใหม่ไหมตอนถูกกดเข้ามา แทนที่จะยิงซ้ำทุกครั้ง
///
/// ยังไม่ได้ผูกใช้งานจริง — ไม่ได้ Get.put() เป็น service, และยังไม่มี service ไหน
/// (nutrition/workout/member) เรียก markXxxDirty() หลังบันทึก/แก้ไข/ลบ
/// ปัจจุบัน Home/Dashboard รีเฟรชผ่านกลไกอื่นแทน (ดู main_shell.dart _dashboardRefresh
/// + new_dashboard_view.dart ที่โหลดใหม่ทุกครั้งที่ initState/tab refresh/RefreshIndicator)
class DashboardCacheService extends GetxService {
  static DashboardCacheService get to => Get.find();

  bool dailyDirty = true;
  bool weeklyDirty = true;
  bool profileDirty = true;

  void markDailyDirty() => dailyDirty = true;
  void markWeeklyDirty() => weeklyDirty = true;
  void markProfileDirty() => profileDirty = true;
}

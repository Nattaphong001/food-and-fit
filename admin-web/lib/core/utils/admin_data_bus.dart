import 'package:flutter/foundation.dart';

// [FEATURE] COMMON_UI
// [FUNCTION] AdminDataBus
// [DESCRIPTION] แจ้งหน้าอื่นที่ถูก cache ค้างไว้ (admin_shell_view ใช้ IndexedStack กัน
//               initState รันซ้ำ) ให้รู้ว่าข้อมูลที่เกี่ยวโยงกันเปลี่ยนไปแล้ว เช่นหน้ารายการ
//               อาหารต้อง refetch หมวดหมู่ใหม่หลังหน้าหมวดหมู่เพิ่ม/แก้/ลบสำเร็จ ไม่งั้นจะยังเห็น
//               หมวดหมู่ที่ถูกลบไปแล้วค้างอยู่จนกว่าจะรีโหลดทั้งหน้าเว็บ
// [INPUT] -
// [OUTPUT] ValueNotifier<int> แยกตามโดเมนข้อมูล เพิ่มค่าทุกครั้งที่ CUD สำเร็จ ให้หน้าอื่น listen
// [RELATED] COMMON_UI
class AdminDataBus {
  AdminDataBus._();

  static final nutritionCategories = ValueNotifier<int>(0);
  static void bumpNutritionCategories() => nutritionCategories.value++;

  static final cardioCategories = ValueNotifier<int>(0);
  static void bumpCardioCategories() => cardioCategories.value++;

  static final muscleGroups = ValueNotifier<int>(0);
  static void bumpMuscleGroups() => muscleGroups.value++;
}

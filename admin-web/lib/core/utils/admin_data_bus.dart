import 'package:flutter/foundation.dart';

// [FEATURE] COMMON_UI
// [FUNCTION] AdminDataBus
// [DESCRIPTION] แจ้งหน้าอื่นที่ถูก cache ค้างไว้ (admin_shell_view ใช้ IndexedStack กัน
//               initState รันซ้ำ) ให้รู้ว่าข้อมูลที่เกี่ยวโยงกันเปลี่ยนไปแล้ว เช่นหน้ารายการ
//               อาหารต้อง refetch หมวดหมู่ใหม่หลังหน้าหมวดหมู่เพิ่ม/แก้/ลบสำเร็จ ไม่งั้นจะยังเห็น
//               หมวดหมู่ที่ถูกลบไปแล้วค้างอยู่จนกว่าจะรีโหลดทั้งหน้าเว็บ
//
// ทิศทางเดิมมีแค่ "หน้าหมวดหมู่" -> "หน้ารายการลูก" (เช่น เพิ่ม/ลบหมวดหมู่คาร์ดิโอ -> หน้ากิจกรรม
// คาร์ดิโอรู้ตัว refetch dropdown หมวดหมู่ใหม่) แต่ badge ตัวเลขบนการ์ดหมวดหมู่ (เช่น "N ท่าฝึก" /
// "N กิจกรรม" / "N รายการ") นับจากฝั่งลูกกลับมา ต้องมีทิศทางย้อนกลับด้วย ไม่งั้นเพิ่ม/ลบท่าฝึก
// ในหน้าท่าฝึกเวท แล้วกลับมาหน้ากลุ่มกล้ามเนื้อ (ที่ยังถูก cache ค้างไว้) ตัวเลขจะไม่ขยับจนกว่าจะ
// รีโหลดทั้งหน้าเว็บ — เพิ่ม 3 ตัวนี้ให้หน้าลูกยิงบอกหน้าหมวดหมู่แม่แทน
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

  // ยิงตอนท่าฝึกเวทถูกเพิ่ม/ลบ หรือกล้ามเนื้อโฟกัส (exercise-muscles) ถูกเพิ่ม/แก้/ลบ — หน้ากลุ่ม
  // กล้ามเนื้อฟังตัวนี้เพื่อ refetch badge "N ท่าฝึก" ต่อการ์ด
  static final weightExercises = ValueNotifier<int>(0);
  static void bumpWeightExercises() => weightExercises.value++;

  // ยิงตอนกิจกรรมคาร์ดิโอถูกเพิ่ม/แก้/ลบ — หน้าประเภทคาร์ดิโอฟังตัวนี้เพื่อ refetch badge
  // "N กิจกรรม" ต่อการ์ด (รวมเคสย้ายกิจกรรมข้ามหมวดหมู่ตอนแก้ไข)
  static final cardioActivities = ValueNotifier<int>(0);
  static void bumpCardioActivities() => cardioActivities.value++;

  // ยิงตอนรายการอาหารถูกเพิ่ม/แก้/ลบ — หน้าประเภทโภชนาการฟังตัวนี้เพื่อ refetch badge
  // "N รายการ" ต่อการ์ด (รวมเคสย้ายรายการอาหารข้ามหมวดหมู่ตอนแก้ไข)
  static final foodItems = ValueNotifier<int>(0);
  static void bumpFoodItems() => foodItems.value++;
}

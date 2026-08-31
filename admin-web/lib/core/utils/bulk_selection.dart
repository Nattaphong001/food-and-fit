// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] BulkSelection
// [DESCRIPTION] state กลางของโหมด multi-select/bulk action — เก็บ id ที่เลือกไว้เป็น Set<int>
//               คงอยู่ข้ามหน้า (pagination) และข้ามการเปลี่ยนตัวกรอง (ผู้เรียกเป็นคนตัดสินใจว่า
//               จะเตือนผู้ใช้เมื่อไหร่ผ่าน markFilterChanged/hasSelectionOutsideFilter) ใช้ร่วมกัน
//               ได้ทั้งหน้าฐานข้อมูลโภชนาการ/กิจกรรมคาร์ดิโอ/ท่าฝึกเวท (บรีฟ bulk action ข้อ "แยก
//               selection state ออกมาให้ชัด นำกลับมาใช้ซ้ำได้")
// [INPUT] เรียก toggle/selectAll/exit ตาม interaction ของผู้ใช้ (long-press, ปุ่ม "เลือก",
//         checkbox, ปุ่ม X/Esc)
// [OUTPUT] ids ที่เลือกอยู่ปัจจุบัน + isActive (กำลังอยู่ในโหมดเลือกหรือไม่)
// [RELATED] COMMON_UI
// --------------------------------------------
class BulkSelection {
  final Set<int> ids = {};
  bool isActive = false;

  // snapshot ของ "ตัวกรองตอนเลือกล่าสุด" — ใช้เทียบตอน filter เปลี่ยนว่ามีรายการที่เลือกไว้
  // หลุดออกนอกตัวกรองปัจจุบันหรือไม่ (ข้อกำหนด UX ข้อ 4: เตือนถ้ามีรายการเลือกอยู่นอกตัวกรอง)
  String? _filterSignatureAtSelection;
  bool hasSelectionOutsideFilter = false;

  bool get isEmpty => ids.isEmpty;
  int get count => ids.length;
  bool contains(int id) => ids.contains(id);

  void enter() => isActive = true;

  // ออกจากโหมดเลือก + ล้างรายการที่เลือกทั้งหมด (ปุ่ม X / Esc — ข้อกำหนด UX ข้อ 1)
  void exitAndClear() {
    isActive = false;
    ids.clear();
    _filterSignatureAtSelection = null;
    hasSelectionOutsideFilter = false;
  }

  void toggle(int id, String currentFilterSignature) {
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
      isActive = true;
    }
    _filterSignatureAtSelection ??= currentFilterSignature;
    hasSelectionOutsideFilter = false;
  }

  // เลือก/ยกเลิกเลือกทั้งหมดของ "ตัวกรองปัจจุบัน" เท่านั้น (ข้อกำหนด UX ข้อ 2 — ห้ามกำกวมว่าเลือก
  // ทั้งฐานข้อมูล) allIdsForCurrentFilter มาจาก endpoint /ids ที่ครอบทุกหน้าของตัวกรองนั้นแล้ว
  void selectAllForCurrentFilter(Iterable<int> allIdsForCurrentFilter, String currentFilterSignature) {
    ids.addAll(allIdsForCurrentFilter);
    isActive = true;
    _filterSignatureAtSelection = currentFilterSignature;
    hasSelectionOutsideFilter = false;
  }

  void deselectAllForCurrentFilter(Iterable<int> allIdsForCurrentFilter) {
    ids.removeAll(allIdsForCurrentFilter);
  }

  void removeAll(Iterable<int> idsToRemove) => ids.removeAll(idsToRemove);

  // เรียกทุกครั้งที่ตัวกรอง/คำค้นเปลี่ยน — ถ้ามีรายการเลือกค้างอยู่จากตัวกรองอื่น ตั้ง flag เตือน
  // (แสดงผลจริงอยู่ที่ผู้เรียก เช่น banner บน AdminBulkActionBar)
  void markFilterChanged(String newFilterSignature) {
    if (ids.isEmpty) return;
    if (_filterSignatureAtSelection != null && _filterSignatureAtSelection != newFilterSignature) {
      hasSelectionOutsideFilter = true;
    }
  }
}

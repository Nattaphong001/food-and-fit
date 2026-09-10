// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AdminBulkActionBar
// [DESCRIPTION] แถบลอยติดขอบล่างของโหมด multi-select — แสดงจำนวนที่เลือกตลอดเวลา + ปุ่ม
//               "เลือกทั้งหมด N รายการที่แสดงอยู่"/"ยกเลิกเลือกทั้งหมด" + ปุ่มการกระทำกลาง (เช่น
//               ย้ายหมวดหมู่ ส่งเข้ามาผ่าน middleActions) + ปุ่มลบสีแดงแยกออกจากปุ่มอื่นชัดเจน
//               (ข้อกำหนด UX ข้อ 3: กันกดพลาด) + ปุ่ม X ออกจากโหมด + banner เตือนถ้ามีรายการที่
//               เลือกไว้อยู่นอกตัวกรองปัจจุบัน (ข้อกำหนด UX ข้อ 4)
// [INPUT] selectedCount, totalForCurrentFilter, allSelectedForCurrentFilter,
//         hasSelectionOutsideFilter, onSelectAllForCurrentFilter, onClose, middleActions, onDelete
// [OUTPUT] แถบ UI ลอยด้านล่างจอ ใช้ร่วมกันได้ทุกหน้าที่มี bulk action
// [RELATED] COMMON_UI
// --------------------------------------------
import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AdminBulkActionBar extends StatelessWidget {
  final int selectedCount;
  final int totalForCurrentFilter;
  final bool allSelectedForCurrentFilter;
  final bool hasSelectionOutsideFilter;
  final VoidCallback onSelectAllForCurrentFilter;
  final VoidCallback onClose;
  final List<Widget> middleActions;
  final VoidCallback onDelete;

  const AdminBulkActionBar({
    super.key,
    required this.selectedCount,
    required this.totalForCurrentFilter,
    required this.allSelectedForCurrentFilter,
    this.hasSelectionOutsideFilter = false,
    required this.onSelectAllForCurrentFilter,
    required this.onClose,
    this.middleActions = const [],
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasSelectionOutsideFilter)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.amberAccent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'มีบางรายการที่เลือกไว้อยู่นอกตัวกรองปัจจุบัน (ยังถูกเลือกอยู่ ไม่หายไป)',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5),
                        ),
                      ),
                    ]),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'ออกจากโหมดเลือก (Esc)',
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: onClose,
                    ),
                    Text('เลือกอยู่ $selectedCount รายการ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: onSelectAllForCurrentFilter,
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary.withValues(alpha: 0.9)),
                      child: Text(
                        allSelectedForCurrentFilter ? 'ยกเลิกเลือกทั้งหมด' : 'เลือกทั้งหมด $totalForCurrentFilter รายการที่แสดงอยู่',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...middleActions,
                    Container(margin: const EdgeInsets.symmetric(horizontal: 10), width: 1, height: 24, color: Colors.white24),
                    ElevatedButton.icon(
                      onPressed: onDelete,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white, elevation: 0),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('ลบ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

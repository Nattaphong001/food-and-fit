// AdminFilterBar — แถบตัวกรองมาตรฐานของหน้าจัดการข้อมูล Admin (จอกว้าง)
// [ช่องค้นหา (debounce 400ms + Enter = ค้นหาทันที)] [dropdown/ตัวกรองเสริม ถ้ามี ผ่าน trailing] [ล้างตัวกรอง ถ้ามี] ... [viewToggle ชิดขวาสุด ถ้ามี]
// บรรทัดล่าง (ถ้าส่ง resultCount มา): "พบ N รายการ"
// ห่อ debounce ไว้ในตัวเอง ไม่ต้องให้แต่ละหน้าทำ Timer เอง

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AdminFilterBar
// [DESCRIPTION] แถบตัวกรองมาตรฐานของหน้าจัดการข้อมูล Admin — ช่องค้นหา + ตัวกรองเสริม (trailing)
//               ของแต่ละหน้า + ปุ่มล้างตัวกรองกลาง (แสดงเมื่อ showClearButton=true เท่านั้น) +
//               ตัวนับผลลัพธ์ (ถ้าส่ง resultCount) + viewToggle การ์ด/ตาราง (ถ้ามี)
// [INPUT] searchHint, onSearchChanged, trailing, viewToggle, resultCount, showClearButton,
//         onClearFilters — showClearButton ต้องคำนวณจากฝั่งหน้าเอง (component ไม่รู้ค่าตัวกรอง
//         เสริมของแต่ละหน้า เพราะ trailing เป็น Widget ล้วนๆ)
// [OUTPUT] แถบ UI ตัวกรอง + ปุ่มล้างตัวกรอง (ถ้ามี) + ข้อความตัวนับผลลัพธ์ (ถ้ามี)
// [RELATED] COMMON_UI
// --------------------------------------------
class AdminFilterBar extends StatefulWidget {
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final List<Widget> trailing;
  final Widget? viewToggle;
  final int? resultCount;
  final bool showClearButton;
  final VoidCallback? onClearFilters;
  static const Duration debounceDuration = Duration(milliseconds: 400);

  const AdminFilterBar({
    super.key,
    required this.searchHint,
    required this.onSearchChanged,
    this.trailing = const [],
    this.viewToggle,
    this.resultCount,
    this.showClearButton = false,
    this.onClearFilters,
  });

  @override
  State<AdminFilterBar> createState() => _AdminFilterBarState();
}

class _AdminFilterBarState extends State<AdminFilterBar> {
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AdminFilterBar.debounceDuration, () => widget.onSearchChanged(value));
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    widget.onSearchChanged(value);
  }

  // --------------------------------------------
  // [FEATURE] COMMON_UI
  // [FUNCTION] _handleClearFilters
  // [DESCRIPTION] ล้างข้อความในช่องค้นหาของ component เอง (มี TextEditingController ในตัว)
  //               แล้วแจ้งให้หน้าที่เรียกใช้รีเซ็ตทั้งช่องค้นหา (onSearchChanged('')) และตัวกรอง
  //               เสริมทั้งหมดของหน้านั้น (onClearFilters)
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _handleClearFilters() {
    _debounce?.cancel();
    _searchController.clear();
    widget.onSearchChanged('');
    widget.onClearFilters?.call();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // เดิมใช้ Wrap ให้ตัวกรองไหลขึ้นบรรทัดใหม่เมื่อพื้นที่ไม่พอ แต่ทำให้ viewToggle (อยู่นอก Wrap
    // เพื่อชิดขวาสุด) ลอยกลางแนวตั้งของทั้งบล็อกแทนที่จะอยู่บรรทัดเดียวกับตัวกรอง — เปลี่ยนเป็น
    // แถวเดียวเลื่อนแนวนอนได้แทน เพื่อให้ viewToggle ชิดขวาสุดเสมอไม่ว่าจะมีตัวกรองกี่ตัว
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        height: 40,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onChanged,
                          onSubmitted: _onSubmitted,
                          decoration: InputDecoration(
                            hintText: widget.searchHint,
                            hintStyle: AppTextStyles.kpiLabel,
                            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      for (final w in widget.trailing) ...[const SizedBox(width: 12), w],
                      if (widget.showClearButton && widget.onClearFilters != null) ...[
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: _handleClearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                          label: const Text('ล้างตัวกรอง'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.viewToggle != null) ...[
                const SizedBox(width: 12),
                widget.viewToggle!,
              ],
            ],
          ),
        ),
        if (widget.resultCount != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text('พบ ${widget.resultCount} รายการ', style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

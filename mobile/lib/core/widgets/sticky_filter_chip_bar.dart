// แถบตัวกรองหมวดหมู่แบบ Sticky Tab — ปุ่ม "ทั้งหมด" ปักหมุดซ้ายสุดเสมอ
// หมวดหมู่อื่นเลื่อนสไลด์ลอดใต้ปุ่มทั้งหมดเมื่อปัดซ้าย-ขวา
// ใช้ร่วมกันทั้งตัวกรองอาหาร (nutrition_view) และตัวกรองกิจกรรมออกกำลังกาย (workout_view)

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'cached_image.dart';

class FilterChipItem<T> {
  final T id;
  final String label;
  final String? imageUrl;
  const FilterChipItem({required this.id, required this.label, this.imageUrl});
}

class StickyFilterChipBar<T> extends StatefulWidget {
  /// items.first คือปุ่มที่จะถูกปักหมุดซ้ายสุด (เช่น "ทั้งหมด")
  final List<FilterChipItem<T>> items;
  final T selectedId;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;
  /// พื้นหลังแถบตัวกรอง — ปกติใช้ AppColors.background (เทาอ่อน) ให้กลืนกับพื้นหน้าจอทั่วไป
  /// แต่บาง sheet พื้นเป็นสีขาว (เช่น _ExercisePickerSheet) ต้อง override ให้ตรงกัน
  final Color backgroundColor;

  const StickyFilterChipBar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
    this.backgroundColor = AppColors.background,
  });

  @override
  State<StickyFilterChipBar<T>> createState() => _StickyFilterChipBarState<T>();
}

class _StickyFilterChipBarState<T> extends State<StickyFilterChipBar<T>> {
  final _restScrollController = ScrollController();

  @override
  void dispose() {
    _restScrollController.dispose();
    super.dispose();
  }

  // กดปุ่มที่ปักหมุด ("ทั้งหมด") → เลื่อนหมวดอื่นที่ค้างตำแหน่งกลับไปจุดเริ่มต้นเสมอ
  // กันงงว่าทำไมหมวดแรกๆ หายไปจากจอตอนกลับมาดู "ทั้งหมด" อีกครั้ง
  void _handleSelect(T id) {
    widget.onSelected(id);
    if (widget.items.isNotEmpty && id == widget.items.first.id && _restScrollController.hasClients) {
      _restScrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final pinned = widget.items.first;
    final rest = widget.items.skip(1).toList();

    return Container(
      color: widget.backgroundColor,
      padding: widget.padding,
      child: Row(
        children: [
          _chip(pinned),
          if (rest.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                controller: _restScrollController,
                scrollDirection: Axis.horizontal,
                child: Row(children: rest.map(_chip).toList()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(FilterChipItem<T> item) {
    final isSelected = item.id == widget.selectedId;
    return GestureDetector(
      onTap: () => _handleSelect(item.id),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primaryGreen : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.imageUrl != null) ...[
              ClipOval(
                child: SizedBox(width: 18, height: 18, child: cachedImage(item.imageUrl, fit: BoxFit.cover)),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.black : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// สร้าง SliverPersistentHeader(pinned: true) พร้อม StickyFilterChipBar ในตัว —
/// ใช้แทนที่ SliverToBoxAdapter เดิมใน CustomScrollView เพื่อให้แถบตัวกรองปักหมุดตอนเลื่อนจอ
SliverPersistentHeader stickyFilterChipSliver<T>({
  required List<FilterChipItem<T>> items,
  required T selectedId,
  required ValueChanged<T> onSelected,
  double height = 46,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
}) {
  return SliverPersistentHeader(
    pinned: true,
    delegate: _StickyFilterHeaderDelegate<T>(
      items: items,
      selectedId: selectedId,
      onSelected: onSelected,
      height: height,
      padding: padding,
    ),
  );
}

class _StickyFilterHeaderDelegate<T> extends SliverPersistentHeaderDelegate {
  final List<FilterChipItem<T>> items;
  final T selectedId;
  final ValueChanged<T> onSelected;
  final double height;
  final EdgeInsetsGeometry padding;

  _StickyFilterHeaderDelegate({
    required this.items,
    required this.selectedId,
    required this.onSelected,
    required this.height,
    required this.padding,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // ต้องบังคับสูงเท่า height เป๊ะ ไม่งั้น SliverPersistentHeader จะคำนวณ paintExtent/layoutExtent
    // ไม่ตรงกับ minExtent/maxExtent ที่ประกาศไว้ ทำให้ SliverGeometry invalid และจอค้างตอนแตะตัวกรอง
    return SizedBox(
      height: height,
      child: StickyFilterChipBar<T>(items: items, selectedId: selectedId, onSelected: onSelected, padding: padding),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyFilterHeaderDelegate<T> oldDelegate) {
    return oldDelegate.items != items || oldDelegate.selectedId != selectedId;
  }
}

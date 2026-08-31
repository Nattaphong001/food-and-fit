// AdminPaginationBar — แถบล่างมาตรฐานของหน้าจัดการข้อมูล Admin (จอกว้าง)
// [จำนวนรวมทั้งหมด] [dropdown จำนวนต่อหน้า] [ปุ่มก่อนหน้า/ถัดไป + เลขหน้า]
//
// ส่วน A: ทำ pagination แบบ client-side เท่านั้น (slice array ที่โหลดมาแล้วทั้งก้อน)
// เพราะยังไม่มี query param page/limit ฝั่ง backend (จะเพิ่มในส่วน B) — ปุ่มนี้ยังทำงานได้จริง
// กับข้อมูลที่มีอยู่แล้ว ไม่ใช่ UI เปล่าๆ

import 'package:flutter/material.dart';
import '../theme/theme.dart';

const List<int> kAdminPageSizeOptions = [10, 20, 50];

class AdminPaginationBar extends StatelessWidget {
  final int totalItems;
  final int pageSize;
  final int currentPage; // เริ่มที่ 1
  final ValueChanged<int> onPageSizeChanged;
  final ValueChanged<int> onPageChanged;

  const AdminPaginationBar({
    super.key,
    required this.totalItems,
    required this.pageSize,
    required this.currentPage,
    required this.onPageSizeChanged,
    required this.onPageChanged,
  });

  int get totalPages => totalItems == 0 ? 1 : ((totalItems - 1) ~/ pageSize) + 1;

  // รายการน้อยกว่า page size เล็กสุด = มีหน้าเดียวแน่นอน เปลี่ยนค่า "ต่อหน้า" ไปก็ไม่มีผล จึงซ่อนทิ้ง
  bool get _showPageSizeSelector => totalItems > kAdminPageSizeOptions.first;

  @override
  Widget build(BuildContext context) {
    final canPrev = currentPage > 1;
    final canNext = currentPage < totalPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text('ทั้งหมด $totalItems รายการ', style: AppTextStyles.kpiLabel),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showPageSizeSelector) ...[
                const Text('ต่อหน้า', style: AppTextStyles.kpiLabel),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: pageSize,
                  underline: const SizedBox.shrink(),
                  items: kAdminPageSizeOptions
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n', style: AppTextStyles.body)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onPageSizeChanged(v);
                  },
                ),
                const SizedBox(width: 16),
              ],
              IconButton(
                tooltip: 'หน้าก่อนหน้า',
                icon: const Icon(Icons.chevron_left, size: 20),
                color: canPrev ? AppColors.textPrimary : AppColors.textMuted,
                onPressed: canPrev ? () => onPageChanged(currentPage - 1) : null,
              ),
              Text('$currentPage / $totalPages', style: AppTextStyles.tableHeader.copyWith(color: AppColors.textPrimary)),
              IconButton(
                tooltip: 'หน้าถัดไป',
                icon: const Icon(Icons.chevron_right, size: 20),
                color: canNext ? AppColors.textPrimary : AppColors.textMuted,
                onPressed: canNext ? () => onPageChanged(currentPage + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

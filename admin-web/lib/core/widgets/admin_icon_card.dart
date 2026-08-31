// AdminIconCard — การ์ดกริดมาตรฐานสำหรับหน้าจัดการ "ประเภท/หมวดหมู่" (คาร์ดิโอ, โภชนาการ)
// ใช้แทน DataTable แถวเดียวเดิม ตามบรีฟรอบ 3 ข้อ 5.1/7.1 — การ์ดครอบมีมิติ (เงา/มุมโค้ง)
// พื้นที่ด้านบนโชว์รูปจริงถ้ามี (imageUrl) ไม่งั้น fallback เป็นไอคอน+สี identity เดิม

import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'admin_network_image.dart';

class AdminIconCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Color? accentColor;
  // เปิดคลิกทั้งการ์ดเพื่อ drill-down ดูรายการที่ผูกกับหมวดนี้ + badge นับจำนวน (แบบเดียวกับ
  // การ์ดกลุ่มกล้ามเนื้อ) — ไม่บังคับใส่ หน้าที่ไม่ต้องการ drill-down ไม่ต้องส่งมา
  final VoidCallback? onTap;
  final String? countLabel;
  final String? imageUrl;

  const AdminIconCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onEdit,
    required this.onDelete,
    this.accentColor,
    this.onTap,
    this.countLabel,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = accentColor ?? AppColors.primary;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: (imageUrl != null && imageUrl!.isNotEmpty)
                      ? AdminNetworkImage(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            color: accent.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child: Icon(icon, color: accent, size: 34),
                          ),
                        )
                      : Container(
                          color: accent.withValues(alpha: 0.12),
                          alignment: Alignment.center,
                          child: Icon(icon, color: accent, size: 34),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(subtitle!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                          if (countLabel != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(countLabel!, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(tooltip: 'แก้ไข', icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 18), onPressed: onEdit, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                    IconButton(tooltip: 'ลบ', icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

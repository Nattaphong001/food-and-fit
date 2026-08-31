// AdminIconListTile — การ์ดแนวนอนกะทัดรัดสำหรับหน้าจัดการ "ประเภท/หมวดหมู่" เมื่อรายการน้อย
// หรือเนื้อหาไม่ต้องการพื้นที่ไอคอนใหญ่ (บรีฟ P2 ข้อ 8/11) — ใช้แทน AdminIconCard (การ์ดแนวตั้ง
// ไอคอนใหญ่ด้านบน) ตอนรายการน้อยกว่า 6 ชิ้น (พื้นที่ว่างเยอะ) หรือเมื่อต้องการเห็นได้หลายรายการ
// ต่อจอโดยไม่ต้อง scroll (เช่นประเภทโภชนาการ)

import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'admin_network_image.dart';

class AdminIconListTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final Color? accentColor;
  final String? countLabel;
  final String? imageUrl;

  const AdminIconListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
    this.accentColor,
    this.countLabel,
    this.imageUrl,
  });

  @override
  State<AdminIconListTile> createState() => _AdminIconListTileState();
}

// ปุ่มแก้ไข/ลบโผล่ตอน hover เท่านั้น — ให้ตรงกับ pattern เดียวกับหน้ากลุ่มกล้ามเนื้อ/หมวดคาร์ดิโอ/
// ฐานข้อมูลโภชนาการ (มาตรฐานเดียวกันทั้งเว็บฝั่งแอดมิน) แถวนี้ไม่มีรูปใหญ่ให้ทับปุ่ม เลยทำให้ปุ่ม
// ทั้งคู่จางหาย/โผล่ตรงๆ แทนการทับซ้อนบนรูปแบบการ์ดรูปภาพ
class _AdminIconListTileState extends State<AdminIconListTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accentColor ?? AppColors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                        ? AdminNetworkImage(
                            widget.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => Container(
                              color: accent.withValues(alpha: 0.12),
                              alignment: Alignment.center,
                              child: Icon(widget.icon, color: accent, size: 22),
                            ),
                          )
                        : Container(
                            color: accent.withValues(alpha: 0.12),
                            alignment: Alignment.center,
                            child: Icon(widget.icon, color: accent, size: 22),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(widget.subtitle!, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                if (widget.countLabel != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(widget.countLabel!, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                ],
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovering ? 1 : 0,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'แก้ไข',
                      icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 18),
                      onPressed: widget.onEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      tooltip: 'ลบ',
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

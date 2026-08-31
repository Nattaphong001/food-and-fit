// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] AdminBreadcrumb
// [DESCRIPTION] แถบนำทางสั้นๆ แสดงลำดับชั้น root -> รายการที่กำลังดู สำหรับหน้า Admin แบบ
//               drill-down ที่ฝัง state ไว้ในตัวเอง (ไม่ push route ใหม่ sidebar เดิมยังอยู่)
// [INPUT] rootLabel (String), currentLabel (String?), onRootTap (VoidCallback?)
// [OUTPUT] currentLabel เป็น null = แสดงแค่ rootLabel เฉยๆ (กดไม่ได้)
//          ไม่ null = แสดง [rootLabel กดได้] › [currentLabel กดไม่ได้]
// [RELATED] COMMON_UI
// --------------------------------------------

import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AdminBreadcrumb extends StatelessWidget {
  final String rootLabel;
  final String? currentLabel;
  final VoidCallback? onRootTap;

  const AdminBreadcrumb({
    super.key,
    required this.rootLabel,
    this.currentLabel,
    this.onRootTap,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Row(
        children: [
          if (current == null)
            Flexible(
              child: Text(rootLabel, style: AppTextStyles.kpiLabel, overflow: TextOverflow.ellipsis),
            )
          else ...[
            Flexible(
              child: GestureDetector(
                onTap: onRootTap,
                child: Text(
                  rootLabel,
                  style: AppTextStyles.kpiLabel.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
            ),
            Flexible(
              child: Text(current, style: AppTextStyles.kpiLabel, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}

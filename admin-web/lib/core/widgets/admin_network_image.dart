// Image.network + shimmer skeleton ระหว่างโหลด (แทนภาพ pop ขึ้นทันทีตอนโหลดเสร็จ)
// ใช้ AdminShimmer/skeleton สีเดียวกับ AdminListStateView ให้ภาษา UI ตรงกันทั้งระบบ

import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'admin_list_state.dart';

class AdminNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const AdminNetworkImage(this.url, {super.key, this.fit = BoxFit.cover, this.errorBuilder});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return AdminShimmer(child: Container(color: AppColors.skeletonBase));
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}

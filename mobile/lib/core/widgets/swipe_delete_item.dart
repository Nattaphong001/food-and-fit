// Wrapper บาง ๆ รอบ Dismissible ให้ตรงตามมาตรฐาน swipe-to-delete ของแอป:
// ปัดซ้าย 60% เพื่อลบ + haptic สั่นเบา 1 จังหวะตอนรายการยุบตัวเสร็จ
// (แอนิเมชัน "Height Collapse & Layout Slide-Up" มาจาก resize animation ในตัวของ Dismissible เอง)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeDeleteItem extends StatelessWidget {
  final Key itemKey;
  final Widget child;
  final Widget background;
  final VoidCallback onDismissed;
  final Future<bool> Function(DismissDirection direction)? confirmDismiss;

  const SwipeDeleteItem({
    super.key,
    required this.itemKey,
    required this.child,
    required this.background,
    required this.onDismissed,
    this.confirmDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: itemKey,
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.6},
      background: background,
      confirmDismiss: confirmDismiss,
      onDismissed: (_) {
        HapticFeedback.lightImpact();
        onDismissed();
      },
      child: child,
    );
  }
}

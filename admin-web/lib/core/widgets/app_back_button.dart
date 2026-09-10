import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AppBackButton extends StatelessWidget {
  final VoidCallback? onTap;

  const AppBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.pop(context),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.40),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_left_rounded, size: 37, color: AppColors.textPrimary),
      ),
    );
  }
}

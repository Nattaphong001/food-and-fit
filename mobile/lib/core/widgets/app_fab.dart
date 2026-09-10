import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AppFab extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;

  const AppFab({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      onPressed: onPressed,
      backgroundColor: color ?? AppColors.primaryGreen,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }
}

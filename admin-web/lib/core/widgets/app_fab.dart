import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';

class AppFab extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;

  const AppFab({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      onPressed: onPressed,
      backgroundColor: color ?? AppColors.primary,
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 28),
    );
  }
}

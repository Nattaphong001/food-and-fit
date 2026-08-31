// AdminSplashView — หน้าจอระหว่างเช็ค session ตอนเปิดแอปครั้งแรก (บรีฟรอบ 3 ข้อ 1)
// แทนที่ Scaffold + CircularProgressIndicator เปล่าๆ เดิมใน AuthGate — ใช้ branding เดียวกับ
// LoginView (วงกลมไอคอนเขียว + ชื่อแอป) กันจอว่างระหว่างรอ auth check

import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class AdminSplashView extends StatelessWidget {
  const AdminSplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
              child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 20),
            const Text('Food & Fit — Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 24),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryGreen)),
          ],
        ),
      ),
    );
  }
}

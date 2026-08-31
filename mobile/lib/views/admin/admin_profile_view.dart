// หน้า: Admin Profile
// ทำหน้าที่: แสดงข้อมูลส่วนตัวของแอดมินที่ล็อกอินอยู่ และให้ logout ออกจากระบบ

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_page_header.dart';
import '../../services/auth_service.dart';

const Color _green = Color(0xFF1BB874);

class AdminProfileView extends StatelessWidget {
  final String name;
  final String email;
  final String organization;

  const AdminProfileView({
    super.key,
    required this.name,
    required this.email,
    required this.organization,
  });

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'ออกจากระบบ?',
      content: 'คุณต้องการออกจากระบบใช่หรือไม่?',
      confirmLabel: 'ออกจากระบบ',
      // ไม่ใช่ action ทำลายข้อมูล — แค่สลับโหมด/ออกจาก session ใช้ฟ้า (info) แทนแดง
      color: AppColors.alertInfo,
    );
    if (confirm) Get.find<AuthService>().logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const AppPageHeader(
              title: 'Admin Profile',
              subtitle: 'ข้อมูลผู้ดูแลระบบ',
            ),
            const SizedBox(height: 20),

            // Avatar
            Container(
              width: 100, height: 100,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 52, color: _green),
            ),
            const SizedBox(height: 16),

            // Name
            Text(
              name,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 4),

            // Email
            Text(
              email,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),

            const SizedBox(height: 24),

            // Info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                children: [
                  _infoRow(
                      icon: Icons.business_outlined,
                      label: 'Organization',
                      value: organization),
                  Divider(color: Colors.grey.shade100, height: 1),
                  _infoRow(
                      icon: Icons.shield_outlined,
                      label: 'Role',
                      value: 'Administrator'),
                ],
              ),
            ),

            const Spacer(),

            // Logout button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                child: const Text('ออกจากระบบ',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF44336),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showLogoutDialog(context),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, color: _green, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        const Spacer(),
        Text(value,
            style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      ]),
    );
  }
}
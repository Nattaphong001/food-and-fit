// หน้า: Change Password
// ทำหน้าที่: หน้าเปลี่ยนรหัสผ่าน ให้ผู้ใช้กรอกรหัสผ่านเดิมและรหัสผ่านใหม่เพื่อยืนยันการเปลี่ยน

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/auth_service.dart';
import '../../../services/remembered_credentials_service.dart';

class ChangePasswordView extends StatefulWidget {
  const ChangePasswordView({super.key});

  @override
  State<ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<ChangePasswordView> {
  late final TextEditingController _currentCtrl;
  late final TextEditingController _newCtrl;
  late final TextEditingController _confirmCtrl;
  bool _obsCurrent = true;
  bool _obsNew = true;
  bool _obsConfirm = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentCtrl = TextEditingController();
    _newCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      showAppAlert(context, 'รหัสผ่านใหม่ไม่ตรงกัน', type: AppAlertType.error);
      return;
    }
    final newPw = _newCtrl.text;
    if (newPw.length < 8) {
      showAppAlert(context, 'รหัสผ่านต้องมีความยาวอย่างน้อย 8 ตัวอักษร', type: AppAlertType.error);
      return;
    }
    setState(() => _isLoading = true);
    final result = await AuthService.to.changePassword(_currentCtrl.text, _newCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    showAppAlert(
      context,
      result['message'] ?? '',
      type: result['success'] == true ? AppAlertType.success : AppAlertType.error,
    );
    if (result['success'] == true) {
      // ถ้าเปิด "จดจำรหัสผ่าน" ไว้ตอนล็อกอิน รหัสที่จำไว้ต้องอัปเดตตามรหัสใหม่ทันที
      // ไม่งั้นค้างรหัสเก่า auto-fill แล้ว login ครั้งหน้าไม่ผ่าน
      final email = AuthService.to.getUserData()?['email']?.toString();
      if (email != null && email.isNotEmpty) {
        await RememberedCredentialsService.updatePasswordIfEmailMatches(email, _newCtrl.text);
      }
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(child: AppBackButton()),
        ),
        centerTitle: true,
        title: const Text('ความปลอดภัย',
            style: AppTextStyles.pageTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, size: 24, color: AppColors.primaryGreen),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("เปลี่ยนรหัสผ่าน", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                      Text("ต้องมีความยาวอย่างน้อย 8 ตัวอักษร", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            _buildPasswordField(
              label: "รหัสผ่านเดิม",
              controller: _currentCtrl,
              isObscured: _obsCurrent,
              onToggle: () => setState(() => _obsCurrent = !_obsCurrent),
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.divider, thickness: 0.5),
            const SizedBox(height: 24),

            _buildPasswordField(
              label: "รหัสผ่านใหม่",
              controller: _newCtrl,
              isObscured: _obsNew,
              onToggle: () => setState(() => _obsNew = !_obsNew),
            ),
            const SizedBox(height: 20),

            _buildPasswordField(
              label: "ยืนยันรหัสผ่านใหม่",
              controller: _confirmCtrl,
              isObscured: _obsConfirm,
              onToggle: () => setState(() => _obsConfirm = !_obsConfirm),
            ),

            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _changePassword,
                child: _isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text("อัปเดตรหัสผ่าน", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool isObscured,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isObscured,
          keyboardType: TextInputType.text,
          autocorrect: false,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 20),
            suffixIcon: IconButton(
              icon: Icon(isObscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppColors.textMuted),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            hintText: "••••••••",
          ),
        ),
      ],
    );
  }
}

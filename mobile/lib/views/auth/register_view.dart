// หน้า: Register
// ทำหน้าที่: หน้าสมัครสมาชิก ให้ผู้ใช้กรอกชื่อ อีเมล และรหัสผ่านเพื่อสร้างบัญชีใหม่

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/top_flash.dart';
import '../../services/auth_service.dart';
import 'otp_register_view.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    showAppAlert(context, message, type: isError ? AppAlertType.error : AppAlertType.success);
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showMessage('กรุณากรอกข้อมูลให้ครบทุกช่อง', isError: true);
      return;
    }

    if (password != confirm) {
      _showMessage('รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน', isError: true);
      return;
    }

    if (password.length < 8) {
      _showMessage('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.to.register(
        fullName: name,
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (result['success']) {
        _showMessage('ส่งรหัส OTP ไปที่อีเมลของคุณแล้ว');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OtpView(email: email)),
        );
      } else {
        _showMessage(result['message'] ?? 'เกิดข้อผิดพลาดในการลงทะเบียน', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: AppBackButton()),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ขั้นตอนที่ 1 จาก 3',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'สร้างบัญชีใหม่',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textDark, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'เริ่มต้นการเดินทางสู่สุขภาพที่ดีขึ้นไปกับเรา',
                style: TextStyle(fontSize: 15, color: AppColors.textBody),
              ),
              const SizedBox(height: 32),

              _buildLabel('ชื่อ-นามสกุล'),
              _buildTextField(controller: _nameController, hintText: 'John Doe', icon: Icons.person_outline_rounded),
              const SizedBox(height: 20),

              _buildLabel('อีเมล'),
              _buildTextField(controller: _emailController, hintText: 'hello@genz.fit', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 20),

              _buildLabel('รหัสผ่าน'),
              _buildPasswordField(
                controller: _passwordController,
                hintText: '••••••••',
                isObscured: _isPasswordObscured,
                onToggle: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
              ),
              const SizedBox(height: 20),

              _buildLabel('ยืนยันรหัสผ่าน'),
              _buildPasswordField(
                controller: _confirmController,
                hintText: '••••••••',
                isObscured: _isConfirmPasswordObscured,
                onToggle: () => setState(() => _isConfirmPasswordObscured = !_isConfirmPasswordObscured),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('สมัครสมาชิก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.inputBorder, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool isObscured,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: isObscured,
      keyboardType: TextInputType.text,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: IconButton(
          icon: Icon(isObscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textMuted, size: 20),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.inputBorder, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
      ),
    );
  }
}

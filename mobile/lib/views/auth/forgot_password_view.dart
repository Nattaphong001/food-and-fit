// หน้า: Forgot Password
// ทำหน้าที่: หน้าลืมรหัสผ่าน ให้ผู้ใช้กรอกอีเมลเพื่อขอรับ OTP สำหรับรีเซ็ตรหัสผ่าน

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/top_flash.dart';
import '../../services/auth_service.dart';
import '../../services/remembered_credentials_service.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;
  bool _isPasswordObscured = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    showAppAlert(context, message, type: isError ? AppAlertType.error : AppAlertType.success);
  }

  Future<void> _requestOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('กรุณากรอกอีเมลให้ถูกต้อง', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final result = await AuthService.to.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success']) {
      setState(() => _otpSent = true);
      _showMessage('ส่งรหัส OTP ไปที่อีเมลแล้ว');
    } else {
      _showMessage(result['message'] ?? 'เกิดข้อผิดพลาด', isError: true);
    }
  }

  Future<void> _resetPassword() async {
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    if (otp.length != 6) {
      _showMessage('กรุณากรอกรหัส OTP ให้ครบ 6 หลัก', isError: true);
      return;
    }
    if (newPassword.length < 8) {
      _showMessage('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final result = await AuthService.to.resetPassword(
      _emailController.text.trim(),
      otp,
      newPassword,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success']) {
      // ถ้าอีเมลนี้เคยกด "จดจำรหัสผ่าน" ไว้ตอนล็อกอิน ต้องอัปเดตรหัสที่จำไว้ตามรหัสใหม่
      // ไม่งั้นค้างรหัสเก่า auto-fill แล้ว login ครั้งหน้าไม่ผ่าน
      await RememberedCredentialsService.updatePasswordIfEmailMatches(
        _emailController.text.trim(),
        newPassword,
      );
      if (!mounted) return;
      _showMessage('เปลี่ยนรหัสผ่านสำเร็จ กรุณาเข้าสู่ระบบใหม่');
      Navigator.pop(context);
    } else {
      _showMessage(result['message'] ?? 'เกิดข้อผิดพลาด', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppBackButton(),
              ),
              const SizedBox(height: 12),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset_rounded, size: 32, color: AppColors.primaryGreen),
              ),
              const SizedBox(height: 20),
              const Text(
                'ลืมรหัสผ่าน?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _otpSent
                    ? 'กรอกรหัส OTP ที่ส่งไปยังอีเมล\nและตั้งรหัสผ่านใหม่'
                    : 'กรอกอีเมลของคุณด้านล่าง\nแล้วเราจะส่งรหัสกู้คืน (OTP) ไปให้คุณ',
                style: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // อีเมล (แสดงตลอด)
              _buildLabel('อีเมล'),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_otpSent,
                decoration: _inputDecoration('hello@genz.fit'),
              ),
              const SizedBox(height: 20),

              if (_otpSent) ...[
                _buildLabel('รหัส OTP'),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: _inputDecoration('000000').copyWith(counterText: ''),
                ),
                const SizedBox(height: 20),

                _buildLabel('รหัสผ่านใหม่'),
                TextField(
                  controller: _newPasswordController,
                  obscureText: _isPasswordObscured,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  decoration: _inputDecoration('••••••••').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordObscured ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _resetPassword,
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('เปลี่ยนรหัสผ่าน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _requestOtp,
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('ส่งรหัสกู้คืนรหัสผ่าน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
        ),
      );
}

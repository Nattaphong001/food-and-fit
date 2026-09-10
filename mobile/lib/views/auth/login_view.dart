// หน้า: Login
// ทำหน้าที่: หน้าล็อกอิน ให้ผู้ใช้กรอกอีเมลและรหัสผ่านเพื่อเข้าสู่ระบบ

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/top_flash.dart';
import '../../services/auth_service.dart';
import '../../services/remembered_credentials_service.dart';

class LoginView extends StatefulWidget {
  const LoginView({Key? key}) : super(key: key);

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  bool _isPasswordObscured = true;
  bool _rememberPassword = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final creds = await RememberedCredentialsService.load();
    if (creds != null && mounted) {
      setState(() {
        _emailController.text = creds.email;
        _passwordController.text = creds.password;
        _rememberPassword = true;
      });
    }
  }

  Future<void> _persistRememberedCredentials(String email, String password) async {
    if (_rememberPassword) {
      await RememberedCredentialsService.save(email, password);
    } else {
      await RememberedCredentialsService.clear();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    showAppAlert(context, message, type: isError ? AppAlertType.error : AppAlertType.success);
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('กรุณากรอกอีเมลและรหัสผ่าน', isError: true);
      return;
    }

    if (!email.contains('@')) {
      _showSnackBar('กรุณากรอกรูปแบบอีเมลให้ถูกต้อง', isError: true);
      return;
    }

    // ✅ ใช้ Get.find เพื่อดึง AuthService
    final authService = Get.find<AuthService>();
    final result = await authService.login(email, password);

    if (mounted) {
      if (result['success']) {
        if (result['restored'] == true) {
          showAppAlert(context, 'กู้คืนบัญชีสำเร็จ ยินดีต้อนรับกลับมา!', type: AppAlertType.success);
        } else {
          _showSnackBar(result['message']);
        }
        await _persistRememberedCredentials(email, password);
        _emailController.clear();
        _passwordController.clear();

        // ตรวจสอบ Role และสถานะ Profile แล้วเด้งไปหน้าที่ถูกต้อง
        // final role = result['role'];
        // if (role == 'admin') {
        //   Get.offAllNamed('/admin/dashboard'); // ปิด UI แอดมิน (ปิดทางเข้าถึง)
        // } else
        if (Get.find<AuthService>().isProfileComplete.value) {
          Get.offAllNamed('/home');
        } else {
          Get.offAllNamed('/onboarding');
        }
      } else {
        _showSnackBar(result['message'], isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 20.0),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // ---- Header ----
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen
                                      .withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.fitness_center,
                                  size: 48,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Food & Fit',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'เข้าสู่ระบบ',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 50),

                        // ---- Email ----
                        _buildLabel('อีเมล'),
                        _buildTextField(
                          controller: _emailController,
                          hintText: 'your@email.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 20),

                        // ---- Password ----
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLabel('รหัสผ่าน'),
                            GestureDetector(
                              onTap: () => Get.toNamed('/forgot-password'),
                              child: const Text(
                                'ลืมรหัสผ่าน?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                        _buildTextField(
                          controller: _passwordController,
                          hintText: '••••••••',
                          isPassword: true,
                          keyboardType: TextInputType.text,
                        ),
                        const SizedBox(height: 12),

                        // ---- Remember Password ----
                        // หมายเหตุ: ห้ามครอบ GestureDetector.onTap รอบ Checkbox ที่มี onChanged ของตัวเอง
                        // ซ้อนกัน — แตะตรง checkbox พอดีจะยิงทั้งสอง handler พร้อมกัน toggle 2 ครั้งหักล้างกันเอง
                        // (ค่าไม่เปลี่ยนจริงแม้ดูเหมือนกดแล้ว) ให้ Checkbox.onChanged เป็นเจ้าของ state คนเดียว
                        Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _rememberPassword,
                                onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                                activeColor: AppColors.primaryGreen,
                                checkColor: Colors.black,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                              child: const Text(
                                'จดจำรหัสผ่าน',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textBody,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ---- Login Button ----
                        Obx(() {
                          final isLoading = Get.find<AuthService>().isLoading.value;
                          return SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: isLoading ? null : _handleLogin,
                              child: isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'เข้าสู่ระบบ',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                            ),
                          );
                        }),

                        const SizedBox(height: 20),

                        // ---- Register Link ----
                        Center(
                          child: RichText(
                            text: TextSpan(
                              text: 'ยังไม่มีบัญชี? ',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textMuted,
                              ),
                              children: [
                                TextSpan(
                                  text: 'สมัครสมาชิก',
                                  style: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => Get.toNamed('/register'),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        // ---- Footer ----
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Center(
                            child: Text(
                              'Food & Fit © 2024',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String hintText,
    required TextEditingController controller,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _isPasswordObscured : false,
      keyboardType: keyboardType,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: AppColors.inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordObscured
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => setState(
                  () => _isPasswordObscured = !_isPasswordObscured,
                ),
              )
            : null,
      ),
    );
  }
}
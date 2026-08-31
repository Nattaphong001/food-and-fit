// หน้า: OTP Verification
// ทำหน้าที่: หน้ายืนยัน OTP ให้ผู้ใช้กรอกรหัส 6 หลักที่ส่งไปยังอีเมล เพื่อยืนยันการสมัครหรือรีเซ็ตรหัสผ่าน

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/top_flash.dart';
import '../../services/auth_service.dart';

class OtpView extends StatefulWidget {
  // รับค่าอีเมลมาจากหน้า Register เพื่อนำมาแสดงให้ผู้ใช้เห็น
  final String email;

  const OtpView({super.key, required this.email});

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    showAppAlert(context, message, type: isError ? AppAlertType.error : AppAlertType.success);
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      _showMessage('กรุณากรอกรหัส OTP ให้ครบ 6 หลัก', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    // --- เรียกใช้ AuthService ยิง API ตรวจสอบ OTP ---
    final result = await AuthService.to.verifyOtp(widget.email, otp);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      _showMessage('ยืนยันตัวตนสำเร็จ! กำลังพาไปตั้งค่าโปรไฟล์');
      
      Get.offAllNamed('/onboarding');
    } else {
      _showMessage(result['message'] ?? 'รหัส OTP ไม่ถูกต้อง หรือหมดอายุแล้ว', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppBackButton(),
              ),
              const SizedBox(height: 10),
              // --- ไอคอน หรือ รูปภาพประกอบ ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 60,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 30),

              // --- หัวข้อ ---
              const Text(
                'ยืนยันอีเมลของคุณ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              
              // --- ข้อความอธิบาย ---
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5),
                  children: [
                    const TextSpan(text: 'เราได้ส่งรหัส OTP 6 หลักไปที่อีเมล\n'),
                    TextSpan(
                      text: widget.email, // ดึงค่า email มาแสดงตรงนี้
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark),
                    ),
                    const TextSpan(text: '\nกรุณากรอกรหัสด้านล่างเพื่อดำเนินการต่อ'),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 20,
                    color: AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 20),
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 22),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text('ยืนยันรหัส OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 24),

              // --- ปุ่มขอรหัสใหม่ ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'ยังไม่ได้รับรหัสใช่ไหม?',
                    style: TextStyle(fontSize: 14, color: AppColors.textDark),
                  ),
                  // ...
                  TextButton(
                    onPressed: _isLoading 
                      ? null 
                      : () async {
                          _showMessage('กำลังส่งรหัส OTP ให้ใหม่...');
                          
                          // เรียกใช้ API Resend OTP
                          final result = await AuthService.to.resendOtp(widget.email);
                          
                          if (result['success']) {
                            _showMessage('ส่งรหัสใหม่ไปที่ ${widget.email} แล้ว');
                          } else {
                            _showMessage(result['message'], isError: true);
                          }
                        },
                    child: const Text(
                      'ส่งอีกครั้ง',
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.bold, 
                        color: AppColors.primaryGreen
                      ),
                    ),
                  ),
// ...
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
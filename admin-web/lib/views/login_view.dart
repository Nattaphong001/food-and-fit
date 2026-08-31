// [PAGE] ADMIN_LOGIN : เข้าสู่ระบบแอดมิน
// [PAGE_PURPOSE] ฟอร์ม login แอดมิน + role guard (ปฏิเสธบัญชีที่ไม่ใช่แอดมินทันที)
// [PAGE_ROUTE] /login (myapp_admin, Flutter Web)
// [USES_FEATURES] AUTH

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/constants/app_colors.dart';
import '../services/admin_auth_service.dart';
import '../services/remembered_credentials_service.dart';
import 'admin_shell_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberPassword = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final creds = await RememberedCredentialsService.load();
    // เช็คว่าช่องยังว่างอยู่ก่อน set — กัน race condition ที่ผู้ใช้พิมพ์เอง
    // ระหว่างรอ storage อ่านเสร็จ (async) แล้วค่าที่จำไว้ไป overwrite ทับกลางคัน
    if (creds != null && mounted && _emailCtrl.text.isEmpty && _passwordCtrl.text.isEmpty) {
      setState(() {
        // ใช้ .value แทน .text ตรงๆ — .text setter เซ็ต selection เป็น offset -1 (ไม่มี cursor
        // ที่ชัดเจน) ทำให้ช่องดูเหมือนแก้ไขไม่ได้บน Flutter Web ต้องระบุ selection เองให้ไปอยู่
        // ท้ายข้อความที่จำไว้ ผู้ใช้ถึงจะแก้ไข/พิมพ์ต่อได้ปกติ
        _emailCtrl.value = TextEditingValue(
          text: creds.email,
          selection: TextSelection.collapsed(offset: creds.email.length),
        );
        _passwordCtrl.value = TextEditingValue(
          text: creds.password,
          selection: TextSelection.collapsed(offset: creds.password.length),
        );
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
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final result = await AdminAuthService.to.login(email, password);

    if (!mounted) return;
    if (result['success'] == true) {
      await _persistRememberedCredentials(email, password);
      if (!mounted) return;
      Get.offAll(() => const AdminShellView());
    } else {
      setState(() => _errorText = result['message'] as String? ?? 'เข้าสู่ระบบไม่สำเร็จ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Food & Fit — Admin',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'เข้าสู่ระบบสำหรับผู้ดูแลระบบ',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 28),
                      if (_errorText != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.alertError.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.alertError.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _errorText!,
                            style: const TextStyle(color: AppColors.alertError, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        // ห้ามใส่ keyboardType: TextInputType.emailAddress — บน Flutter Web
                        // ชนกับตำแหน่ง cursor/selection ทำให้แก้ไขข้อความกลางช่องไม่ได้ (พิมพ์
                        // ต่อท้ายอย่างเดียว) เว็บนี้ใช้คีย์บอร์ดจริงเสมอ ไม่จำเป็นต้องใช้ hint นี้
                        decoration: InputDecoration(
                          labelText: 'อีเมล',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.inputBorder),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกอีเมล' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.inputBorder),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      // หมายเหตุ: ห้ามครอบ GestureDetector.onTap รอบ Checkbox ที่มี onChanged ของตัวเอง
                      // ซ้อนกัน — แตะตรง checkbox พอดีจะยิงทั้งสอง handler พร้อมกัน toggle 2 ครั้งหักล้างกันเอง
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                            child: const Text(
                              'จดจำรหัสผ่าน',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textBody),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Obx(() => SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: AdminAuthService.to.isLoading.value ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: AdminAuthService.to.isLoading.value
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                                  : const Text('เข้าสู่ระบบ',
                                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

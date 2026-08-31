// [PAGE] ADMIN_PROFILE : โปรไฟล์ผู้ดูแล + ข้อมูลระบบ (เว็บ)
// [PAGE_PURPOSE] ฟอร์มเดี่ยวอิงตาราง system_data แถวเดียว (sys_id เดียว ไม่มี multi-admin)
//                รวม C1 (ข้อมูลระบบ: องค์กร/วันที่เริ่มใช้ระบบ) กับ E1 (โปรไฟล์แอดมิน: ชื่อ/เปลี่ยนรหัสผ่าน)
//                เป็นหน้าเดียว เพราะเป็นแถวข้อมูลเดียวกัน แยกหน้าจะสร้าง UX ที่แปลก
// [PAGE_ROUTE] /admin > คลิก avatar/ชื่อที่ topbar
// [USES_FEATURES] AUTH

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/top_flash.dart';
import '../../services/admin_auth_service.dart';
import '../../services/api_client.dart';
import '../login_view.dart';

class AdminProfileView extends StatefulWidget {
  const AdminProfileView({super.key});

  @override
  State<AdminProfileView> createState() => _AdminProfileViewState();
}

class _AdminProfileViewState extends State<AdminProfileView> {
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  bool _hasError = false;
  bool _isSavingProfile = false;
  bool _isSavingPassword = false;

  String _email = '';
  final _fullNameCtrl = TextEditingController();
  final _organizationCtrl = TextEditingController();
  DateTime? _startDate;

  // ค่าตอนโหลดล่าสุด — ใช้เทียบว่ามีการแก้ไขจริงหรือยัง (ปุ่มบันทึกจะ enable เฉพาะตอน hasChanges)
  String _origFullName = '';
  String _origOrganization = '';

  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool get _hasProfileChanges =>
      _fullNameCtrl.text.trim() != _origFullName ||
      _organizationCtrl.text.trim() != _origOrganization;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fullNameCtrl.addListener(_rebuild);
    _organizationCtrl.addListener(_rebuild);
    _newPasswordCtrl.addListener(_rebuild);
  }

  void _rebuild() {
    setState(() {});
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _organizationCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final response = await _api.get('/admin/profile', forceRefresh: true);
      if (response.statusCode == 200) {
        final data = response.data as Map;
        setState(() {
          _email = (data['sys_email'] ?? '').toString();
          _fullNameCtrl.text = (data['sys_full_name'] ?? '').toString();
          _organizationCtrl.text = (data['sys_organization'] ?? '').toString();
          final startDateRaw = data['sys_start_date'];
          _startDate = startDateRaw == null ? null : DateTime.tryParse(startDateRaw.toString());
          _origFullName = _fullNameCtrl.text;
          _origOrganization = _organizationCtrl.text;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Future<void> _saveProfile() async {
    final fullName = _fullNameCtrl.text.trim();
    if (fullName.isEmpty) {
      showAppAlert(context, 'กรุณากรอกชื่อ-นามสกุล', type: AppAlertType.warning);
      return;
    }
    setState(() => _isSavingProfile = true);
    try {
      final response = await _api.put('/admin/profile', {
        'sys_full_name': fullName,
        'sys_organization': _organizationCtrl.text.trim().isEmpty ? null : _organizationCtrl.text.trim(),
        'sys_start_date': _startDate == null ? '' : DateFormat('yyyy-MM-dd').format(_startDate!),
      });
      if (response.statusCode == 200) {
        AdminAuthService.to.adminName.value = fullName;
        _origFullName = fullName;
        _origOrganization = _organizationCtrl.text.trim();
        if (mounted) showAppAlert(context, 'บันทึกข้อมูลสำเร็จ');
      } else {
        final msg = response.data is Map ? (response.data['error'] ?? 'บันทึกข้อมูลไม่สำเร็จ') : 'บันทึกข้อมูลไม่สำเร็จ';
        if (mounted) showAppAlert(context, msg.toString(), type: AppAlertType.error);
      }
    } catch (e) {
      if (mounted) showAppAlert(context, 'เกิดข้อผิดพลาด: $e', type: AppAlertType.error);
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final oldPw = _oldPasswordCtrl.text;
    final newPw = _newPasswordCtrl.text;
    final confirmPw = _confirmPasswordCtrl.text;

    if (oldPw.isEmpty || newPw.isEmpty) {
      showAppAlert(context, 'กรุณากรอกรหัสผ่านเดิมและรหัสผ่านใหม่', type: AppAlertType.warning);
      return;
    }
    if (newPw.length < 8) {
      showAppAlert(context, 'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร', type: AppAlertType.warning);
      return;
    }
    if (newPw != confirmPw) {
      showAppAlert(context, 'ยืนยันรหัสผ่านใหม่ไม่ตรงกัน', type: AppAlertType.warning);
      return;
    }

    final confirmed = await showAppConfirmDialog(
      context,
      icon: Icons.lock_reset_rounded,
      title: 'ยืนยันเปลี่ยนรหัสผ่าน?',
      content: 'ระบบจะให้คุณเข้าสู่ระบบใหม่หลังเปลี่ยนรหัสผ่านสำเร็จ',
      confirmLabel: 'ยืนยัน',
      color: AppColors.primaryGreen,
    );
    if (!confirmed) return;

    setState(() => _isSavingPassword = true);
    try {
      final response = await _api.put('/admin/profile/password', {
        'old_password': oldPw,
        'new_password': newPw,
      });
      if (response.statusCode == 200) {
        _oldPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
        if (!mounted) return;
        await showAppNoticeDialog(
          context,
          icon: Icons.lock_reset_rounded,
          title: 'เปลี่ยนรหัสผ่านสำเร็จ',
          content: 'กรุณาเข้าสู่ระบบใหม่ด้วยรหัสผ่านใหม่ของคุณ',
          color: AppColors.primaryGreen,
        );
        await AdminAuthService.to.logout();
        if (mounted) Get.offAll(() => const LoginView());
        return;
      }
      final msg = response.data is Map ? (response.data['error'] ?? 'เปลี่ยนรหัสผ่านไม่สำเร็จ') : 'เปลี่ยนรหัสผ่านไม่สำเร็จ';
      if (mounted) showAppAlert(context, msg.toString(), type: AppAlertType.error);
    } catch (e) {
      if (mounted) showAppAlert(context, 'เกิดข้อผิดพลาด: $e', type: AppAlertType.error);
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  InputDecoration _fieldDeco({String? label, IconData? icon}) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primaryGreen, size: 20) : null,
      );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('โหลดข้อมูลไม่สำเร็จ', style: TextStyle(color: AppColors.textBody)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchProfile, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }

    final saveButton = ElevatedButton(
      onPressed: (_hasProfileChanges && !_isSavingProfile) ? _saveProfile : null,
      child: _isSavingProfile
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : const Text('บันทึกการเปลี่ยนแปลง'),
    );
    // ปุ่ม disabled (ยังไม่แก้ไขค่าใดๆ) ต้องบอกเหตุผลด้วย Tooltip กันผู้ใช้งง
    final saveButtonWithTooltip =
        _hasProfileChanges ? saveButton : Tooltip(message: 'ยังไม่มีการเปลี่ยนแปลง', child: saveButton);

    // รวม "บัญชีของฉัน" + "ข้อมูลหน่วยงาน" เดิมเป็นการ์ดเดียว เพราะบันทึกพร้อมกันเป็นข้อมูลชุดเดียว
    final generalCard = _sectionCard(
      title: 'ข้อมูลทั่วไป',
      children: [
        TextField(
          decoration: _fieldDeco(label: 'อีเมล', icon: Icons.email_outlined).copyWith(
            fillColor: const Color(0xFFF3F5F4),
            filled: true,
            suffixIcon: Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
          ),
          style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.75)),
          controller: TextEditingController(text: _email),
          enabled: false,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _fullNameCtrl,
          decoration: _fieldDeco(label: 'ชื่อ-นามสกุล', icon: Icons.person_outline),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _organizationCtrl,
          decoration: _fieldDeco(label: 'หน่วยงานเจ้าของระบบ', icon: Icons.business_outlined),
        ),
        const SizedBox(height: 14),
        // วันที่เริ่มใช้ระบบ = วันที่สมัครสมาชิก ห้ามแก้ไข — แสดงผลอย่างเดียว ไม่มี date picker
        InputDecorator(
          decoration: _fieldDeco(label: 'วันที่เริ่มใช้ระบบ', icon: Icons.event_outlined),
          child: Text(
            _startDate == null ? 'ยังไม่ระบุ' : DateFormat('d MMM yyyy', 'th').format(_startDate!),
            style: const TextStyle(color: AppColors.textDark),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: saveButtonWithTooltip,
        ),
      ],
    );

    final passwordCard = _sectionCard(
      title: 'ความปลอดภัย',
      children: [
        TextField(
          controller: _oldPasswordCtrl,
          obscureText: _obscureOld,
          decoration: _fieldDeco(label: 'รหัสผ่านเดิม', icon: Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscureOld = !_obscureOld),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: _obscureNew,
          decoration: _fieldDeco(label: 'รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)', icon: Icons.lock_reset_rounded).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: _obscureConfirm,
          decoration: _fieldDeco(label: 'ยืนยันรหัสผ่านใหม่', icon: Icons.check_circle_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'เปลี่ยนรหัสผ่านสำเร็จแล้วระบบจะให้เข้าสู่ระบบใหม่ทันที',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
        // แถบวัดความแข็งแรงรหัสผ่าน — ย้ายมาไว้ใต้ช่องยืนยันรหัสผ่านใหม่ (หลังสุดก่อนปุ่ม)
        // เพื่อไม่ให้ช่อง "รหัสผ่านใหม่" กับ "ยืนยันรหัสผ่านใหม่" ถูกแทรกแยกออกจากกัน
        const SizedBox(height: 12),
        _passwordStrengthBar(_newPasswordCtrl.text),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _isSavingPassword ? null : _changePassword,
            child: _isSavingPassword
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('เปลี่ยนรหัสผ่าน'),
          ),
        ),
      ],
    );

    // จอกว้าง: ข้อมูลทั่วไป/ความปลอดภัย วางเป็น 2 คอลัมน์ สูงเท่ากัน จำกัด maxWidth ไม่ให้โหรงเหรง
    // จอแคบ (< 900): ซ้อนกันแนวตั้ง
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1150),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [generalCard, const SizedBox(height: 20), passwordCard],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: generalCard),
                    const SizedBox(width: 20),
                    Expanded(child: passwordCard),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // แถบความแข็งแรงรหัสผ่าน 3 ระดับ (แดง/เหลือง/เขียว) — heuristic ง่ายๆ ช่วยลด validation error
  // ตอนกดบันทึกจริง (ยังบังคับแค่ >= 8 ตัวอักษรเหมือนเดิมใน _changePassword ไม่เปลี่ยน requirement)
  Widget _passwordStrengthBar(String pw) {
    int score = 0;
    if (pw.length >= 8) score++;
    if (RegExp(r'[0-9]').hasMatch(pw) && RegExp(r'[a-zA-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) score++;

    final Color color;
    final String label;
    if (pw.isEmpty) {
      color = AppColors.divider;
      label = 'อย่างน้อย 8 ตัวอักษร';
    } else if (score <= 1) {
      color = AppColors.error;
      label = 'ยังไม่ปลอดภัย — เพิ่มความยาวหรือผสมตัวเลข';
    } else if (score == 2) {
      color = const Color(0xFFF59E0B);
      label = 'พอใช้ได้ — เพิ่มตัวเลขหรือสัญลักษณ์ให้ปลอดภัยขึ้น';
    } else {
      color = AppColors.primaryGreen;
      label = 'รหัสผ่านความปลอดภัยดี';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(3, (i) {
            final filled = pw.isNotEmpty && i < score.clamp(1, 3);
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                height: 4,
                decoration: BoxDecoration(
                  color: filled ? color : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: pw.isEmpty ? AppColors.textMuted : color)),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

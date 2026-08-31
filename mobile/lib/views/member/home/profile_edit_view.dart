// หน้า: Edit Profile
// ทำหน้าที่: หน้าแก้ไขโปรไฟล์ส่วนตัว เปลี่ยนชื่อ อีเมล และรูปโปรไฟล์ของสมาชิก

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/user_model.dart';
import '../../../services/api_client.dart';
import '../../../services/member_service.dart';
import '../../../services/auth_service.dart';
import 'change_password_view.dart';

class ProfileEditView extends StatefulWidget {
  final User user;
  const ProfileEditView({super.key, required this.user});

  @override
  State<ProfileEditView> createState() => _ProfileEditViewState();
}

class _ProfileEditViewState extends State<ProfileEditView> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  bool _isLoading = false;
  File? _pickedImage;
  String? _profilePicUrl;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _emailController = TextEditingController(text: widget.user.email);
    if (widget.user.profilePic != null && widget.user.profilePic!.isNotEmpty) {
      _profilePicUrl = ApiClient.prefixPath(widget.user.profilePic!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 800);
    if (file == null || !mounted) return;
    setState(() => _pickedImage = File(file.path));
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text("เลือกรูปโปรไฟล์", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildSheetOption(icon: Icons.camera_alt_outlined, label: "ถ่ายรูป", onTap: () => _pickImage(ImageSource.camera)),
            _buildSheetOption(icon: Icons.photo_library_outlined, label: "เลือกจากคลังรูป", onTap: () => _pickImage(ImageSource.gallery)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ยกเลิก", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialAvatar() {
    return Center(
      child: Text(
        widget.user.fullName.isNotEmpty ? widget.user.fullName[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
      ),
    );
  }

  Widget _buildSheetOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.primaryGreen, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(child: AppBackButton()),
        ),
        title: const Text('แก้ไขโปรไฟล์',
            style: AppTextStyles.pageTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // --- ส่วนรูปภาพโปรไฟล์ ---
            Center(
              child: GestureDetector(
                onTap: _isLoading ? null : _showImagePickerSheet,
                child: Stack(
                  children: [
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryGreen.withValues(alpha: 0.18),
                        boxShadow: [BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 6))],
                      ),
                      child: ClipOval(
                        child: _pickedImage != null
                            ? Image.file(_pickedImage!, fit: BoxFit.cover)
                            : _profilePicUrl != null
                                ? cachedImage(_profilePicUrl!, fit: BoxFit.cover)
                                : _buildInitialAvatar(),
                      ),
                    ),
                    if (_isLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
                          child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))),
                        ),
                      ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 34, height: 34,
                        decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // --- ส่วนข้อมูลบัญชี ---
            _buildSectionHeader("ข้อมูลบัญชี"),
            const SizedBox(height: 16),
            _buildTextField(label: "ชื่อ-นามสกุล", controller: _nameController, icon: Icons.person_outline),
            const SizedBox(height: 20),
            _buildTextField(label: "อีเมล", controller: _emailController, icon: Icons.email_outlined, isReadOnly: true),
            
            const SizedBox(height: 32),

            // --- ส่วนความปลอดภัย ---
            _buildSectionHeader("ความปลอดภัย"),
            const SizedBox(height: 12),
            _buildMenuTile(
              icon: Icons.lock_outline_rounded,
              title: "เปลี่ยนรหัสผ่าน",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangePasswordView()));
              },
            ),

            const SizedBox(height: 40),

            // --- ปุ่มบันทึก ---
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text("บันทึกการเปลี่ยนแปลง", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            TextButton(
              onPressed: () => _showLogoutDialog(context),
              child: const Text("ออกจากระบบ", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 32),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);

    // อัปโหลดรูปก่อน ถ้ามีรูปที่เลือกไว้
    if (_pickedImage != null) {
      final imgResult = await MemberService.to.uploadProfileImage(_pickedImage!.path);
      if (!mounted) return;
      if (imgResult['success'] != true) {
        setState(() => _isLoading = false);
        showAppAlert(context, imgResult['message'] ?? 'อัปโหลดรูปไม่สำเร็จ', type: AppAlertType.error);
        return;
      }
      setState(() {
        _profilePicUrl = ApiClient.prefixPath(imgResult['profile_pic'] as String);
        _pickedImage = null;
      });
    }

    // แปลง gender string → int ตามที่ backend ต้องการ
    final gStr = widget.user.gender;
    final genderInt = (gStr == 'female' || gStr == '2') ? 2 : 1;

    // แปลง birth_date → YYYY-MM-DD
    final b = widget.user.birthDate;
    final birthDateStr =
        '${b.year.toString().padLeft(4, '0')}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';

    final result = await MemberService.to.updateProfile({
      'full_name': _nameController.text.trim(),
      'gender': genderInt,
      'birth_date': birthDateStr,
    });
    if (!mounted) return;
    setState(() => _isLoading = false);
    showAppAlert(context, result['message'] ?? '',
        type: result['success'] == true ? AppAlertType.success : AppAlertType.error);
    if (result['success'] == true) Navigator.pop(context);
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textBody, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildTextField({required String label, required TextEditingController controller, required IconData icon, bool isReadOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: isReadOnly,
          keyboardType: TextInputType.text,
          autocorrect: false,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: isReadOnly ? AppColors.textMuted : AppColors.primaryGreen, size: 22),
            filled: true,
            fillColor: isReadOnly ? AppColors.surfaceLight.withValues(alpha: 0.5) : AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.textDark, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
      ),
    );
  }

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
    if (confirm) AuthService.to.logout();
  }
}
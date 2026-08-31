// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage System Workout Plans (จัดการแผนการฝึกระบบ)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบแผนออกกำลังกายมาตรฐาน ที่ผู้ใช้เลือกใช้เป็นแผนเริ่มต้นได้

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'manage_system_plan_details_view.dart';
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/core/constants/app_text_styles.dart';
import 'package:myapp/core/widgets/app_back_button.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_fab.dart';
import 'package:myapp/core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';

// ─── เกรดความยาก: 1=Beginner, 2=Intermediate, 3=Advanced (ตรงกับ wpt_difficulty) ──
class _DifficultyOpt {
  final int value;
  final String label;
  const _DifficultyOpt(this.value, this.label);
}

const _difficultyOptions = [
  _DifficultyOpt(1, 'Beginner'),
  _DifficultyOpt(2, 'Intermediate'),
  _DifficultyOpt(3, 'Advanced'),
];

class _PlanFormState {
  int difficulty;
  File? selectedImage;
  Uint8List? selectedImageBytes;
  String? selectedImageName;
  _PlanFormState({this.difficulty = 1});
}

// ─── Workout plan icon mapping ───────────────────────────────────────────────
IconData _getPlanIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('อก') || n.contains('chest'))          return Icons.fitness_center_outlined;
  if (n.contains('ขา') || n.contains('leg'))            return Icons.directions_run_outlined;
  if (n.contains('หลัง') || n.contains('back'))         return Icons.accessibility_new_outlined;
  if (n.contains('ไหล่') || n.contains('shoulder'))     return Icons.sports_gymnastics_outlined;
  if (n.contains('แขน') || n.contains('arm'))           return Icons.sports_handball_outlined;
  if (n.contains('คาร์ดิโอ') || n.contains('cardio'))   return Icons.flash_on_outlined;
  if (n.contains('ผู้เริ่ม') || n.contains('beginner')) return Icons.star_outline_rounded;
  if (n.contains('ลด') || n.contains('fat'))            return Icons.local_fire_department_outlined;
  if (n.contains('เพิ่ม') || n.contains('muscle'))      return Icons.trending_up_rounded;
  return Icons.assignment_outlined;
}

const Color _green = Color(0xFF1A7A4E);

class ManageSystemWorkoutPlansView extends StatefulWidget {
  const ManageSystemWorkoutPlansView({super.key});

  @override
  State<ManageSystemWorkoutPlansView> createState() =>
      _ManageSystemWorkoutPlansViewState();
}

class _ManageSystemWorkoutPlansViewState
    extends State<ManageSystemWorkoutPlansView> {
  List<dynamic> workoutPlans = [];
  bool isLoading = true;

  String get apiUrl => '${ApiClient.serverUrl}/api/workouts/plans';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────
  Future<void> _fetchPlans() async {
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: _authHeaders);
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        if (mounted) setState(() { workoutPlans = list; isLoading = false; });
      } else {
        if (mounted) setState(() => isLoading = false);
        _showSnackBar('ดึงข้อมูลล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showSnackBar('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: $e');
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  // backend (workout_controller.go: CreateWorkoutPlan/UpdateWorkoutPlan) อ่านด้วย
  // c.PostForm/c.FormFile เท่านั้น — ต้องส่งเป็น multipart/form-data ห้ามส่ง JSON
  Future<void> _handleSave(
      Map<String, dynamic>? oldItem,
      String planName,
      int daysPerWeek,
      int difficulty,
      String description,
      File? imageFile,
      Uint8List? imageBytes,
      String? imageFileName) async {
    if (planName.trim().isEmpty) return;

    _showLoadingDialog();
    try {
      final isEdit = oldItem != null;
      final url = isEdit ? '$apiUrl/${oldItem['wpt_id']}' : apiUrl;
      final request = http.MultipartRequest(isEdit ? 'PUT' : 'POST', Uri.parse(url));
      request.headers.addAll(_authHeaders);
      request.fields['wpt_name'] = planName.trim();
      request.fields['wpt_days_per_week'] = daysPerWeek.toString();
      request.fields['wpt_difficulty'] = difficulty.toString();
      request.fields['wpt_description'] = description.trim();

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'wpt_image', imageBytes, filename: imageFileName));
        }
      } else if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('wpt_image', imageFile.path));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      Navigator.pop(context); // ปิด loading

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchPlans();
        Navigator.pop(context); // ปิด form dialog
        _showSnackBar(oldItem == null ? 'เพิ่มแผนสำเร็จ' : 'แก้ไขแผนสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ── Delete: ล็อกไว้ ลบไม่ได้ (แผนระบบ ป้องกันผลกระทบกับผู้ใช้ที่เลือกแผนนี้อยู่) ──
  Future<void> _handleDelete(int id, String title) async {
    await showAppNoticeDialog(
      context,
      icon: Icons.lock_outline_rounded,
      title: 'ไม่สามารถลบได้',
      content: 'แผน "$title" เป็นแผนมาตรฐานของระบบ\nไม่สามารถลบได้ เพื่อป้องกันผลกระทบ\nต่อผู้ใช้ที่เลือกแผนนี้อยู่',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // ── Form Dialog ───────────────────────────────────────────────────────────
  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['wpt_name'] ?? '');
    final descCtrl = TextEditingController(text: item?['wpt_description'] ?? '');
    final daysVal  = item?['wpt_days_per_week'];
    final daysCtrl = TextEditingController(
        text: (daysVal != null && daysVal != 0) ? daysVal.toString() : '');
    final diffVal = (item?['wpt_difficulty'] as num?)?.toInt() ?? 0;
    final fs = _PlanFormState(difficulty: diffVal >= 1 && diffVal <= 3 ? diffVal : 1);
    final picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickImage() async {
            final picked = await picker.pickImage(source: ImageSource.gallery);
            if (picked != null) {
              final bytes = await picked.readAsBytes();
              setModalState(() {
                fs.selectedImageBytes = bytes;
                fs.selectedImageName  = picked.name;
                if (!kIsWeb) fs.selectedImage = File(picked.path);
              });
            }
          }

          Widget imagePreview;
          if (fs.selectedImageBytes != null) {
            imagePreview = Image.memory(fs.selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['wpt_image'] ?? '').toString().isNotEmpty) {
            final url = ApiClient.prefixPath(item!['wpt_image']);
            imagePreview = url != null
                ? Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.add_a_photo, size: 32, color: Colors.grey))
                : const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 4, height: 20,
                        decoration: BoxDecoration(
                            color: _green,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item == null ? 'สร้างแผนการฝึกใหม่' : 'แก้ไขแผนการฝึก',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ]),
                  ),

                  // ── Body ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                        left: 20, right: 20, top: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Container(
                                height: 84, width: 84,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: imagePreview,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('ชื่อแผนการฝึก *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              hintText: 'เช่น แผนเพิ่มกล้ามเนื้อ, แผนลดน้ำหนัก',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.assignment_outlined,
                                  color: _green, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('คำอธิบาย',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: descCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'รายละเอียดแผนการฝึก (ไม่บังคับ)',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('วันฝึก/สัปดาห์',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: daysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 4',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.fitness_center_outlined,
                                  color: _green, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('ระดับความยาก',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: _difficultyOptions.map((opt) {
                              final selected = fs.difficulty == opt.value;
                              return ChoiceChip(
                                label: Text(opt.label),
                                selected: selected,
                                selectedColor: _green.withOpacity(0.15),
                                labelStyle: TextStyle(
                                    color: selected ? _green : Colors.black87,
                                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal),
                                onSelected: (_) => setModalState(() => fs.difficulty = opt.value),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                if (nameCtrl.text.trim().isEmpty) {
                                  _showSnackBar('กรุณากรอกชื่อแผนการฝึก');
                                  return;
                                }
                                final days = int.tryParse(daysCtrl.text) ?? 0;
                                _handleSave(item, nameCtrl.text.trim(), days, fs.difficulty,
                                    descCtrl.text, fs.selectedImage, fs.selectedImageBytes,
                                    fs.selectedImageName);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('บันทึกข้อมูล',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(child: AppBackButton()),
        ),
        title: const Column(
          children: [
            Text(
              'Workout Plans',
              style: AppTextStyles.pageTitle,
            ),
            Text(
              'จัดการแผนการออกกำลังกาย',
              style: AppTextStyles.pageSubtitle,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text(
                'ทั้งหมด ${workoutPlans.length} แผน',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ]),
          ),

          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : workoutPlans.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.assignment_outlined,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text('ยังไม่มีแผนการฝึก',
                              style: TextStyle(color: Colors.grey)),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _fetchPlans();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: workoutPlans.length,
                          itemBuilder: (context, i) {
                            final item = workoutPlans[i];
                            final name =
                                (item['wpt_name'] ?? '').toString();
                            final days =
                                (item['wpt_days_per_week'] ?? 0).toString();
                            final diff = item['wpt_difficulty'] ?? 1;
                            final diffText = diff == 1 ? 'Beginner' : diff == 2 ? 'Intermediate' : 'Advanced';
                            final imageUrl = ApiClient.prefixPath(item['wpt_image']);

                            return GestureDetector(
                              onTap: () => Get.to(() => ManageSystemPlanDetailsView(
                                planId: item['wpt_id'] as int,
                                planName: name.isNotEmpty ? name : 'รายละเอียดแผน',
                                daysPerWeek: (item['wpt_days_per_week'] as num?)?.toInt() ?? 3,
                              )),
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(children: [
                                    Container(
                                      width: 46, height: 46,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5E9),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: imageUrl != null
                                          ? Image.network(imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(
                                                  _getPlanIcon(name),
                                                  color: _green, size: 22))
                                          : Icon(_getPlanIcon(name),
                                              color: _green, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name.isNotEmpty ? name : 'ไม่มีชื่อแผน',
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.black87),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'ฝึก $days วัน/สัปดาห์ · $diffText',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showForm(item: Map<String, dynamic>.from(item)),
                                      child: Container(
                                        width: 34, height: 34,
                                        decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.edit_outlined,
                                            color: _green, size: 22),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    GestureDetector(
                                      onTap: () => _handleDelete(
                                          item['wpt_id'] as int, name),
                                      child: Container(
                                        width: 34, height: 34,
                                        decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.delete_outline,
                                            color: Colors.redAccent, size: 22),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      floatingActionButton: AppFab(onPressed: _showForm, color: _green),
    );
  }
}
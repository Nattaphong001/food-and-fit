// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_WORKOUT_PLANS : จัดการแผนการฝึกระบบ (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบแผนออกกำลังกายมาตรฐาน ที่ผู้ใช้เลือกใช้เป็นแผนเริ่มต้นได้
//                (ลบได้เมื่อไม่มีสมาชิกใช้งานแผนนี้อยู่ — backend เช็ค workout_schedules ก่อนอนุญาต)
// [PAGE_ROUTE] /admin > แผนการฝึก > รายการแผน
// [USES_FEATURES] WORKOUT_PLAN
//
// ย้ายจากแอปมือถือ (lib/views/admin/plan/manage_system_workout_plans_view.dart)
// Logic CRUD เหมือนเดิมทุกจุด (COPY) — คลิกแถวเพื่อดูรายละเอียดแผน (setState สลับไปแสดง
// ManageSystemPlanDetailsView ในสล็อตเดิม ไม่ push route ใหม่ — sidebar เห็นตลอด)
// layout: AppBar+FAB มือถือ -> AdminListHeader + DataTable

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'manage_system_plan_details_view.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/utils/plan_orphan_guard.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';

class _DifficultyOpt {
  final int value;
  final String label;
  const _DifficultyOpt(this.value, this.label);
}

const _difficultyOptions = [
  _DifficultyOpt(1, 'ง่าย'),
  _DifficultyOpt(2, 'ปานกลาง'),
  _DifficultyOpt(3, 'ยาก'),
];

// สี/label เดียวกับ _getDiffColor/_getDiffText ใน manage_weight_exercises_view.dart — ให้ badge
// ระดับความยากหน้าตาตรงกันทั้งระบบ (ที่นั่นเป็น private method คนละไฟล์ ก๊อปแพทเทิร์นมาแทนการ import)
Color _diffColor(int diff) => diff == 1 ? Colors.green : diff == 2 ? Colors.amber.shade700 : diff == 3 ? Colors.red : Colors.grey;
String _diffLabel(int diff) => diff == 1 ? 'ง่าย' : diff == 2 ? 'ปานกลาง' : diff == 3 ? 'ยาก' : 'ไม่ระบุ';

Widget _diffBadge(int diff) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: _diffColor(diff).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _diffColor(diff), width: 0.5)),
      child: Text(_diffLabel(diff), style: TextStyle(fontSize: 11, color: _diffColor(diff), fontWeight: FontWeight.w600)),
    );

class _PlanFormState {
  int difficulty;
  int daysPerWeek;
  File? selectedImage;
  Uint8List? selectedImageBytes;
  String? selectedImageName;
  _PlanFormState({this.difficulty = 1, this.daysPerWeek = 3});
}

IconData _getPlanIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('อก') || n.contains('chest')) return Icons.fitness_center_outlined;
  if (n.contains('ขา') || n.contains('leg')) return Icons.directions_run_outlined;
  if (n.contains('หลัง') || n.contains('back')) return Icons.accessibility_new_outlined;
  if (n.contains('ไหล่') || n.contains('shoulder')) return Icons.sports_gymnastics_outlined;
  if (n.contains('แขน') || n.contains('arm')) return Icons.sports_handball_outlined;
  if (n.contains('คาร์ดิโอ') || n.contains('cardio')) return Icons.flash_on_outlined;
  if (n.contains('ผู้เริ่ม') || n.contains('beginner')) return Icons.star_outline_rounded;
  if (n.contains('ลด') || n.contains('fat')) return Icons.local_fire_department_outlined;
  if (n.contains('เพิ่ม') || n.contains('muscle')) return Icons.trending_up_rounded;
  return Icons.assignment_outlined;
}


class ManageSystemWorkoutPlansView extends StatefulWidget {
  const ManageSystemWorkoutPlansView({super.key});

  @override
  State<ManageSystemWorkoutPlansView> createState() => _ManageSystemWorkoutPlansViewState();
}

class _ManageSystemWorkoutPlansViewState extends State<ManageSystemWorkoutPlansView> {
  List<dynamic> workoutPlans = [];
  bool isLoading = true;
  bool _hasError = false;
  String _search = '';
  int? _filterDifficulty;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ไม่ว่างเมื่อคลิกดูรายละเอียดแผน — สลับแสดงเนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell
  Map<String, dynamic>? _drillPlan;

  String get apiUrl => '${ApiClient.serverUrl}/api/workouts/plans';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  List<dynamic> get _filtered {
    var result = workoutPlans;
    if (_filterDifficulty != null) {
      result = result.where((p) => ((p['wpt_difficulty'] as num?)?.toInt() ?? 0) == _filterDifficulty).toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((p) => (p['wpt_name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    result = List.from(result)
      ..sort((a, b) => ((a['wpt_days_per_week'] as num?)?.toInt() ?? 0)
          .compareTo((b['wpt_days_per_week'] as num?)?.toInt() ?? 0));
    return result;
  }

  Future<void> _fetchPlans() async {
    setState(() => _hasError = false);
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
        if (mounted) {
          setState(() {
            workoutPlans = list;
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() { isLoading = false; _hasError = true; });
        _showSnackBar('ดึงข้อมูลล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() { isLoading = false; _hasError = true; });
      _showSnackBar('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: $e');
    }
  }

  Future<void> _handleSave(Map<String, dynamic>? oldItem, String planName, int daysPerWeek, int difficulty, String description, File? imageFile, Uint8List? imageBytes, String? imageFileName) async {
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
          request.files.add(http.MultipartFile.fromBytes('wpt_image', imageBytes, filename: imageFileName));
        }
      } else if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('wpt_image', imageFile.path));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchPlans();
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มแผนสำเร็จ' : 'แก้ไขแผนสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  String? _extractErrorMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
    } catch (_) {}
    return null;
  }

  Future<void> _handleDelete(int id, String title) async {
    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบแผน "$title" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );
    if (!confirm) return;

    _showLoadingDialog();
    try {
      final response = await http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders);
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200) {
        ApiClient.clearCache();
        await _fetchPlans();
        _showSnackBar('ลบ "$title" เรียบร้อย', type: AppAlertType.success);
      } else if (response.statusCode == 400) {
        await showAppNoticeDialog(
          context,
          icon: Icons.lock_outline_rounded,
          title: 'ไม่สามารถลบได้',
          content: _extractErrorMessage(response.body) ?? 'ไม่สามารถลบแผนนี้ได้',
        );
      } else {
        _showSnackBar(_extractErrorMessage(response.body) ?? 'ลบไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  void _showLoadingDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)));
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // --------------------------------------------
  // [FEATURE] WORKOUT_PLAN
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหาและตัวกรองระดับความยากกลับค่าเริ่มต้น — ใช้ร่วมกันทั้งปุ่ม
  //               "ล้างตัวกรอง" บน AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() => setState(() {
        _search = '';
        _filterDifficulty = null;
        _currentPage = 1;
      });

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['wpt_name'] ?? '');
    final descCtrl = TextEditingController(text: item?['wpt_description'] ?? '');
    final daysVal = (item?['wpt_days_per_week'] as num?)?.toInt() ?? 3;
    final diffVal = (item?['wpt_difficulty'] as num?)?.toInt() ?? 0;
    final fs = _PlanFormState(
      difficulty: diffVal >= 1 && diffVal <= 3 ? diffVal : 1,
      daysPerWeek: daysVal.clamp(1, 7),
    );
    final picker = ImagePicker();

    showAdminDialog(
      context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickImage() async {
            final picked = await picker.pickImage(source: ImageSource.gallery);
            if (picked != null) {
              final bytes = await picked.readAsBytes();
              setModalState(() {
                fs.selectedImageBytes = bytes;
                fs.selectedImageName = picked.name;
                if (!kIsWeb) fs.selectedImage = File(picked.path);
              });
            }
          }

          Widget imagePreview;
          if (fs.selectedImageBytes != null) {
            imagePreview = Image.memory(fs.selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['wpt_image'] ?? '').toString().isNotEmpty) {
            final url = ApiClient.prefixPath(item!['wpt_image']);
            imagePreview = url != null ? AdminNetworkImage(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.add_a_photo, size: 32, color: Colors.grey)) : const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: Container(
              width: 460,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                    decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100)), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                    child: Row(children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item == null ? 'เพิ่มแผนการฝึก' : 'แก้ไขแผนการฝึก', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))),
                      IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20), onPressed: () => Navigator.pop(dialogContext)),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Container(height: 84, width: 84, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: imagePreview),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Center(child: Text('แตะเพื่อเปลี่ยนรูปภาพ', style: TextStyle(color: Colors.grey, fontSize: 11))),
                          const SizedBox(height: 16),
                          const Text('ชื่อแผนการฝึก *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(controller: nameCtrl, decoration: InputDecoration(hintText: 'เช่น แผนเพิ่มกล้ามเนื้อ, แผนลดน้ำหนัก', prefixIcon: const Icon(Icons.assignment_outlined, color: AppColors.primaryGreen, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12))),
                          const SizedBox(height: 14),
                          const Text('คำอธิบาย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(controller: descCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'รายละเอียดแผนการฝึก (ไม่บังคับ)', contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12))),
                          const SizedBox(height: 14),
                          const Text('วันฝึก/สัปดาห์ *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                            child: Row(children: [
                              const Icon(Icons.fitness_center_outlined, color: AppColors.primaryGreen, size: 18),
                              const SizedBox(width: 10),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: AppColors.primaryGreen,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: fs.daysPerWeek > 1 ? () => setModalState(() => fs.daysPerWeek--) : null,
                              ),
                              SizedBox(width: 28, child: Text('${fs.daysPerWeek}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppColors.primaryGreen,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: fs.daysPerWeek < 7 ? () => setModalState(() => fs.daysPerWeek++) : null,
                              ),
                              const SizedBox(width: 10),
                              const Text('วัน / สัปดาห์ (1-7)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          const Text('ระดับความยาก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: _difficultyOptions.map((opt) {
                              final selected = fs.difficulty == opt.value;
                              final themeColor = _diffColor(opt.value);
                              return GestureDetector(
                                onTap: () => setModalState(() => fs.difficulty = opt.value),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected ? themeColor : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: themeColor),
                                  ),
                                  child: Text(opt.label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : themeColor)),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: () async {
                                final name = nameCtrl.text.trim();
                                final desc = descCtrl.text.trim();
                                if (name.length < 3 || name.length > 60) {
                                  _showSnackBar('ชื่อแผนต้องมีความยาว 3-60 ตัวอักษร');
                                  return;
                                }
                                if (desc.isNotEmpty && desc.length < 10) {
                                  _showSnackBar('คำอธิบายต้องมีความยาวอย่างน้อย 10 ตัวอักษร (หรือเว้นว่างไว้)');
                                  return;
                                }
                                if (item != null) {
                                  final oldDays = (item['wpt_days_per_week'] as num?)?.toInt() ?? fs.daysPerWeek;
                                  if (fs.daysPerWeek < oldDays) {
                                    final canProceed = await resolveOrphanPlanDaysBeforeSave(
                                      context,
                                      planId: item['wpt_id'] as int,
                                      newDays: fs.daysPerWeek,
                                      oldDays: oldDays,
                                      authHeaders: _authHeaders,
                                    );
                                    if (!canProceed) return;
                                  }
                                }
                                _handleSave(item, name, fs.daysPerWeek, fs.difficulty, desc, fs.selectedImage, fs.selectedImageBytes, fs.selectedImageName);
                              },
                              child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
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

  // การ์ดครอบขนาดใหญ่ขึ้น จัดแถวคู่ 2 คอลัมน์ (บรีฟรอบ 3 ข้อ 6) แทนตารางแถวเดียวเดิม —
  // รูปใหญ่ขึ้นให้ใกล้เคียงสไตล์การ์ดแผนฝั่ง User เพราะแอดมินต้องดูแผนที่ผู้ใช้จะเห็นจริง
  Widget _buildPlanCard(Map<String, dynamic> item) {
    final name = (item['wpt_name'] ?? '').toString();
    final days = (item['wpt_days_per_week'] ?? 0).toString();
    final diff = ((item['wpt_difficulty'] as num?) ?? 1).toInt();
    final desc = (item['wpt_description'] ?? '').toString();
    final imageUrl = ApiClient.prefixPath(item['wpt_image']);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _drillPlan = item),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 84, height: 84,
                  color: AppColors.calorieBadgeBg,
                  child: imageUrl != null
                      ? AdminNetworkImage(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(_getPlanIcon(name), color: AppColors.primaryGreen, size: 30))
                      : Icon(_getPlanIcon(name), color: AppColors.primaryGreen, size: 30),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isNotEmpty ? name : 'ไม่มีชื่อแผน', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blueGrey, width: 0.5)),
                        child: Text('$days วัน/สัปดาห์', style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                      ),
                      _diffBadge(diff),
                    ]),
                    if (desc.isNotEmpty) ...[const SizedBox(height: 8), Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.grey))],
                  ],
                ),
              ),
              // ปุ่มแก้ไข/ลบแยกเป็น icon button ตรงๆ ไม่ซ่อนหลังเมนู ⋮ — ให้ตรงกับ pattern
              // แถวปุ่มใน manage_weight_exercises_view.dart (actionsBuilder) แทนที่จะกดเปิดเมนูก่อน
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'แก้ไข',
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 18),
                  onPressed: () {
                    Tooltip.dismissAllToolTips();
                    _showForm(item: Map<String, dynamic>.from(item));
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  tooltip: 'ลบ',
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  onPressed: () {
                    Tooltip.dismissAllToolTips();
                    _handleDelete(item['wpt_id'] as int, name);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_drillPlan != null) {
      final item = _drillPlan!;
      final name = (item['wpt_name'] ?? '').toString();
      final desc = (item['wpt_description'] ?? '').toString();
      final diff = ((item['wpt_difficulty'] as num?) ?? 1).toInt();
      return ManageSystemPlanDetailsView(
        planId: item['wpt_id'] as int,
        planName: name.isNotEmpty ? name : 'รายละเอียดแผน',
        daysPerWeek: (item['wpt_days_per_week'] as num?)?.toInt() ?? 3,
        planImage: item['wpt_image']?.toString(),
        planDifficulty: diff,
        planDescription: desc,
        onBack: () {
          setState(() => _drillPlan = null);
          _fetchPlans();
        },
      );
    }
    final allRows = _filtered;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? ((_search.isNotEmpty || _filterDifficulty != null) ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['แผนการฝึก', 'รายการแผนฝึก'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มแผนการฝึก',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อแผน...',
          onSearchChanged: (v) => setState(() {
            _search = v;
            _currentPage = 1;
          }),
          // pill chip กรองระดับความยาก ใช้สีตามความหมายจริง (เขียว/เหลือง/แดง) ตัดสีมาจาก
          // _diffColor ตัวเดียวกับ badge บนการ์ด — ตรงกับ pattern chip กรองความยากที่หน้า
          // ท่าฝึกเวท (_diffFilters) เดิมทำ all-green ล้วนซึ่งไม่ตรงกับ pattern จริงในระบบ
          trailing: [
            for (final diff in const [null, 1, 2, 3])
              GestureDetector(
                onTap: () => setState(() {
                  _filterDifficulty = diff;
                  _currentPage = 1;
                }),
                child: Builder(builder: (context) {
                  final selected = _filterDifficulty == diff;
                  final themeColor = diff == null ? AppColors.primaryGreen : _diffColor(diff);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? (diff == null ? themeColor.withValues(alpha: 0.12) : themeColor) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: themeColor),
                    ),
                    child: Text(
                      diff == null ? 'ทั้งหมด' : _diffLabel(diff),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected && diff != null ? Colors.white : themeColor),
                    ),
                  );
                }),
              ),
          ],
          resultCount: allRows.length,
          showClearButton: _search.isNotEmpty || _filterDifficulty != null,
          onClearFilters: _clearFilters,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text('คลิกที่การ์ดเพื่อดู/จัดการรายละเอียดแผน (ท่าฝึกแต่ละวัน)', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.cards,
                  onAdd: () => _showForm(),
                  onRetry: _fetchPlans,
                  onClearFilter: _clearFilters,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth > 720 ? 2 : 1;
                    final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: rows.map((item) => SizedBox(width: width, child: _buildPlanCard(item))).toList(),
                    );
                  }),
                ),
        ),
        if (stateOverride == null)
          AdminPaginationBar(
            totalItems: allRows.length,
            pageSize: _pageSize,
            currentPage: safePage,
            onPageSizeChanged: (v) => setState(() {
              _pageSize = v;
              _currentPage = 1;
            }),
            onPageChanged: (v) => setState(() => _currentPage = v),
          ),
      ],
    );
  }
}

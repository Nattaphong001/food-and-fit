// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_PLAN_DETAILS : จัดการรายละเอียดแผนฝึกระบบ (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบท่าฝึกในแต่ละแผนมาตรฐาน กำหนดว่าวันไหนควรฝึกท่าอะไรบ้าง
// [PAGE_ROUTE] /admin > แผนการฝึก > รายการแผน > (คลิกแผน) — drill-down ฝังในสล็อตเดิมของ
//              sidebar shell (setState สลับ widget ไม่ push route ใหม่ — sidebar เห็นตลอด)
// [USES_FEATURES] WORKOUT_PLAN
//
// ย้ายจากแอปมือถือ (lib/views/admin/plan/manage_system_plan_details_view.dart)
// Logic CRUD เหมือนเดิมทุกจุด (COPY) — มี Scaffold ของตัวเอง (ให้ FAB วางตำแหน่งได้) แต่ไม่ใช่
// Scaffold ระดับ route (ไม่ได้ push ทับ shell) ปุ่ม back เรียก widget.onBack ที่พ่อแม่ส่งมา
// เปลี่ยนแค่ bottom sheet ฟอร์ม -> Dialog กึ่งกลางจอ (เข้ากับรูปแบบ desktop) และจำกัดความกว้าง
// เนื้อหาให้ไม่ยืดเต็มจอกว้างเกินไป

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/layout_breakpoints.dart';
import '../../../core/utils/plan_day_labels.dart';
import '../../../core/utils/plan_orphan_guard.dart';
import '../../../core/widgets/admin_breadcrumb.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_fab.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/top_flash.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'dart:io';
import '../../../services/api_client.dart';

// สี/label ระดับความยากเดียวกับ manage_system_workout_plans_view.dart / manage_weight_exercises_view.dart
// (private ต่อไฟล์ตามภาษา Dart — ก๊อปแพทเทิร์นมาแทนการ import ข้ามไฟล์)
Color _diffColor(int diff) => diff == 1 ? Colors.green : diff == 2 ? Colors.amber.shade700 : diff == 3 ? Colors.red : Colors.grey;
String _diffLabel(int diff) => diff == 1 ? 'ง่าย' : diff == 2 ? 'ปานกลาง' : diff == 3 ? 'ยาก' : 'ไม่ระบุ';

class ManageSystemPlanDetailsView extends StatefulWidget {
  final int planId;
  final String planName;
  final int daysPerWeek;
  final String? planImage;
  final int planDifficulty;
  final String? planDescription;
  // เรียกตอนกดปุ่ม back (แทนที่ Navigator.pop เดิม เพราะตอนนี้ฝังเนื้อหาแทนที่ในสล็อตเดิม
  // ของ sidebar shell ไม่ใช่ route ที่ pop ได้แล้ว)
  final VoidCallback? onBack;

  const ManageSystemPlanDetailsView({
    super.key,
    required this.planId,
    required this.planName,
    required this.daysPerWeek,
    this.planImage,
    this.planDifficulty = 1,
    this.planDescription,
    this.onBack,
  });

  @override
  State<ManageSystemPlanDetailsView> createState() => _ManageSystemPlanDetailsViewState();
}

class _ManageSystemPlanDetailsViewState extends State<ManageSystemPlanDetailsView> with SingleTickerProviderStateMixin {
  List<dynamic> planDetails = [];
  List<dynamic> weightExercises = [];
  bool isLoading = true;
  late TabController _tabController;

  // สำเนา mutable ของข้อมูลแผน — แก้ได้จากปุ่ม "แก้ไขข้อมูลแผน" ในหน้านี้ตรงๆ ไม่ต้องกลับไปหน้ารายการ
  // (widget.* เป็นค่าตอน push มาตอนแรกเท่านั้น อัปเดตไม่ได้ ต้องมีสำเนาที่ setState ได้)
  late String _planName;
  late int _planDaysPerWeek;
  String? _planImage;
  late int _planDifficulty;
  String? _planDescription;

  String get baseUrl => '${ApiClient.serverUrl}/api';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _planName = widget.planName;
    _planDaysPerWeek = widget.daysPerWeek;
    _planImage = widget.planImage;
    _planDifficulty = widget.planDifficulty;
    _planDescription = widget.planDescription;
    _tabController = TabController(length: _planDaysPerWeek, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ปุ่มขึ้น/ลงแทน drag-reorder — สลับ ptd_order ระหว่าง 2 แถวที่ติดกันในวันเดียวกัน แล้วเขียนกลับผ่าน
  // endpoint เดิม PUT /workouts/details/:id (generic partial update รับ {"ptd_order": n} ได้อยู่แล้ว
  // ไม่ต้องแก้ backend) — ไม่แตะ GetPlanDetails ฝั่งอ่านเพราะ endpoint นี้แอปมือถือเรียกใช้ร่วมด้วย
  // (กฎเหล็กข้อ 2) จึงเรียงตาม ptd_order ที่ฝั่ง client เท่านั้น ดู _dayItems()
  Future<void> _reorder(List<Map<String, dynamic>> dayItems, int index, int delta) async {
    final otherIndex = index + delta;
    if (otherIndex < 0 || otherIndex >= dayItems.length) return;
    final a = dayItems[index];
    final b = dayItems[otherIndex];
    final aOrder = (a['ptd_order'] as num?)?.toInt() ?? (index + 1);
    final bOrder = (b['ptd_order'] as num?)?.toInt() ?? (otherIndex + 1);

    setState(() {
      a['ptd_order'] = bOrder;
      b['ptd_order'] = aOrder;
    });

    try {
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      await Future.wait([
        http.put(Uri.parse('$baseUrl/workouts/details/${a['ptd_id']}'), headers: headers, body: jsonEncode({'ptd_order': bOrder})),
        http.put(Uri.parse('$baseUrl/workouts/details/${b['ptd_id']}'), headers: headers, body: jsonEncode({'ptd_order': aOrder})),
      ]);
      ApiClient.clearCache();
    } catch (e) {
      if (mounted) _showSnackBar('เรียงลำดับไม่สำเร็จ: $e');
      await _fetchPlanDetails(); // sync กลับให้ตรงกับ server จริง
    }
  }

  // รายการท่าของวันที่ระบุ เรียงตาม ptd_order (fallback ptd_id กันลำดับสลับไปมาตอนค่า ptd_order เท่ากัน
  // เช่นรายการเก่าที่ยังไม่เคยเรียงมาก่อน ค่า default ทุกแถวคือ 1)
  List<Map<String, dynamic>> _dayItems(int dayNumber) {
    final list = planDetails
        .cast<Map<String, dynamic>>()
        .where((item) => ((item['ptd_day_number'] as num?)?.toInt() ?? 0) == dayNumber)
        .toList();
    list.sort((a, b) {
      final ao = (a['ptd_order'] as num?)?.toInt() ?? 1;
      final bo = (b['ptd_order'] as num?)?.toInt() ?? 1;
      if (ao != bo) return ao.compareTo(bo);
      return ((a['ptd_id'] as num?)?.toInt() ?? 0).compareTo((b['ptd_id'] as num?)?.toInt() ?? 0);
    });
    return list;
  }

  // ท่าที่ถูกเพิ่มลงวันนี้ไปแล้ว — ใช้กันไม่ให้เลือกซ้ำตอนเพิ่ม/แก้ท่าฝึกในวันเดียวกัน
  // excludePtdId กันตัวเองหลุดตอนแก้ไขรายการที่มีอยู่แล้ว (ไม่งั้นท่าตัวเองจะหายไปจากรายการตอนแก้)
  Set<int> _existingWetIdsForDay(int dayNumber, {int? excludePtdId}) {
    return _dayItems(dayNumber)
        .where((d) => excludePtdId == null || (d['ptd_id'] as num?)?.toInt() != excludePtdId)
        .map((d) => (d['wet_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_fetchPlanDetails(), _fetchWeightExercises()]);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchPlanDetails() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/workouts/details?plan_id=${widget.planId}'), headers: _authHeaders);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final list = data is Map ? (data['data'] ?? data['items'] ?? data['result'] ?? []) as List : data as List;
        if (mounted) setState(() => planDetails = list);
      }
    } catch (e) {
      debugPrint("Error fetching details: $e");
    }
  }

  Future<void> _fetchWeightExercises() async {
    try {
      final response = await _api.get('/exercises/weights');
      if (response.statusCode == 200) {
        final data = response.data;
        final list = data is Map ? (data['data'] ?? data['items'] ?? data['result'] ?? []) as List : data as List;
        if (mounted) setState(() => weightExercises = list);
      }
    } catch (e) {
      debugPrint("Error fetching exercises: $e");
    }
  }

  // label วันฝึกใช้ helper กลาง (core/utils/plan_day_labels.dart) ร่วมกับหน้ารายการแผน —
  // ต้องตรงกับ planDayWeekday ฝั่ง Go (workout_controller.go) เสมอ กันหลุด sync กัน
  String _dayLabel(int dayNumber) => planDayLabel(dayNumber, _planDaysPerWeek);

  String _getExerciseName(Map<String, dynamic> item) {
    final preloaded = item['weight_exercise'];
    if (preloaded is Map && preloaded['wet_name'] != null) return preloaded['wet_name'];
    final wetId = item['wet_id'];
    if (wetId == null) return 'ไม่ระบุ';
    final ex = weightExercises.firstWhere((e) => e['wet_id'] == wetId, orElse: () => null);
    return ex?['wet_name'] ?? 'ท่า #$wetId';
  }

  String? _getExerciseImage(Map<String, dynamic> item) {
    final preloaded = item['weight_exercise'];
    if (preloaded is Map && preloaded['wet_image'] != null) return ApiClient.prefixPath(preloaded['wet_image']);
    final wetId = item['wet_id'];
    if (wetId == null) return null;
    final ex = weightExercises.firstWhere((e) => e['wet_id'] == wetId, orElse: () => null);
    return ApiClient.prefixPath(ex?['wet_image']);
  }

  void _showLoadingDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)));
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  Future<void> _handleSave(Map<String, dynamic>? oldItem, Map<String, dynamic> formData) async {
    Navigator.pop(context); // ปิด dialog ฟอร์ม

    _showLoadingDialog();
    try {
      http.Response response;
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      final body = jsonEncode(formData);

      if (oldItem == null) {
        response = await http.post(Uri.parse('$baseUrl/workouts/details'), headers: headers, body: body);
      } else {
        response = await http.put(Uri.parse('$baseUrl/workouts/details/${oldItem['ptd_id']}'), headers: headers, body: body);
      }

      if (!mounted) return;
      Navigator.pop(context); // ปิด loading

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchPlanDetails();
        _showSnackBar(oldItem == null ? 'เพิ่มท่าฝึกสำเร็จ' : 'แก้ไขท่าฝึกสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('ล้มเหลว: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _handleDelete(int detId, String name) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ออกจากแผนหรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (!confirm) return;

    _showLoadingDialog();
    try {
      final response = await http.delete(Uri.parse('$baseUrl/workouts/details/$detId'), headers: _authHeaders);
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200) {
        await _fetchPlanDetails();
        showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
      } else {
        _showSnackBar('ลบล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // แก้ไขข้อมูลแผน (ชื่อ/รูป/คำอธิบาย/วัน/ระดับ) เปิด dialog ในหน้านี้ตรงๆ แทนที่จะ pop กลับไป
  // หน้ารายการเหมือนก่อนหน้านี้ — ฟอร์มหน้าตาเดียวกับหน้ารายการ (ก๊อปแพทเทิร์นมาเพราะเป็น dialog
  // คนละบริบท) แต่ตัวป้องกันข้อมูลกำพร้าใช้ resolveOrphanPlanDaysBeforeSave ตัวเดียวกันจริงๆ
  // (core/utils/plan_orphan_guard.dart) กันโค้ดตรงนี้หลุด sync กับหน้ารายการ
  Future<void> _showEditPlanForm() async {
    // ไม่มี endpoint ดึงทีละแผน ต้องดึงทั้งลิสต์มาหา wpt_id ที่ตรงกัน (เหมือนหน้ารายการ) เอาค่า
    // ล่าสุดจริงจาก server แทนใช้สำเนาในเครื่อง (เผื่อมีคนอื่นแก้ไว้ก่อนหน้านี้)
    Map<String, dynamic>? planItem;
    try {
      final res = await http.get(Uri.parse('$baseUrl/workouts/plans'), headers: _authHeaders);
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        final list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List : decoded as List;
        planItem = list.cast<Map<String, dynamic>>().firstWhere((p) => (p['wpt_id'] as num?)?.toInt() == widget.planId, orElse: () => {});
        if (planItem.isEmpty) planItem = null;
      }
    } catch (_) {}

    if (!mounted) return;
    if (planItem == null) {
      _showSnackBar('โหลดข้อมูลแผนไม่สำเร็จ ลองใหม่อีกครั้ง');
      return;
    }
    final currentPlan = planItem;

    final nameCtrl = TextEditingController(text: currentPlan['wpt_name'] ?? _planName);
    final descCtrl = TextEditingController(text: currentPlan['wpt_description'] ?? _planDescription ?? '');
    final oldDays = (currentPlan['wpt_days_per_week'] as num?)?.toInt() ?? _planDaysPerWeek;
    int selectedDifficulty = ((currentPlan['wpt_difficulty'] as num?)?.toInt() ?? _planDifficulty).clamp(1, 3);
    int selectedDays = oldDays.clamp(1, 7);
    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
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
                selectedImageBytes = bytes;
                selectedImageName = picked.name;
                if (!kIsWeb) selectedImage = File(picked.path);
              });
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview = Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if ((currentPlan['wpt_image'] ?? '').toString().isNotEmpty) {
            final url = ApiClient.prefixPath(currentPlan['wpt_image']);
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
                      const Expanded(child: Text('แก้ไขแผนการฝึก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))),
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
                                onPressed: selectedDays > 1 ? () => setModalState(() => selectedDays--) : null,
                              ),
                              SizedBox(width: 28, child: Text('$selectedDays', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppColors.primaryGreen,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: selectedDays < 7 ? () => setModalState(() => selectedDays++) : null,
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
                            children: [(1, 'ง่าย'), (2, 'ปานกลาง'), (3, 'ยาก')].map((opt) {
                              final selected = selectedDifficulty == opt.$1;
                              final themeColor = _diffColor(opt.$1);
                              return GestureDetector(
                                onTap: () => setModalState(() => selectedDifficulty = opt.$1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected ? themeColor : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: themeColor),
                                  ),
                                  child: Text(opt.$2, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : themeColor)),
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
                                if (selectedDays < oldDays) {
                                  final canProceed = await resolveOrphanPlanDaysBeforeSave(
                                    context,
                                    planId: widget.planId,
                                    newDays: selectedDays,
                                    oldDays: oldDays,
                                    authHeaders: _authHeaders,
                                  );
                                  if (!canProceed) return;
                                }
                                if (!ctx.mounted) return;
                                Navigator.pop(dialogContext);
                                await _savePlanInfo(name, selectedDays, selectedDifficulty, desc, selectedImage, selectedImageBytes, selectedImageName);
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

  Future<void> _savePlanInfo(String name, int daysPerWeek, int difficulty, String description, File? imageFile, Uint8List? imageBytes, String? imageFileName) async {
    _showLoadingDialog();
    try {
      final request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/workouts/plans/${widget.planId}'));
      request.headers.addAll(_authHeaders);
      request.fields['wpt_name'] = name;
      request.fields['wpt_days_per_week'] = daysPerWeek.toString();
      request.fields['wpt_difficulty'] = difficulty.toString();
      request.fields['wpt_description'] = description;

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
      Navigator.pop(context); // ปิด loading

      if (response.statusCode == 200 || response.statusCode == 201) {
        final daysChanged = daysPerWeek != _planDaysPerWeek;
        setState(() {
          _planName = name;
          _planDescription = description;
          _planDifficulty = difficulty;
          if (daysChanged) {
            _planDaysPerWeek = daysPerWeek;
            _tabController.dispose();
            _tabController = TabController(length: daysPerWeek, vsync: this);
          }
        });
        // รูป/path อัปเดตจริงจาก server เท่านั้น (multipart อัปโหลดไฟล์ใหม่ได้ path ใหม่มา) ดึงแผนล่าสุดมาเช็ค
        _refreshPlanImage();
        if (daysChanged) await _fetchPlanDetails(); // เผื่อตัวป้องกันกำพร้าลบท่าที่เกินไปแล้ว
        _showSnackBar('แก้ไขแผนสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _refreshPlanImage() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/workouts/plans'), headers: _authHeaders);
      if (res.statusCode != 200) return;
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      final list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List : decoded as List;
      final match = list.cast<Map<String, dynamic>>().firstWhere((p) => (p['wpt_id'] as num?)?.toInt() == widget.planId, orElse: () => {});
      if (match.isNotEmpty && mounted) setState(() => _planImage = match['wpt_image']?.toString());
    } catch (_) {}
  }

  // NOT A BUG (สืบสวนแล้ว 2026-08-24, TC028): ถ้าเจอ ptd_sets/ptd_reps/ptd_rest_seconds
  // เพี้ยนเป็นค่า default (3/'12'/90) ทั้งที่กรอกค่าอื่นในฟอร์มนี้ ไม่ใช่บั๊กของแอป — repro แล้วว่า
  // เกิดจาก race condition ของ Flutter Web เอง (DOM input ปรากฏแล้วแต่ text-input listener
  // ยังผูกไม่เสร็จตอน dialog เพิ่ง mount) ถ้า set ค่าเข้าช่องแบบ programmatic เร็วเกินไป (เช่น
  // Playwright .fill() ของ TestSprite) ค่าจะไม่ sync เข้า controller แล้วตกไปที่ default ตอน
  // _handleSave — เกิดกับฟิลด์ไหนก็ได้ในฟอร์มนี้แบบสุ่ม ไม่เจาะจง reps คนพิมพ์คีย์บอร์ดจริงไม่เจอ
  // เพราะมี delay ระหว่างตัวอักษรตามธรรมชาติอยู่แล้ว — ถ้าเจอใน test report ให้บอก TestSprite
  // ผ่าน additionalInstruction ให้รอ ~800ms-1s หลัง dialog เปิดก่อนกรอก แทนการแก้โค้ดตรงนี้
  void _showForm({Map<String, dynamic>? item}) {
    final editingPtdId = (item?['ptd_id'] as num?)?.toInt();
    // เพิ่มใหม่ (item == null): เอาวันของ tab ที่กำลังเปิดอยู่เป็นค่าเริ่มต้น สะดวกกว่าเดาว่าเริ่มที่วันจันทร์เสมอ
    // clamp กันข้อมูลเก่าที่ ptd_day_number เกิน daysPerWeek ปัจจุบัน (เช่นแผนเคยลดจำนวนวันภายหลัง)
    // ไม่งั้น DropdownButtonFormField (ตัวเลือกตอนนี้ตัดตาม daysPerWeek แล้ว) จะ assert พังตอนเปิดฟอร์ม
    int selectedDay = ((item?['ptd_day_number'] as num?)?.toInt() ?? (_tabController.index + 1)).clamp(1, _planDaysPerWeek);

    // เพิ่มใหม่: ห้ามตั้งค่าเริ่มต้นเป็นท่าที่มีอยู่ในวันนี้แล้ว (จะโดนกรองออกจากรายการทันทีที่เปิดฟอร์ม)
    int? selectedWetId = item?['wet_id'] as int?;
    if (selectedWetId == null && weightExercises.isNotEmpty) {
      final excludedAtStart = _existingWetIdsForDay(selectedDay, excludePtdId: editingPtdId);
      final firstAvailable = weightExercises.cast<Map<String, dynamic>>().firstWhere(
            (ex) => !excludedAtStart.contains((ex['wet_id'] as num?)?.toInt()),
            orElse: () => weightExercises.first as Map<String, dynamic>,
          );
      selectedWetId = firstAvailable['wet_id'] as int?;
    }

    final setsCtrl = TextEditingController(text: item == null ? '' : (item['ptd_sets'] ?? '').toString());
    final repsCtrl = TextEditingController(text: item == null ? '' : (item['ptd_reps'] ?? '').toString());
    final restCtrl = TextEditingController(text: item == null ? '' : (item['ptd_rest_seconds'] ?? '').toString());

    // ค้นหา/กรองท่าฝึก — เดิมเป็น dropdown รายชื่อล้วนไม่มีทางค้นหา หาท่ายากเวลามีท่าเยอะ
    String exerciseSearchQuery = '';
    int? exerciseMuscleFilter;
    final muscleGroups = <int, String>{};
    for (final ex in weightExercises) {
      final mg = ex['muscle_group'];
      if (mg is Map && mg['mug_id'] != null) {
        muscleGroups[mg['mug_id'] as int] = mg['mug_name']?.toString() ?? '';
      }
    }
    // ท่าที่มีอยู่ในวันที่กำลังเลือกอยู่แล้วจะไม่ถูกแสดง กันเพิ่มซ้ำท่าเดิมในวันเดียวกัน
    // (ยกเว้นตัวเองตอนแก้ไขรายการเดิม ดู editingPtdId)
    List<dynamic> filteredExercises() {
      final excluded = _existingWetIdsForDay(selectedDay, excludePtdId: editingPtdId);
      return weightExercises.where((ex) {
        final wetId = (ex['wet_id'] as num?)?.toInt();
        if (wetId != null && excluded.contains(wetId)) return false;
        if (exerciseMuscleFilter != null) {
          final mg = ex['muscle_group'];
          final mgId = mg is Map ? mg['mug_id'] : null;
          if (mgId != exerciseMuscleFilter) return false;
        }
        if (exerciseSearchQuery.isNotEmpty) {
          final name = (ex['wet_name'] ?? '').toString().toLowerCase();
          if (!name.contains(exerciseSearchQuery.toLowerCase())) return false;
        }
        return true;
      }).toList();
    }

    showAdminDialog(
      context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                  decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100)), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                  child: Row(children: [
                    Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item == null ? 'เพิ่มท่าฝึก' : 'แก้ไขท่าฝึก', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))),
                    IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('วันที่ในแผน', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<int>(
                          initialValue: selectedDay,
                          isExpanded: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.primaryGreen, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                          items: [for (var d = 1; d <= _planDaysPerWeek; d++) DropdownMenuItem(value: d, child: Text(_dayLabel(d)))],
                          onChanged: (v) => setModalState(() {
                            selectedDay = v!;
                            // ย้ายวันแล้วท่าที่เลือกค้างไว้ดันมีอยู่ในวันใหม่แล้ว (จะโดนกรองออกจากรายการ) — ต้องล้างทิ้งให้เลือกใหม่
                            final excluded = _existingWetIdsForDay(selectedDay, excludePtdId: editingPtdId);
                            if (selectedWetId != null && excluded.contains(selectedWetId)) {
                              selectedWetId = null;
                            }
                          }),
                        ),
                        const SizedBox(height: 14),
                        const Text('ท่าฝึก *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        Text('ท่าที่มีอยู่ในวันนี้แล้วจะไม่แสดงในรายการ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'ค้นหาชื่อท่าฝึก...',
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, color: AppColors.primaryGreen, size: 18),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              ),
                              onChanged: (v) => setModalState(() => exerciseSearchQuery = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int?>(
                              initialValue: exerciseMuscleFilter,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('ทุกกลุ่ม', overflow: TextOverflow.ellipsis)),
                                ...muscleGroups.entries.map((e) => DropdownMenuItem<int?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))),
                              ],
                              onChanged: (v) => setModalState(() => exerciseMuscleFilter = v),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
                          child: Builder(builder: (context) {
                            final options = filteredExercises();
                            if (options.isEmpty) {
                              // แยกข้อความ 2 กรณี — ค้นหา/กรองแล้วไม่เจอ VS ท่าที่มีถูกใช้ในวันนี้หมดแล้ว
                              // (เดิมใช้ข้อความเดียวปนกัน ทำให้ไม่รู้ว่าควรลองค้นหาใหม่ หรือย้ายไปวันอื่น)
                              final hasActiveFilter = exerciseSearchQuery.isNotEmpty || exerciseMuscleFilter != null;
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  hasActiveFilter ? 'ไม่พบท่าฝึกที่ตรงกับคำค้นหา' : 'ท่าฝึกทั้งหมดถูกใช้ในวันนี้แล้ว ลองเลือกวันอื่นหรือเพิ่มท่าฝึกใหม่',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                ),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final ex = options[i];
                                final id = ex['wet_id'] as int;
                                final selected = id == selectedWetId;
                                final mg = ex['muscle_group'];
                                final mgName = mg is Map ? (mg['mug_name']?.toString() ?? '') : '';
                                return InkWell(
                                  onTap: () => setModalState(() => selectedWetId = id),
                                  child: Container(
                                    color: selected ? AppColors.primaryGreen.withValues(alpha: 0.08) : null,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(children: [
                                      Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: selected ? AppColors.primaryGreen : AppColors.textMuted),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(ex['wet_name'] ?? 'ไม่มีชื่อ', style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: Colors.black87)),
                                          if (mgName.isNotEmpty) Text(mgName, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('เซต', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: setsCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(hintText: 'เช่น 3', contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('ครั้ง', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: repsCtrl,
                                keyboardType: TextInputType.number,
                                // อนุญาตเลข + "-" (รองรับช่วงเช่น "8-12" ตาม ptdRepsPattern ฝั่ง backend)
                                // มี formatter เสมอ (ไม่ปล่อยว่าง) เพื่อให้ sync ค่าจาก DOM เข้า
                                // controller เสถียรเหมือนช่องเซต/พัก — ไม่งั้นค่าที่ set แบบ
                                // programmatic (เช่น autofill) อาจ sync ไม่ครบ/เพี้ยน
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
                                decoration: InputDecoration(hintText: 'เช่น 12', contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                              ),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        const Text('เวลาพักระหว่างเซต (วินาที)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: restCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: 'เช่น 90',
                            prefixIcon: const Icon(Icons.timer_outlined, color: AppColors.primaryGreen, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity, height: 48,
                          child: ElevatedButton(
                            onPressed: () {
                              if (selectedWetId == null) {
                                _showSnackBar('กรุณาเลือกท่าฝึก');
                                return;
                              }
                              _handleSave(item, {
                                "wpt_id": widget.planId,
                                "ptd_day_number": selectedDay,
                                "wet_id": selectedWetId,
                                "ptd_sets": int.tryParse(setsCtrl.text) ?? 3,
                                "ptd_reps": repsCtrl.text.trim().isEmpty ? '12' : repsCtrl.text.trim(),
                                "ptd_rest_seconds": int.tryParse(restCtrl.text) ?? 90,
                              });
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // header ใช้ AdminPageHeader (breadcrumb + back) แบบเดียวกับหน้า drill-down อื่นในระบบ
    // (เช่น member_detail_view.dart) แทน Scaffold+AppBar เดิมที่สูงเกินจำเป็นเพราะ title
    // 2 บรรทัดซ้อน + toolbar เต็ม — เปลี่ยนมาใช้ตัวเดียวกันทั้งระบบ ทั้งสั้นลงและตรง pattern เดิม
    // Scaffold นี้ยังอยู่ในตัวเอง (ให้ FAB วางตำแหน่งได้) แต่ไม่ได้ push แบบ Get.to() ทับ shell
    // แล้ว — ฝังอยู่ในสล็อตเดิมของ sidebar shell เหมือนหน้า manage อื่น จึงเห็น sidebar ตลอด
    return Scaffold(
      backgroundColor: AppColors.dialogBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminPageHeader(leading: AppBackButton(onTap: widget.onBack), breadcrumb: ['แผนการฝึก', 'รายการแผนฝึก', _planName]),
            // --------------------------------------------
            // [FEATURE] COMMON_UI
            // [FUNCTION] AdminBreadcrumb (ใช้งานใน ManageSystemPlanDetailsView)
            // [DESCRIPTION] แสดง "รายการแผนฝึก › ชื่อแผนที่คลิกเข้ามา" กดที่ root กลับไปหน้ารายการแผนฝึก
            // [INPUT] widget.planName, widget.onBack
            // [OUTPUT] แถบ breadcrumb เหนือเนื้อหารายละเอียดแผน
            // [RELATED] WORKOUT_PLAN
            // --------------------------------------------
            AdminBreadcrumb(
              rootLabel: 'รายการแผนฝึก',
              currentLabel: _planName,
              onRootTap: widget.onBack,
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
                        child: LayoutBuilder(builder: (context, constraints) {
                          if (constraints.maxWidth < 720) {
                            return Column(children: [
                              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _buildInfoCard()),
                              const SizedBox(height: 12),
                              Expanded(child: _buildDayTabs()),
                            ]);
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Row(
                              // start แทน stretch — การ์ดซ้ายสูงพอดีเนื้อหาของมันเอง ไม่ยืดตามฝั่งขวา
                              // (เดิม stretch ทำให้เหลือพื้นที่ว่างเยอะเวลาเนื้อหาขวายาวกว่าซ้ายมาก)
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: _buildInfoCard()),
                                const SizedBox(width: 16),
                                Expanded(flex: 7, child: SizedBox(height: constraints.maxHeight, child: _buildDayTabs())),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: AppFab(onPressed: _showForm, color: AppColors.primaryGreen),
    );
  }

  // ซ้าย — การ์ดอ่านอย่างเดียว: รูป/ชื่อ/badge ระดับ/จำนวนวัน
  Widget _buildInfoCard() {
    final imageUrl = ApiClient.prefixPath(_planImage);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              height: 120,
              color: AppColors.calorieBadgeBg,
              child: imageUrl != null
                  ? AdminNetworkImage(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.assignment_outlined, color: AppColors.primaryGreen, size: 36))
                  : const Icon(Icons.assignment_outlined, color: AppColors.primaryGreen, size: 36),
            ),
          ),
          const SizedBox(height: 14),
          // แก้ไขข้อมูลแผน (ชื่อ/รูป/วัน/ระดับ) เปิด dialog ในหน้านี้ตรงๆ ไม่ต้อง pop กลับไปหน้ารายการ
          // — ใช้ตัวป้องกันข้อมูลกำพร้าชุดเดียวกับฟอร์มที่หน้ารายการ (core/utils/plan_orphan_guard.dart)
          Row(children: [
            Expanded(child: Text(_planName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark))),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _showEditPlanForm,
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 18)),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _diffColor(_planDifficulty).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _diffColor(_planDifficulty), width: 0.5)),
            child: Text(_diffLabel(_planDifficulty), style: TextStyle(fontSize: 11, color: _diffColor(_planDifficulty), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('$_planDaysPerWeek วัน/สัปดาห์', style: const TextStyle(fontSize: 12.5, color: AppColors.textBody)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.fitness_center, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('ทั้งหมด ${planDetails.length} รายการ', style: const TextStyle(fontSize: 12.5, color: AppColors.textBody)),
          ]),
          // คำอธิบายแผน — เดิมหน้านี้ไม่โชว์เลยทั้งที่มีข้อมูลจริง (เห็นได้จากหน้ารายการ) ทิ้งพื้นที่
          // ว่างด้านล่างการ์ดไว้เฉยๆ แอดมินต้องสลับกลับไปหน้ารายการเพื่อดู
          if ((_planDescription ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),
            Text(_planDescription!.trim(), style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.5)),
          ],
        ],
      ),
    );
  }

  // ขวา — tab ตามวันในสัปดาห์ แต่ละ tab แสดงรายการท่าของวันนั้น เรียงตาม ptd_order
  // ตัวสลับวันแบบ pill (ไม่ใช้ TabBar ขีดเส้นใต้ default ของ Material แล้ว) — สไตล์เดียวกับ
  // chip กรองที่ใช้ทั้งระบบ (โซนกล้ามเนื้อ/หมวดคาร์ดิโอ/ระดับความยาก) แทนเส้นใต้ที่ดูแข็งๆ
  // ยังขับเคลื่อนด้วย _tabController ตัวเดิม (TabBarView ด้านล่างยัง sync ตามอยู่) แค่เปลี่ยน
  // ตัวโชว์ผลด้านบนเป็น custom widget แทน TabBar ของ Material
  Widget _buildDaySwitcher() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) => Row(children: [
            for (var d = 1; d <= _planDaysPerWeek; d++) ...[
              if (d > 1) const SizedBox(width: 8),
              _dayPill(d, selected: _tabController.index == d - 1),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _dayPill(int dayNumber, {required bool selected}) {
    return GestureDetector(
      onTap: () => _tabController.animateTo(dayNumber - 1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primaryGreen : Colors.grey.shade300),
        ),
        child: Text(
          '${_dayLabel(dayNumber)} (${_dayItems(dayNumber).length})',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textBody),
        ),
      ),
    );
  }

  Widget _buildDayTabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDaySwitcher(),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [for (var d = 1; d <= _planDaysPerWeek; d++) _buildDayList(d)],
          ),
        ),
      ],
    );
  }

  // แถวเดียวเสมอ (ไม่ใช้ grid 2 คอลัมน์แล้ว) — ผู้ใช้ขอให้เห็นลำดับท่าของวันนั้นชัดเจนเป็นเส้นตรง
  // 1,2,3... แทนการไล่ซ้าย-ขวา-ซ้าย-ขวาแบบ grid ซึ่งอ่านลำดับสับสน
  Widget _buildDayList(int dayNumber) {
    final items = _dayItems(dayNumber);
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fitness_center_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          const Text('ยังไม่มีท่าในวันนี้', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildExerciseRow(
        items[index],
        order: index + 1,
        canMoveUp: index > 0,
        canMoveDown: index < items.length - 1,
        onMoveUp: () => _reorder(items, index, -1),
        onMoveDown: () => _reorder(items, index, 1),
      ),
    );
  }

  Widget _buildExerciseRow(
    Map<String, dynamic> item, {
    required int order,
    required bool canMoveUp,
    required bool canMoveDown,
    required VoidCallback onMoveUp,
    required VoidCallback onMoveDown,
  }) {
    final exName = _getExerciseName(item);
    final exImage = _getExerciseImage(item);
    final sets = item['ptd_sets'];
    final reps = item['ptd_reps'];
    final rest = item['ptd_rest_seconds'];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
            child: Text('$order', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
          const SizedBox(width: 12),
          Container(
            width: 64, height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.calorieBadgeBg, borderRadius: BorderRadius.circular(14)),
            child: exImage != null ? AdminNetworkImage(exImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 28)) : const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (sets != null && reps != null) _chip('$sets เซต × $reps', Colors.blue.shade700, const Color(0xFFE3F2FD)),
                  if (rest != null && rest != 0) _chip('พัก $rest วิ', Colors.orange.shade700, const Color(0xFFFFF3E0)),
                ]),
              ],
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: canMoveUp ? onMoveUp : null,
              child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_up, size: 20, color: canMoveUp ? AppColors.textBody : AppColors.textMuted.withValues(alpha: 0.3))),
            ),
            InkWell(
              onTap: canMoveDown ? onMoveDown : null,
              child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_down, size: 20, color: canMoveDown ? AppColors.textBody : AppColors.textMuted.withValues(alpha: 0.3))),
            ),
          ]),
          const SizedBox(width: 8),
          GestureDetector(onTap: () => _showForm(item: item), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 24))),
          const SizedBox(width: 6),
          GestureDetector(onTap: () => _handleDelete(item['ptd_id'], exName), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 24))),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
    );
  }
}

// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage System Plan Details (จัดการรายละเอียดแผนฝึกระบบ)
// ทำหน้าที่: Admin เพิ่ม/ลบท่าฝึกในแต่ละแผนมาตรฐาน กำหนดว่าวันไหนควรฝึกท่าอะไรบ้าง

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/core/constants/app_text_styles.dart';
import 'package:myapp/core/widgets/app_back_button.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_fab.dart';
import 'package:myapp/core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';

const Color _green = Color(0xFF1A7A4E);

class ManageSystemPlanDetailsView extends StatefulWidget {
  final int planId;
  final String planName;
  final int daysPerWeek;

  const ManageSystemPlanDetailsView({
    super.key,
    required this.planId,
    required this.planName,
    required this.daysPerWeek,
  });

  @override
  State<ManageSystemPlanDetailsView> createState() =>
      _ManageSystemPlanDetailsViewState();
}

class _ManageSystemPlanDetailsViewState
    extends State<ManageSystemPlanDetailsView> {
  List<dynamic> planDetails     = [];
  List<dynamic> weightExercises = [];
  bool isLoading = true;

  String get baseUrl => '${ApiClient.serverUrl}/api';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _loadInitialData() async {
    await Future.wait([_fetchPlanDetails(), _fetchWeightExercises()]);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchPlanDetails() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/workouts/details?plan_id=${widget.planId}'), headers: _authHeaders);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final list = data is Map
            ? (data['data'] ?? data['items'] ?? data['result'] ?? []) as List
            : data as List;
        if (mounted) setState(() => planDetails = list);
      }
    } catch (e) {
      debugPrint("Error fetching details: $e");
    }
  }

  Future<void> _fetchWeightExercises() async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/exercises/weights'), headers: _authHeaders);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final list = data is Map
            ? (data['data'] ?? data['items'] ?? data['result'] ?? []) as List
            : data as List;
        if (mounted) setState(() => weightExercises = list);
      }
    } catch (e) {
      debugPrint("Error fetching exercises: $e");
    }
  }

  // ── Helper ────────────────────────────────────────────────────────────────
  static const _thaiDayNames = [
    'จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์', 'อาทิตย์',
  ];

  // ptd_day_number คือเลขวันในสัปดาห์จริง (1=จันทร์...7=อาทิตย์ ตาม DateTime.weekday)
  // ต้อง map ตรงตัวแบบเดียวกับ dropdown เพิ่มท่า (ด้านล่าง) และฝั่งสมาชิก
  // (WeightTrainingScheduleView._currentDayNumber = _selectedDate.weekday)
  String _dayLabel(int dayNumber) {
    if (dayNumber >= 1 && dayNumber <= 7) {
      return _thaiDayNames[dayNumber - 1];
    }
    return 'วัน $dayNumber';
  }

  String _getExerciseName(Map<String, dynamic> item) {
    // ใช้ข้อมูล preload จาก API ก่อน (backend ทำ Preload("WeightExercise"))
    final preloaded = item['weight_exercise'];
    if (preloaded is Map && preloaded['wet_name'] != null) {
      return preloaded['wet_name'];
    }
    // Fallback: หาจาก local list
    final wetId = item['wet_id'];
    if (wetId == null) return 'ไม่ระบุ';
    final ex = weightExercises.firstWhere(
      (e) => e['wet_id'] == wetId,
      orElse: () => null,
    );
    return ex?['wet_name'] ?? 'ท่า #$wetId';
  }

  String? _getExerciseImage(Map<String, dynamic> item) {
    final preloaded = item['weight_exercise'];
    if (preloaded is Map && preloaded['wet_image'] != null) {
      return ApiClient.prefixPath(preloaded['wet_image']);
    }
    final wetId = item['wet_id'];
    if (wetId == null) return null;
    final ex = weightExercises.firstWhere(
      (e) => e['wet_id'] == wetId,
      orElse: () => null,
    );
    return ApiClient.prefixPath(ex?['wet_image']);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _handleSave(
      Map<String, dynamic>? oldItem, Map<String, dynamic> formData) async {
    Navigator.pop(context); // ปิด bottom sheet

    _showLoadingDialog();
    try {
      http.Response response;
      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_token",
      };
      final body = jsonEncode(formData);

      if (oldItem == null) {
        response = await http.post(
            Uri.parse('$baseUrl/workouts/details'),
            headers: headers, body: body);
      } else {
        response = await http.put(
            Uri.parse('$baseUrl/workouts/details/${oldItem['ptd_id']}'),
            headers: headers, body: body);
      }

      if (!mounted) return;
      Navigator.pop(context); // ปิด loading

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchPlanDetails();
        _showSnackBar('บันทึกข้อมูลเรียบร้อย', type: AppAlertType.success);
      } else {
        _showSnackBar('ล้มเหลว: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _handleDelete(int detId) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบรายการนี้ออกจากแผนหรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (!confirm) return;

    _showLoadingDialog();
    try {
      final response = await http.delete(
          Uri.parse('$baseUrl/workouts/details/$detId'),
          headers: _authHeaders);
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200) {
        await _fetchPlanDetails();
        showAdminTopToast(context, 'ลบรายการสำเร็จ');
      } else {
        _showSnackBar('ลบล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // ── Form ──────────────────────────────────────────────────────────────────
  void _showForm({Map<String, dynamic>? item}) {
    int? selectedWetId = item?['wet_id'] ??
        (weightExercises.isNotEmpty ? weightExercises.first['wet_id'] as int? : null);
    int selectedDay = item?['ptd_day_number'] ?? 1;

    final setsCtrl = TextEditingController(
        text: item == null ? '' : (item['ptd_sets'] ?? '').toString());
    final repsCtrl = TextEditingController(
        text: item == null ? '' : (item['ptd_reps'] ?? '').toString());
    final restCtrl = TextEditingController(
        text: item == null ? '' : (item['ptd_rest_seconds'] ?? '').toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 30),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100)),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(25)),
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
                        item == null
                            ? 'เพิ่มท่าออกกำลังกาย'
                            : 'แก้ไขท่าออกกำลังกาย',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: Colors.grey.shade400, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ]),
                ),

                // ── Fields ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('วันที่ในแผน',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        value: selectedDay,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _green, width: 1.5),
                          ),
                          prefixIcon: const Icon(
                              Icons.calendar_today_outlined,
                              color: _green, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('วันจันทร์')),
                          DropdownMenuItem(value: 2, child: Text('วันอังคาร')),
                          DropdownMenuItem(value: 3, child: Text('วันพุธ')),
                          DropdownMenuItem(value: 4, child: Text('วันพฤหัสบดี')),
                          DropdownMenuItem(value: 5, child: Text('วันศุกร์')),
                          DropdownMenuItem(value: 6, child: Text('วันเสาร์')),
                          DropdownMenuItem(value: 7, child: Text('วันอาทิตย์')),
                        ],
                        onChanged: (v) => setModalState(() => selectedDay = v!),
                      ),
                      const SizedBox(height: 14),

                      const Text('ท่าออกกำลังกาย *',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        value: selectedWetId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: _green, width: 1.5),
                          ),
                          prefixIcon: const Icon(
                              Icons.fitness_center_outlined,
                              color: _green, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                        ),
                        items: weightExercises
                            .map<DropdownMenuItem<int>>((ex) =>
                                DropdownMenuItem<int>(
                                  value: ex['wet_id'] as int,
                                  child: Text(
                                    ex['wet_name'] ?? 'ไม่มีชื่อ',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setModalState(() => selectedWetId = v),
                      ),
                      const SizedBox(height: 14),

                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('เซต',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: setsCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                onTap: () => setsCtrl.selection = TextSelection(
                                  baseOffset: 0, extentOffset: setsCtrl.text.length),
                                decoration: InputDecoration(
                                  hintText: 'เช่น 3',
                                  hintStyle: const TextStyle(
                                      fontSize: 13, color: Color(0xFFA0A1A5)),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: _green, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ครั้ง',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: repsCtrl,
                                keyboardType: TextInputType.number,
                                onTap: () => repsCtrl.selection = TextSelection(
                                  baseOffset: 0, extentOffset: repsCtrl.text.length),
                                decoration: InputDecoration(
                                  hintText: 'เช่น 12',
                                  hintStyle: const TextStyle(
                                      fontSize: 13, color: Color(0xFFA0A1A5)),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: _green, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),

                      const Text('เวลาพักระหว่างเซต (วินาที)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: restCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onTap: () => restCtrl.selection = TextSelection(
                          baseOffset: 0, extentOffset: restCtrl.text.length),
                        decoration: InputDecoration(
                          hintText: 'เช่น 90',
                          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: _green, width: 1.5),
                          ),
                          prefixIcon: const Icon(Icons.timer_outlined,
                              color: _green, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            if (selectedWetId == null) {
                              _showSnackBar('กรุณาเลือกท่าออกกำลังกาย');
                              return;
                            }
                            _handleSave(item, {
                              "wpt_id":           widget.planId,
                              "ptd_day_number":   selectedDay,
                              "wet_id":           selectedWetId,
                              "ptd_sets":         int.tryParse(setsCtrl.text) ?? 3,
                              "ptd_reps":         repsCtrl.text.trim().isEmpty ? '12' : repsCtrl.text.trim(),
                              "ptd_rest_seconds": int.tryParse(restCtrl.text) ?? 90,
                            });
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
              ],
            ),
          ),
        ),
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
        title: Column(
          children: [
            Text(
              widget.planName,
              style: AppTextStyles.pageTitle,
            ),
            const Text(
              'รายละเอียดแผนการฝึก',
              style: AppTextStyles.pageSubtitle,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          SizedBox(
              height: MediaQuery.of(context).padding.top + kToolbarHeight),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text(
                'ทั้งหมด ${planDetails.length} รายการ',
                style: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
              ),
            ]),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : planDetails.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fitness_center_outlined,
                                  size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              const Text('ยังไม่มีท่าในแผนนี้',
                                  style: TextStyle(color: Colors.grey)),
                            ]),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _fetchPlanDetails();
                        },
                        child: _buildGroupedList(),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppFab(onPressed: _showForm, color: _green),
    );
  }

  Widget _buildGroupedList() {
    // จัดกลุ่มตาม ptd_day_number
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final raw in planDetails) {
      final item = raw as Map<String, dynamic>;
      final day = (item['ptd_day_number'] as num?)?.toInt() ?? 0;
      grouped.putIfAbsent(day, () => []).add(item);
    }
    final sortedDays = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final day in sortedDays) ...[
          _buildDayHeader(day, grouped[day]!.length),
          ...grouped[day]!.map(_buildExerciseRow),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildDayHeader(int dayNumber, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
              color: _green, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today, color: Colors.white, size: 12),
            const SizedBox(width: 5),
            Text(
              'วัน${_dayLabel(dayNumber)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text('$count ท่า',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Expanded(
            child: Container(
                margin: const EdgeInsets.only(left: 8),
                height: 1,
                color: Colors.grey.shade200)),
      ]),
    );
  }

  Widget _buildExerciseRow(Map<String, dynamic> item) {
    final exName  = _getExerciseName(item);
    final exImage = _getExerciseImage(item);
    final sets   = item['ptd_sets'];
    final reps   = item['ptd_reps'];
    final rest   = item['ptd_rest_seconds'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
            child: exImage != null
                ? Image.network(exImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.fitness_center, color: _green, size: 18))
                : const Icon(Icons.fitness_center, color: _green, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (sets != null && reps != null)
                      _chip('$sets เซต × $reps',
                          Colors.blue.shade700,
                          const Color(0xFFE3F2FD)),
                    if (rest != null && rest != 0)
                      _chip('พัก $rest วิ',
                          Colors.orange.shade700,
                          const Color(0xFFFFF3E0)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showForm(item: item),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.edit_outlined, color: _green, size: 22),
            ),
          ),
          GestureDetector(
            onTap: () => _handleDelete(item['ptd_id']),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 22),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor)),
    );
  }
}
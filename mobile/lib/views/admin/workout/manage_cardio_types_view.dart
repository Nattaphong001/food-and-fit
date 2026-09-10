// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage Cardio Types (จัดการประเภทคาร์ดิโอ)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบหมวดหมู่คาร์ดิโอ ใช้จัดกลุ่มกิจกรรมคาร์ดิโอในระบบ

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';

const Color _green = Color(0xFF5EA61A);

// ─── Cardio icon mapping ──────────────────────────────────────────────────────
IconData _getCardioIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('จักรยาน') || n.contains('ปั่น'))  return Icons.directions_bike_outlined;
  if (n.contains('ว่าย') || n.contains('น้ำ'))       return Icons.pool_outlined;
  if (n.contains('วิ่ง'))                             return Icons.directions_run_outlined;
  if (n.contains('เต้น') || n.contains('แอโรบิก'))   return Icons.music_note_outlined;
  if (n.contains('เดิน'))                             return Icons.directions_walk_outlined;
  if (n.contains('กีฬา'))                             return Icons.sports_outlined;
  if (n.contains('หนัก') || n.contains('คาร์ดิโอ'))  return Icons.fitness_center_outlined;
  return Icons.flash_on_outlined;
}

class ManageCardioTypesView extends StatefulWidget {
  const ManageCardioTypesView({super.key});

  @override
  State<ManageCardioTypesView> createState() => _ManageCardioTypesViewState();
}

class _ManageCardioTypesViewState extends State<ManageCardioTypesView> {
  List<dynamic> categories = [];
  bool isLoading = true;

  String get baseUrl => ApiClient.serverUrl;
  String get apiUrl  => '${ApiClient.serverUrl}/api/exercises/cardio-categories';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────
  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: _authHeaders);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        setState(() { categories = list; isLoading = false; });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("fetchCategories exception: $e");
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _handleDelete(int id, String name) async {
    _showLoadingDialog();
    int itemCount = 0;
    try {
      final res = await http.get(
          Uri.parse('$baseUrl/api/exercises/cardio'),
          headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final items = (data is Map
            ? (data['data'] ?? data['items'] ?? data['result'] ?? [])
            : data) as List;
        itemCount = items.where((f) {
          final catId = f['cdc_id'] ?? f['category']?['cdc_id'];
          return catId == id;
        }).length;
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);

    if (itemCount > 0) {
      await showAppNoticeDialog(
        context,
        icon: Icons.error_outline_rounded,
        title: 'ไม่สามารถลบได้',
        content: 'ประเภท "$name" ยังมีท่าออกกำลังกายอยู่ $itemCount รายการ\n\nกรุณาลบหรือย้ายท่าออกกำลังกายออกก่อน',
      );
      return;
    }

    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      _showLoadingDialog();
      try {
        final response = await http.delete(
            Uri.parse('$apiUrl/$id'), headers: _authHeaders);
        if (!mounted) return;
        Navigator.pop(context);
        if (response.statusCode == 200) {
          _fetchCategories();
          showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${response.statusCode}');
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showSnackBar('ลบไม่สำเร็จ: $e');
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _handleSave(Map<String, dynamic>? oldItem, String name, String description) async {
    if (name.trim().isEmpty) return;
    _showLoadingDialog();
    try {
      http.Response response;
      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_token",
      };
      final body = json.encode({"cdc_name": name.trim(), "cdc_description": description.trim()});
      if (oldItem == null) {
        response = await http.post(Uri.parse(apiUrl), headers: headers, body: body);
      } else {
        response = await http.put(Uri.parse('$apiUrl/${oldItem['cdc_id']}'), headers: headers, body: body);
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchCategories();
        if (!mounted) return;
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มสำเร็จ' : 'แก้ไขสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
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
    final nameCtrl = TextEditingController(text: item?['cdc_name'] ?? '');
    final descCtrl = TextEditingController(text: item?['cdc_description'] ?? '');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        backgroundColor: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
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
                      color: const Color(0xFF1BB874),
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item == null ? 'เพิ่มประเภทคาร์ดิโอ' : 'แก้ไขประเภทคาร์ดิโอ',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ]),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ชื่อประเภท *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'เช่น วิ่ง, ว่ายน้ำ, ปั่นจักรยาน',
                      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.flash_on_outlined,
                          color: const Color(0xFF1BB874), size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
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
                      hintText: 'รายละเอียดประเภทคาร์ดิโอ (ไม่บังคับ)',
                      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _handleSave(item, nameCtrl.text, descCtrl.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
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
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      // ── ลบ AppBar ออก ใช้ extendBodyBehindAppBar แทน ──
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
              'Cardio Types',
              style: AppTextStyles.pageTitle,
            ),
            Text(
              'จัดการหมวดหมู่การออกกำลังกายคาร์ดิโอ',
              style: AppTextStyles.pageSubtitle,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Spacer แทนที่ header เดิม (safe area + appbar height)
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

          // Count bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text(
                'ทั้งหมด ${categories.length} ประเภท',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ]),
          ),

          // List
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : categories.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.flash_on_outlined,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text('ยังไม่มีประเภทคาร์ดิโอ',
                              style: TextStyle(color: Colors.grey)),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _fetchCategories();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: categories.length,
                          itemBuilder: (context, i) {
                            final item = categories[i];
                            final name = (item['cdc_name'] ?? '').toString();
                            return Container(
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
                                  // Icon avatar
                                  Container(
                                    width: 46, height: 46,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(_getCardioIcon(name),
                                        color: const Color(0xFF1BB874), size: 22),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name
                                  Expanded(
                                    child: Text(name,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black87)),
                                  ),

                                  // Edit
                                  GestureDetector(
                                    onTap: () => _showForm(item: item),
                                    child: Container(
                                      width: 34, height: 34,
                                      decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.edit_outlined,
                                          color: const Color(0xFF1BB874), size: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 2),

                                  // Delete
                                  GestureDetector(
                                    onTap: () => _handleDelete(
                                        item['cdc_id'], name),
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
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      floatingActionButton: AppFab(onPressed: _showForm, color: const Color(0xFF1BB874)),
    );
  }
}
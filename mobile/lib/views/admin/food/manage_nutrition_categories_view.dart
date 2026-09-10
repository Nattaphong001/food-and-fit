// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage Nutrition Categories (จัดการหมวดหมู่อาหาร)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบหมวดหมู่โภชนาการ ใช้จัดกลุ่มรายการอาหารในระบบ

import 'package:flutter/material.dart';
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
import 'package:myapp/services/nutrition_service.dart';

// ─── Category icon mapping ────────────────────────────────────────────────────
IconData _getCategoryIcon(String catName) {
  final n = catName.toLowerCase();
  if (n.contains('ของว่าง') || n.contains('อาหารว่าง')) return Icons.cookie_outlined;
  if (n.contains('กับข้าว') || n.contains('กับ'))        return Icons.set_meal_outlined;
  if (n.contains('วัตถุดิบ'))                             return Icons.egg_alt_outlined;
  if (n.contains('ผักและผลไม้') || n.contains('ผัก'))    return Icons.eco_outlined;
  if (n.contains('ผลไม้'))                                return Icons.apple_outlined;
  if (n.contains('ขนม'))                                  return Icons.cake_outlined;
  if (n.contains('เครื่องดื่ม'))                          return Icons.local_drink_outlined;
  return Icons.restaurant_outlined;
}

const Color _green = Color(0xFF1BB874);

class ManageNutritionCategoriesView extends StatefulWidget {
  const ManageNutritionCategoriesView({super.key});

  @override
  State<ManageNutritionCategoriesView> createState() =>
      _ManageNutritionCategoriesViewState();
}

class _ManageNutritionCategoriesViewState
    extends State<ManageNutritionCategoriesView> {
  List<dynamic> categories = [];
  bool _isLoading = true;

  String get baseUrl => ApiClient.serverUrl;
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
      final response = await http.get(
          Uri.parse('$baseUrl/api/nutrition/categories'),
          headers: _authHeaders);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          categories = data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Fetch Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _handleSave(Map<String, dynamic>? oldItem, String name) async {
    if (name.trim().isEmpty) return;

    final trimmedName = name.trim().toLowerCase();
    final isDuplicate = categories.any((c) {
      final same = (c['nttc_name'] ?? '').toString().trim().toLowerCase() == trimmedName;
      final isCurrent = oldItem != null && c['nttc_id'] == oldItem['nttc_id'];
      return same && !isCurrent;
    });
    if (isDuplicate) {
      _showSnackBar('หมวดหมู่ "$name" มีในระบบแล้ว', type: AppAlertType.warning);
      return;
    }

    _showLoadingDialog();
    try {
      http.Response response;
      final headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": "Bearer $_token",
      };

      if (oldItem == null) {
        response = await http.post(
          Uri.parse('$baseUrl/api/nutrition/categories'),
          headers: headers,
          body: jsonEncode({"nttc_name": name.trim()}),
        );
      } else {
        final int id = oldItem['nttc_id'];
        response = await http.put(
          Uri.parse('$baseUrl/api/nutrition/categories/$id'),
          headers: headers,
          body: jsonEncode({"nttc_id": id, "nttc_name": name.trim()}),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200 || response.statusCode == 201) {
        NutritionService.to.clearCategoriesCache();
        await _fetchCategories();
        Navigator.pop(context);
        _showSnackBar('บันทึกสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('ล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _handleDelete(int id, String name) async {
    _showLoadingDialog();
    int foodCount = 0;
    try {
      final res = await http.get(
          Uri.parse('$baseUrl/api/nutrition/foods'),
          headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        final foods = (data['data'] as List?) ?? [];
        foodCount = foods.where((f) {
          final catId = f['nttc_id'] ?? f['category']?['nttc_id'];
          return catId == id;
        }).length;
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);

    if (foodCount > 0) {
      await showAppNoticeDialog(
        context,
        icon: Icons.error_outline_rounded,
        title: 'ไม่สามารถลบได้',
        content: 'หมวดหมู่ "$name" ยังมีรายการอาหารอยู่ $foodCount รายการ\n\nกรุณาลบหรือย้ายรายการอาหารออกก่อน',
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
            Uri.parse('$baseUrl/api/nutrition/categories/$id'),
            headers: _authHeaders);
        if (!mounted) return;
        Navigator.pop(context);
        if (response.statusCode == 200) {
          NutritionService.to.clearCategoriesCache();
          _fetchCategories();
          showAdminTopToast(context, 'ลบข้อมูลเรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${response.statusCode}');
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showSnackBar('ลบไม่สำเร็จ: $e');
      }
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
    final ctrl = TextEditingController(
        text: item != null ? (item['nttc_name'] ?? '').toString().trim() : '');

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
                      color: _green, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item == null ? 'เพิ่มหมวดหมู่ใหม่' : 'แก้ไขหมวดหมู่',
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
                  const Text('ชื่อหมวดหมู่ *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: 'เช่น อาหารหลัก, ผลไม้',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _green, width: 1.5),
                      ),
                      prefixIcon: const Icon(Icons.category,
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
                      onPressed: () => _handleSave(item, ctrl.text),
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
        title: const Column(children: [
          Text('Nutrition Categories',
              style: AppTextStyles.pageTitle),
          Text('จัดการประเภทโภชนาการ',
              style: AppTextStyles.pageSubtitle),
        ]),
        centerTitle: true,
      ),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

          // Count bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Text('ทั้งหมด ${categories.length} หมวดหมู่',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ]),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : categories.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.category_outlined,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text('ยังไม่มีหมวดหมู่',
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
                            final name =
                                (item['nttc_name'] ?? '').toString().trim();
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
                                    child: Icon(_getCategoryIcon(name),
                                        color: _green, size: 22),
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
                                          color: _green, size: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 2),

                                  // Delete
                                  GestureDetector(
                                    onTap: () =>
                                        _handleDelete(item['nttc_id'], name),
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

      floatingActionButton: AppFab(onPressed: _showForm, color: _green),
    );
  }
}
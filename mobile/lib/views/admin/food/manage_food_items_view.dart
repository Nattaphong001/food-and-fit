// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage Food Items (จัดการรายการอาหาร)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบข้อมูลอาหาร รวมถึงแคลอรี่ สารอาหาร และรูปภาพอาหาร

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:myapp/core/constants/app_colors.dart';
import 'package:myapp/core/constants/app_text_styles.dart';
import 'package:myapp/core/widgets/app_back_button.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_fab.dart';
import 'package:myapp/core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';
import 'package:myapp/services/nutrition_service.dart';

// ─── wrapper สำหรับ state ใน dialog ─────────────────────────────────────────
class _FormState {
  int? selectedCatId;
  File? selectedImage;
  Uint8List? selectedImageBytes;
  String? selectedImageName;
  _FormState({this.selectedCatId});
}

// ─── enum เรียงลำดับ ─────────────────────────────────────────────────────────
enum SortField { latest, calories, protein, carbs, fat }

extension SortFieldLabel on SortField {
  String get label {
    switch (this) {
      case SortField.latest:   return 'ล่าสุด';
      case SortField.calories: return 'kcal';
      case SortField.protein:  return 'โปรตีน';
      case SortField.carbs:    return 'คาร์บ';
      case SortField.fat:      return 'ไขมัน';
    }
  }
  String get field {
    switch (this) {
      case SortField.latest:   return 'ntt_id';
      case SortField.calories: return 'ntt_calories';
      case SortField.protein:  return 'ntt_protein';
      case SortField.carbs:    return 'ntt_carbs';
      case SortField.fat:      return 'ntt_fat';
    }
  }
}

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

class ManageFoodItemsView extends StatefulWidget {
  const ManageFoodItemsView({super.key});
  @override
  State<ManageFoodItemsView> createState() => _ManageFoodItemsViewState();
}

class _ManageFoodItemsViewState extends State<ManageFoodItemsView> {
  List<dynamic> foods      = [];
  List<dynamic> categories = [];
  bool _isLoading          = true;

  // ── Search ────────────────────────────────────────────────────────────────
  bool _searchVisible = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ── Sort / Filter — default: calories มากไปน้อย ───────────────────────────
  SortField _sortField   = SortField.calories;
  bool _sortAscending    = false;

  // ── Category tabs ─────────────────────────────────────────────────────────
  int? _selectedCategoryFilter;
  bool _groupByCategory = false;

  // ── API ───────────────────────────────────────────────────────────────────
  String get baseUrl   => ApiClient.serverUrl;
  String get serverUrl => ApiClient.serverUrl;
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  String _buildImageUrl(String path) => ApiClient.prefixPath(path) ?? '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Filtered / Grouped ────────────────────────────────────────────────────
  List<dynamic> get _filteredFoods {
    List<dynamic> result = List.from(foods);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((item) {
        final name = (item['ntt_food_name'] ?? '').toLowerCase();
        final cat  = (item['category']?['nttc_name'] ?? '').toLowerCase();
        return name.contains(q) || cat.contains(q);
      }).toList();
    }
    if (_selectedCategoryFilter != null) {
      result = result.where((item) {
        final id = item['nttc_id'] ?? item['category']?['nttc_id'];
        return id == _selectedCategoryFilter;
      }).toList();
    }
    result.sort((a, b) {
      final va = (a[_sortField.field] as num?) ?? 0;
      final vb = (b[_sortField.field] as num?) ?? 0;
      return _sortAscending ? va.compareTo(vb) : vb.compareTo(va);
    });
    return result;
  }

  Map<String, List<dynamic>> get _groupedFoods {
    final result = <String, List<dynamic>>{};
    for (final item in _filteredFoods) {
      result.putIfAbsent(_getCatName(item), () => []).add(item);
    }
    return result;
  }

  String _getCatName(dynamic item) {
    if (item['category']?['nttc_name'] != null) return item['category']['nttc_name'];
    final cat = categories.firstWhere(
      (c) => c['nttc_id'] == item['nttc_id'], orElse: () => null);
    return cat?['nttc_name'] ?? 'ไม่มีหมวดหมู่';
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await _fetchCategories();
    await _fetchFoods();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await http.get(
          Uri.parse('$baseUrl/api/nutrition/categories'), headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        categories = data['data'] ?? [];
      }
    } catch (e) { debugPrint("Fetch Categories Error: $e"); }
  }

  Future<void> _fetchFoods() async {
    try {
      final res = await http.get(
          Uri.parse('$baseUrl/api/nutrition/foods'), headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (mounted) setState(() => foods = data['data'] ?? []);
      }
    } catch (e) { debugPrint("Fetch Foods Error: $e"); }
  }

  void _showLoading() {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _handleDelete(int id, String name) async {
    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      _showLoading();
      try {
        final res = await http.delete(
            Uri.parse('$baseUrl/api/nutrition/foods/$id'),
            headers: _authHeaders);
        if (!mounted) return;
        Navigator.pop(context);
        if (res.statusCode == 200) {
          NutritionService.to.clearFoodsCache();
          await _fetchFoods();
          showAdminTopToast(context, 'ลบข้อมูลเรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${res.statusCode}');
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showSnackBar('Error: $e');
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _handleSave(
    Map<String, dynamic>? oldItem, String name, int? catId,
    String protein, String carbs, String fat, String calories,
    String servingWeight, String unit,
    File? imageFile, Uint8List? imageBytes, String? imageFileName,
  ) async {
    if (name.isEmpty || catId == null) {
      _showSnackBar('กรุณากรอกชื่ออาหารและเลือกหมวดหมู่');
      return;
    }
    final trimmedName = name.toLowerCase().trim();
    final isDuplicate = foods.any((f) {
      final same = (f['ntt_food_name'] ?? '').toString().toLowerCase().trim() == trimmedName;
      final isCurrent = oldItem != null && f['ntt_id'] == oldItem['ntt_id'];
      return same && !isCurrent;
    });
    if (isDuplicate) {
      _showSnackBar('ชื่ออาหาร "$name" มีในระบบแล้ว', type: AppAlertType.warning);
      return;
    }

    final parsedCalories      = double.tryParse(calories) ?? 0;
    final parsedProtein       = double.tryParse(protein) ?? 0;
    final parsedCarbs         = double.tryParse(carbs) ?? 0;
    final parsedFat           = double.tryParse(fat) ?? 0;
    final parsedServingWeight = double.tryParse(servingWeight) ?? 100;
    if (parsedCalories < 0 ||
        parsedProtein < 0 ||
        parsedCarbs < 0 ||
        parsedFat < 0 ||
        parsedServingWeight <= 0) {
      _showSnackBar('ค่าแคลอรี่/สารอาหาร/น้ำหนักต้องไม่ติดลบ', type: AppAlertType.warning);
      return;
    }

    _showLoading();
    try {
      final isEdit = oldItem != null;
      final url = isEdit
          ? '$baseUrl/api/nutrition/foods/${oldItem['ntt_id']}'
          : '$baseUrl/api/nutrition/foods';
      var request = http.MultipartRequest(
          isEdit ? 'PUT' : 'POST', Uri.parse(url));
      request.headers.addAll(_authHeaders);
      request.fields['ntt_food_name']      = name;
      request.fields['nttc_id']            = catId.toString();
      request.fields['ntt_calories']       = parsedCalories.toString();
      request.fields['ntt_protein']        = parsedProtein.toString();
      request.fields['ntt_carbs']          = parsedCarbs.toString();
      request.fields['ntt_fat']            = parsedFat.toString();
      request.fields['ntt_serving_weight'] = parsedServingWeight.toString();
      request.fields['ntt_unit']           = unit.isEmpty ? 'กรัม' : unit;

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'ntt_food_image', imageBytes, filename: imageFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(await http.MultipartFile.fromPath(
              'ntt_food_image', imageFile.path));
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200 || response.statusCode == 201) {
        NutritionService.to.clearFoodsCache();
        await _fetchFoods();
        if (!mounted) return;
        Navigator.pop(context);
        _showSnackBar(isEdit ? 'อัปเดตข้อมูลสำเร็จ' : 'เพิ่มข้อมูลสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('ไม่สามารถบันทึกได้: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // ── Form Dialog ───────────────────────────────────────────────────────────
  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl    = TextEditingController(text: item?['ntt_food_name'] ?? '');
    final proteinCtrl = TextEditingController(text: item?['ntt_protein']?.toString() ?? '');
    final carbCtrl    = TextEditingController(text: item?['ntt_carbs']?.toString() ?? '');
    final fatCtrl     = TextEditingController(text: item?['ntt_fat']?.toString() ?? '');
    final calCtrl     = TextEditingController(text: item?['ntt_calories']?.toString() ?? '');
    final servingCtrl = TextEditingController(
        text: item?['ntt_serving_weight']?.toString() ?? '100');
    final unitCtrl    = TextEditingController(text: item?['ntt_unit'] ?? 'กรัม');

    final bool isAdding = item == null;
    final int? lockedCatId = isAdding ? _selectedCategoryFilter : null;
    final bool showCatSelector = lockedCatId == null;

    final fs = _FormState(
      selectedCatId: lockedCatId ??
          item?['nttc_id'] ??
          (categories.isNotEmpty ? categories.first['nttc_id'] : null),
    );
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
          } else if (item?['ntt_food_image'] != null &&
              item?['ntt_food_image'] != "") {
            imagePreview = Image.network(
              _buildImageUrl(item!['ntt_food_image']),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.add_a_photo, size: 40),
            );
          } else {
            imagePreview =
                const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.88),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          bottom: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
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
                              ? 'เพิ่มรายการอาหารใหม่'
                              : 'แก้ไขรายการอาหาร',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: Colors.grey.shade400, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ]),
                  ),

                  // Body
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
                          // รูปภาพ
                          Center(
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Stack(children: [
                                Container(
                                  height: 100, width: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.grey.shade200, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: imagePreview,
                                ),
                                Positioned(
                                  bottom: 2, right: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                        color: _green,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Center(
                            child: Text('แตะเพื่อเปลี่ยนรูปภาพ',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 11)),
                          ),
                          const SizedBox(height: 16),

                          // ชื่ออาหาร
                          const Text('ชื่ออาหาร *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              hintText: 'เช่น ข้าวผัด, สลัดผัก...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.restaurant_menu,
                                  color: _green, size: 18),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // หมวดหมู่
                          const Text('หมวดหมู่ *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          if (showCatSelector)
                            DropdownButtonFormField<int>(
                              value: fs.selectedCatId,
                              items: categories
                                  .map<DropdownMenuItem<int>>((c) =>
                                      DropdownMenuItem<int>(
                                        value: c['nttc_id'] as int,
                                        child: Text(c['nttc_name'] ?? '',
                                            style: const TextStyle(
                                                fontSize: 13)),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setModalState(() => fs.selectedCatId = v),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: _green, width: 1.5),
                                ),
                                prefixIcon: const Icon(Icons.category,
                                    color: _green, size: 18),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 12),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: _green.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _green.withOpacity(0.3), width: 1),
                              ),
                              child: Row(children: [
                                const Icon(Icons.category,
                                    color: _green, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    categories.firstWhere(
                                      (c) => c['nttc_id'] == fs.selectedCatId,
                                      orElse: () => {'nttc_name': ''},
                                    )['nttc_name'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _green),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('อัตโนมัติ',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _green,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                          const SizedBox(height: 16),

                          // สารอาหาร
                          _sectionLabel('สารอาหาร'),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: _nutriField(
                                ctrl: proteinCtrl, label: 'โปรตีน (g)',
                                color: Colors.blue,
                                icon: Icons.fitness_center)),
                            const SizedBox(width: 6),
                            Expanded(child: _nutriField(
                                ctrl: carbCtrl, label: 'คาร์บ (g)',
                                color: Colors.purple, icon: Icons.grain)),
                            const SizedBox(width: 6),
                            Expanded(child: _nutriField(
                                ctrl: fatCtrl, label: 'ไขมัน (g)',
                                color: Colors.orange,
                                icon: Icons.water_drop)),
                          ]),
                          const SizedBox(height: 16),

                          // ข้อมูลปริมาณ
                          _sectionLabel('ข้อมูลปริมาณ'),
                          const SizedBox(height: 8),
                          const Text('พลังงาน (kcal)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: calCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 200',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(
                                  Icons.local_fire_department,
                                  color: Colors.orange, size: 18),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('ขนาดต่อหน่วย',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: servingCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: 'เช่น 100',
                                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: _green, width: 1.5),
                                      ),
                                      prefixIcon: const Icon(Icons.scale,
                                          color: Colors.teal, size: 18),
                                      contentPadding: const EdgeInsets.symmetric(
                                          vertical: 12, horizontal: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('หน่วย',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: unitCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'เช่น กรัม',
                                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: _green, width: 1.5),
                                      ),
                                      prefixIcon: const Icon(
                                          Icons.straighten,
                                          color: Colors.teal, size: 18),
                                      contentPadding: const EdgeInsets.symmetric(
                                          vertical: 12, horizontal: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                          const SizedBox(height: 22),

                          // ปุ่มบันทึก
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: () => _handleSave(
                                item, nameCtrl.text, fs.selectedCatId,
                                proteinCtrl.text, carbCtrl.text,
                                fatCtrl.text, calCtrl.text,
                                servingCtrl.text, unitCtrl.text,
                                fs.selectedImage, fs.selectedImageBytes,
                                fs.selectedImageName,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                              child: const Text('บันทึกข้อมูล',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ),
                          ),
                          const SizedBox(height: 4),
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

  Widget _sectionLabel(String text) => Row(children: [
    Container(
        width: 3, height: 14,
        decoration: BoxDecoration(
            color: _green, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 7),
    Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: Colors.black54)),
  ]);

  Widget _nutriField({
    required TextEditingController ctrl,
    required String label,
    required Color color,
    required IconData icon,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
              prefixIcon: Icon(icon, color: color, size: 16),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            ),
          ),
        ],
      );

  // ── Category Tabs ─────────────────────────────────────────────────────────
  Widget _buildCategoryTabs() {
    final allCategories = <Map<String, dynamic>>[
      {'nttc_id': null, 'nttc_name': 'ทั้งหมด'},
      ...categories.map((c) => Map<String, dynamic>.from(c)),
    ];

    return SizedBox(
      height: 90,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: allCategories.map((cat) {
            final catId   = cat['nttc_id'] as int?;
            final catName = cat['nttc_name'] ?? '';
            final selected = _selectedCategoryFilter == catId;
            final icon = catId == null
                ? Icons.grid_view_rounded
                : _getCategoryIcon(catName);

            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 60,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategoryFilter = catId;
                    _groupByCategory        = false;
                  }),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primaryGreen : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? AppColors.primaryGreen : Colors.grey.shade200,
                            width: selected ? 2 : 1,
                          ),
                          boxShadow: [BoxShadow(
                            color: selected
                                ? AppColors.primaryGreen.withOpacity(0.2)
                                : Colors.black.withOpacity(0.05),
                            blurRadius: 6, offset: const Offset(0, 2),
                          )],
                        ),
                        child: Icon(icon, size: 20,
                            color: selected ? Colors.black87 : Colors.grey.shade500),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 30,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(catName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? AppColors.primaryGreen : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Sort Sheet ────────────────────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void setSortField(SortField f) {
            setSheetState(() {
              if (_sortField == f) {
                _sortAscending = !_sortAscending;
              } else {
                _sortField     = f;
                _sortAscending = false;
              }
            });
            setState(() {});
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Text('เรียงตาม',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    SortField.calories,
                    SortField.protein,
                    SortField.carbs,
                    SortField.fat,
                  ].map((f) {
                    final sel = _sortField == f;
                    return GestureDetector(
                      onTap: () => setSortField(f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 9),
                        decoration: BoxDecoration(
                          color: sel ? _green : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(f.label,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _directionTile(
                  label: 'เรียงจากน้อยไปมาก',
                  selected: _sortAscending,
                  onTap: () {
                    setSheetState(() => _sortAscending = true);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 4),
                _directionTile(
                  label: 'เรียงจากมากไปน้อย',
                  selected: !_sortAscending,
                  onTap: () {
                    setSheetState(() => _sortAscending = false);
                    setState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _directionTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _green.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _green : Colors.grey.shade200,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? _green : Colors.black87,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ))),
            if (selected)
              Container(
                width: 16, height: 16,
                decoration:
                    const BoxDecoration(color: _green, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
          ]),
        ),
      );

  // ── Food Card ─────────────────────────────────────────────────────────────
  Widget _buildFoodCard(dynamic item) {
    final catName  = _getCatName(item);
    final imgPath  = item['ntt_food_image'] as String?;
    final calories = (item['ntt_calories'] as num?)?.toDouble() ?? 0;
    final protein  = (item['ntt_protein']  as num?)?.toDouble() ?? 0;
    final carbs    = (item['ntt_carbs']    as num?)?.toDouble() ?? 0;
    final fat      = (item['ntt_fat']      as num?)?.toDouble() ?? 0;
    final serving  = item['ntt_serving_weight'];
    final unit     = item['ntt_unit'] ?? 'กรัม';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.hardEdge,
              child: (imgPath != null && imgPath.isNotEmpty)
                  ? Image.network(
                      _buildImageUrl(imgPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.fastfood, color: _green, size: 22),
                    )
                  : const Icon(Icons.fastfood, color: _green, size: 22),
            ),
            const SizedBox(width: 10),

            // Info — ใช้ Expanded + Wrap แทน Row เพื่อป้องกัน overflow
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(catName,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item['ntt_food_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  // แถว 1: ขนาด + kcal
                  Wrap(
                    spacing: 3,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('$serving $unit',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      _badge('${calories.toStringAsFixed(0)} kcal',
                          Colors.blue,
                          highlight: _sortField == SortField.calories),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // แถว 2: โปรตีน คาร์บ ไขมัน
                  Wrap(
                    spacing: 3,
                    runSpacing: 2,
                    children: [
                      _badge('P ${protein.toStringAsFixed(0)}g',
                          Colors.green,
                          highlight: _sortField == SortField.protein),
                      _badge('C ${carbs.toStringAsFixed(0)}g',
                          Colors.purple,
                          highlight: _sortField == SortField.carbs),
                      _badge('F ${fat.toStringAsFixed(0)}g',
                          Colors.amber.shade700,
                          highlight: _sortField == SortField.fat),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Edit + Delete
            Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () => _showForm(item: item),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.edit_outlined,
                      color: _green, size: 20),
                ),
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: () =>
                    _handleDelete(item['ntt_id'], item['ntt_food_name']),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 20),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {bool highlight = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: highlight
              ? color.withOpacity(0.18)
              : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: color.withOpacity(highlight ? 0.8 : 0.3),
              width: highlight ? 1 : 0.5),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight:
                    highlight ? FontWeight.w800 : FontWeight.w600)),
      );

  // ── Category Header ───────────────────────────────────────────────────────
  Widget _buildCategoryHeader(String catName, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: _green, borderRadius: BorderRadius.circular(20)),
        child: Text(catName,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
      const SizedBox(width: 8),
      Text('$count รายการ',
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Expanded(
          child: Container(
              margin: const EdgeInsets.only(left: 10),
              height: 1, color: Colors.grey.shade200)),
    ]),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFoods;
    final grouped  = _groupedFoods;
    final hasActiveFilter =
        _sortField != SortField.calories || _sortAscending || _groupByCategory;

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
          Text('Food Database',
              style: AppTextStyles.pageTitle),
          Text('จัดการข้อมูลโภชนาการ',
              style: AppTextStyles.pageSubtitle),
        ]),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _searchVisible
                  ? Icons.search_off_rounded
                  : Icons.search_rounded,
              color: _searchVisible ? _green : Colors.grey.shade600,
              size: 22,
            ),
            onPressed: () {
              setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                } else {
                  Future.delayed(const Duration(milliseconds: 100),
                      () => _searchFocus.requestFocus());
                }
              });
            },
          ),
          Stack(clipBehavior: Clip.none, children: [
            IconButton(
              icon: Icon(Icons.tune_rounded,
                  color: hasActiveFilter ? _green : Colors.grey.shade600,
                  size: 22),
              onPressed: _showSortSheet,
            ),
            if (hasActiveFilter)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                      color: _green, shape: BoxShape.circle),
                ),
              ),
          ]),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
              height: MediaQuery.of(context).padding.top + kToolbarHeight),

          // Inline Search Bar
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _searchVisible
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาชื่ออาหาร หรือ หมวดหมู่...',
                  hintStyle:
                      const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: _green, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _green, width: 1.5),
                  ),
                ),
              ),
            ),
            secondChild: const SizedBox(height: 0),
          ),

          // Category Tabs
          _buildCategoryTabs(),
          const SizedBox(height: 2),

          // Result count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('พบ ${filtered.length} รายการ',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              if (_selectedCategoryFilter != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategoryFilter = null;
                    _groupByCategory = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('ล้าง filter',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700)),
                      const SizedBox(width: 3),
                      Icon(Icons.close,
                          size: 12, color: Colors.orange.shade700),
                    ]),
                  ),
                ),
            ]),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.search_off,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty ||
                                    _selectedCategoryFilter != null
                                ? 'ไม่พบรายการที่ค้นหา'
                                : 'ยังไม่มีข้อมูลอาหาร',
                            style: const TextStyle(color: Colors.grey)),
                        ]))
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _loadInitialData();
                        },
                        child: _groupByCategory
                            ? ListView(
                                padding:
                                    const EdgeInsets.only(bottom: 80),
                                children: grouped.entries
                                    .map((e) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildCategoryHeader(
                                                e.key, e.value.length),
                                            ...e.value
                                                .map(_buildFoodCard),
                                          ],
                                        ))
                                    .toList(),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.only(bottom: 80),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) =>
                                    _buildFoodCard(filtered[i]),
                              ),
                      ),
          ),
        ],
      ),

      floatingActionButton: AppFab(onPressed: _showForm, color: _green),
    );
  }
}
// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_NUTRITION_CATEGORIES : จัดการหมวดหมู่อาหาร (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบประเภทโภชนาการ ใช้จัดกลุ่มรายการอาหารในระบบ
// [PAGE_ROUTE] /admin > โภชนาการ > ประเภทโภชนาการ
// [USES_FEATURES] FOOD_LOG
//
// ย้ายจากแอปมือถือ (lib/views/admin/food/manage_nutrition_categories_view.dart)
// Logic CRUD/validate เหมือนเดิมทุกจุด (COPY) — layout ปรับเป็นการ์ดรูปภาพ grid 4 คอลัมน์
// แบบเดียวกับหน้าหมวดหมู่คาร์ดิโอ/กลุ่มกล้ามเนื้อ (มาตรฐานเดียวกันทั้งเว็บ) หลังเพิ่มคอลัมน์
// nttc_image (migration 2026-08-29_add_nttc_image_to_nutrition_category.sql) — ไม่มีคำอธิบาย
// เพราะ nutrition_category ไม่มีคอลัมน์ description (ตัดสินใจแล้วว่าเอาแค่รูป)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/utils/icon_fallback.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';
import 'manage_food_items_view.dart';

// เพิ่ม keyword "ของทอด"/"ข้าว"/"น้ำ" ที่ audit เจอว่าตกไปใช้ไอคอนช้อนส้อมซ้ำกับหมวดอื่น —
// ชื่อที่ยังไม่ตรง keyword ไหนเลย (เช่นชื่อภาษาอังกฤษ) ใช้ fallbackIconFor สุ่มตามชื่อแทนไอคอนเดียวตายตัว
IconData _getCategoryIcon(String catName) {
  final n = catName.toLowerCase();
  if (n.contains('ของว่าง') || n.contains('อาหารว่าง')) return Icons.cookie_outlined;
  if (n.contains('ของทอด') || n.contains('ทอด')) return Icons.brunch_dining_outlined;
  if (n.contains('กับข้าว') || n.contains('กับ')) return Icons.set_meal_outlined;
  if (n.contains('ข้าว')) return Icons.rice_bowl_outlined;
  if (n.contains('วัตถุดิบ')) return Icons.egg_alt_outlined;
  if (n.contains('ผักและผลไม้') || n.contains('ผัก')) return Icons.eco_outlined;
  if (n.contains('ผลไม้')) return Icons.apple_outlined;
  if (n.contains('ขนม')) return Icons.cake_outlined;
  if (n.contains('เครื่องดื่ม')) return Icons.local_drink_outlined;
  if (n.contains('น้ำ')) return Icons.water_drop_outlined;
  return fallbackIconFor(catName, const [
    Icons.restaurant_outlined,
    Icons.ramen_dining_outlined,
    Icons.lunch_dining_outlined,
    Icons.tapas_outlined,
    Icons.bakery_dining_outlined,
  ]);
}

// ให้แต่ละหมวดหมู่มีสี identity ต่างกัน แบบเดียวกับหน้าหมวดหมู่คาร์ดิโอ (มาตรฐานเดียวกันทั้งเว็บ)
Color _getCategoryColor(String name) {
  const colors = [
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF0277BD),
    Color(0xFF8E24AA),
    Color(0xFFC62828),
    Color(0xFF00897B),
  ];
  return colors[name.hashCode.abs() % colors.length];
}

class ManageNutritionCategoriesView extends StatefulWidget {
  const ManageNutritionCategoriesView({super.key});

  @override
  State<ManageNutritionCategoriesView> createState() => _ManageNutritionCategoriesViewState();
}

class _ManageNutritionCategoriesViewState extends State<ManageNutritionCategoriesView> {
  List<dynamic> categories = [];
  Map<int, int> _foodCounts = {};
  bool _isLoading = true;
  bool _hasError = false;
  String _search = '';
  bool _sortAscending = true;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ไม่ว่างเมื่อคลิกการ์ดดูโภชนาการในหมวดหมู่ — สลับแสดงเนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell
  int? _drillCategoryId;

  String get baseUrl => ApiClient.serverUrl;
  String get apiUrl => '${ApiClient.serverUrl}/api/nutrition/categories';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchFoodCounts();
  }

  // นับจำนวนอาหารต่อหมวดหมู่ (badge "N รายการ" บรีฟ P2 ข้อ 11) — ดึงครั้งเดียวมานับรวมในเครื่อง
  Future<void> _fetchFoodCounts() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/nutrition/foods'), headers: _authHeaders);
      if (res.statusCode != 200) return;
      final data = json.decode(utf8.decode(res.bodyBytes));
      final foods = (data['data'] as List?) ?? [];
      final counts = <int, int>{};
      for (final f in foods) {
        final catId = f['nttc_id'] ?? f['category']?['nttc_id'];
        final id = catId is int ? catId : int.tryParse(catId?.toString() ?? '');
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      if (mounted) setState(() => _foodCounts = counts);
    } catch (e) {
      debugPrint('_fetchFoodCounts error: $e');
    }
  }

  List<dynamic> get _filtered {
    List<dynamic> result = categories;
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      result = result.where((c) => (c['nttc_name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    result = List.from(result)
      ..sort((a, b) => (a['nttc_name'] ?? '').toString().compareTo((b['nttc_name'] ?? '').toString()) * (_sortAscending ? 1 : -1));
    return result;
  }

  Future<void> _fetchCategories() async {
    setState(() => _hasError = false);
    try {
      final response = await _api.get('/nutrition/categories');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          categories = data['data'];
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (e) {
      debugPrint('Fetch Error: $e');
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Future<void> _handleSave(
    Map<String, dynamic>? oldItem,
    String name, {
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
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
          Uri.parse(apiUrl),
          headers: headers,
          body: jsonEncode({"nttc_name": name.trim()}),
        );
      } else {
        final int id = oldItem['nttc_id'];
        response = await http.put(
          Uri.parse('$apiUrl/$id'),
          headers: headers,
          body: jsonEncode({"nttc_id": id, "nttc_name": name.trim()}),
        );
      }

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        // อัปโหลดรูป (ถ้าเลือกไว้) เป็นขั้นถัดไปแยกต่างหาก — endpoint สร้าง/แก้ไขหลักยังเป็น
        // JSON เหมือนเดิม (แอปมือถือยังเรียกอยู่) รูปเลยแยกไป endpoint multipart คนละตัว
        final int catId = oldItem?['nttc_id'] ?? json.decode(response.body)['data']['nttc_id'];
        if (imageBytes != null || imageFile != null) {
          await _uploadCategoryImage(catId, imageFile, imageBytes, imageFileName);
        }
        Navigator.pop(context);
        ApiClient.clearCache();
        await _fetchCategories();
        AdminDataBus.bumpNutritionCategories();
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มสำเร็จ' : 'แก้ไขสำเร็จ', type: AppAlertType.success);
      } else {
        Navigator.pop(context);
        _showSnackBar('ล้มเหลว: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _uploadCategoryImage(int catId, File? imageFile, Uint8List? imageBytes, String? imageFileName) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$apiUrl/$catId/image'));
    request.headers.addAll(_authHeaders);
    if (kIsWeb) {
      if (imageBytes != null && imageFileName != null) {
        request.files.add(http.MultipartFile.fromBytes('nttc_image', imageBytes, filename: imageFileName));
      }
    } else {
      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('nttc_image', imageFile.path));
      }
    }
    await http.Response.fromStream(await request.send());
  }

  Future<void> _handleDelete(int id, String name) async {
    _showLoadingDialog();
    int foodCount = 0;
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/nutrition/foods'), headers: _authHeaders);
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
        final response = await http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders);
        if (!mounted) return;
        Navigator.pop(context);
        if (response.statusCode == 200) {
          ApiClient.clearCache();
          _fetchCategories();
          AdminDataBus.bumpNutritionCategories();
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

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหากลับค่าเริ่มต้น — ใช้ร่วมกันทั้งปุ่ม "ล้างตัวกรอง" บน
  //               AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() => setState(() {
        _search = '';
        _currentPage = 1;
      });

  // มาตรฐานตัวกรอง ข้อ 3 (แก้ตามรีวิว 2026-08-29): หน้านี้มีมิติให้เรียงแค่ชื่อหมวดหมู่มิติเดียว —
  // ใช้ dropdown ตัวเลือกเดียวแล้วดูเหมือนใช้งานได้ทั้งที่กดแล้วไม่มีอะไรให้เลือก (สับสนกว่าเดิม)
  // เปลี่ยนเป็น label ฟิลด์เฉยๆ (ไม่ใช่ dropdown) + ปุ่มสลับทิศทางแทน — dropdown จริงเก็บไว้ใช้
  // เฉพาะหน้าที่มี ≥2 มิติให้เรียง (เช่นฐานข้อมูลโภชนาการ)
  Widget _buildSortControl() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 150,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        alignment: Alignment.centerLeft,
        child: Row(children: const [
          Icon(Icons.sort, size: 18, color: AppColors.textMuted),
          SizedBox(width: 8),
          Expanded(child: Text('เรียงตามชื่อ', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => setState(() {
          _sortAscending = !_sortAscending;
          _currentPage = 1;
        }),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primaryGreen),
          ),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: AppColors.primaryGreen),
            const SizedBox(width: 6),
            Text(_sortAscending ? 'ก-ฮ' : 'ฮ-ก', style: const TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  void _showForm({Map<String, dynamic>? item}) {
    final ctrl = TextEditingController(text: item != null ? (item['nttc_name'] ?? '').toString().trim() : '');

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    final String existingImage = (item?['nttc_image'] ?? '').toString();
    final picker = ImagePicker();

    showAdminDialog(
      context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickImage() async {
            final f = await picker.pickImage(source: ImageSource.gallery);
            if (f != null) {
              final bytes = await f.readAsBytes();
              setDialogState(() {
                selectedImageBytes = bytes;
                selectedImageName = f.name;
                if (!kIsWeb) selectedImage = File(f.path);
              });
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview = Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if (existingImage.isNotEmpty) {
            final imgUrl = ApiClient.prefixPath(existingImage);
            imagePreview = imgUrl != null
                ? AdminNetworkImage(imgUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.add_a_photo, size: 32))
                : const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item == null ? 'เพิ่มหมวดหมู่' : 'แก้ไขหมวดหมู่',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                      IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20), onPressed: () => Navigator.pop(dialogContext)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(children: [
                            GestureDetector(
                              onTap: pickImage,
                              child: ClipOval(
                                child: Container(
                                  height: 88, width: 88,
                                  color: Colors.grey[200],
                                  child: imagePreview,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('แตะวงกลมเพื่อเปลี่ยนรูปภาพ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        const Text('ชื่อหมวดหมู่ *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: ctrl,
                          decoration: InputDecoration(
                            hintText: 'เช่น อาหารหลัก, ผลไม้',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            prefixIcon: const Icon(Icons.category, color: AppColors.primaryGreen, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                          onSubmitted: (_) => _handleSave(item, ctrl.text, imageFile: selectedImage, imageBytes: selectedImageBytes, imageFileName: selectedImageName),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => _handleSave(item, ctrl.text, imageFile: selectedImage, imageBytes: selectedImageBytes, imageFileName: selectedImageName),
                            child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    if (_drillCategoryId != null) {
      return ManageFoodItemsView(
        initialCategoryId: _drillCategoryId,
        onBack: () => setState(() => _drillCategoryId = null),
      );
    }
    final allRows = _filtered;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = _isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? (_search.isNotEmpty ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['โภชนาการ', 'ประเภทโภชนาการ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มหมวดหมู่',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อหมวดหมู่...',
          onSearchChanged: (v) => setState(() {
            _search = v;
            _currentPage = 1;
          }),
          trailing: [
            _buildSortControl(),
          ],
          resultCount: allRows.length,
          showClearButton: _search.isNotEmpty,
          onClearFilters: _clearFilters,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.cards,
                  onAdd: () => _showForm(),
                  onRetry: _fetchCategories,
                  onClearFilter: _clearFilters,
                )
              // การ์ดรูปใหญ่ fixed 4 คอลัมน์ แบบเดียวกับหน้าหมวดหมู่คาร์ดิโอ/กลุ่มกล้ามเนื้อ
              // (มาตรฐานเดียวกันทั้งเว็บสำหรับหน้า "หมวดหมู่/กลุ่ม") — badge "N รายการ" + คลิกการ์ด
              // = drill-down ไปหน้าฐานข้อมูลโภชนาการที่กรองหมวดนี้แล้ว (บรีฟ P2 ข้อ 11)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    final name = (item['nttc_name'] ?? '').toString().trim();
                    final catId = item['nttc_id'] as int;
                    final count = _foodCounts[catId] ?? 0;
                    final String nttcImage = (item['nttc_image'] ?? '').toString();

                    return _NutritionCategoryCard(
                      imageUrl: nttcImage.isEmpty ? null : ApiClient.prefixPath(nttcImage),
                      icon: _getCategoryIcon(name),
                      accentColor: _getCategoryColor(name),
                      name: name,
                      foodCount: count,
                      onTap: () => setState(() => _drillCategoryId = catId),
                      onEdit: () => _showForm(item: item),
                      onDelete: () => _handleDelete(catId, name),
                    );
                  },
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

// การ์ดประเภทโภชนาการในกริด — คัดลอกทรง/interaction มาจาก _CardioCategoryCard ของหน้าหมวดหมู่
// คาร์ดิโอทุกจุด (มาตรฐานเดียวกันทั้งเว็บ) ต่างแค่ไม่มีคำอธิบาย เพราะ nutrition_category ไม่มี
// คอลัมน์ description (ตัดสินใจแล้วว่าเอาแค่รูป — ไม่แก้ schema เพิ่ม)
class _NutritionCategoryCard extends StatefulWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accentColor;
  final String name;
  final int foodCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NutritionCategoryCard({
    required this.imageUrl,
    required this.icon,
    required this.accentColor,
    required this.name,
    required this.foodCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_NutritionCategoryCard> createState() => _NutritionCategoryCardState();
}

class _NutritionCategoryCardState extends State<_NutritionCategoryCard> {
  bool _hovering = false;

  Widget _placeholderImage() {
    return Container(
      width: double.infinity,
      color: widget.accentColor.withValues(alpha: 0.12),
      child: Center(child: Icon(widget.icon, color: widget.accentColor, size: 36)),
    );
  }

  Widget _overlayButton({required IconData icon, required Color color, required VoidCallback onPressed, required String tooltip}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))]),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(icon, color: color),
        onPressed: () {
          Tooltip.dismissAllToolTips();
          onPressed();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: widget.imageUrl != null
                              ? AdminNetworkImage(widget.imageUrl!, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => _placeholderImage())
                              : _placeholderImage(),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovering ? 1 : 0,
                        child: Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.black.withValues(alpha: 0.05)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: _hovering ? 1 : 0,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            _overlayButton(icon: Icons.edit_outlined, color: AppColors.primaryGreen, onPressed: widget.onEdit, tooltip: 'แก้ไข'),
                            const SizedBox(width: 6),
                            _overlayButton(icon: Icons.delete_outline, color: Colors.redAccent, onPressed: widget.onDelete, tooltip: 'ลบ'),
                          ]),
                        ),
                      ),
                      // badge จำนวนรายการอาหาร มุมซ้ายบนของรูป — ตำแหน่ง/สไตล์เดียวกับ badge
                      // จำนวนกิจกรรมในหน้าหมวดหมู่คาร์ดิโอ/กลุ่มกล้ามเนื้อ (มาตรฐานเดียวกันทั้งเว็บ)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                          child: Text('${widget.foodCount} รายการ', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

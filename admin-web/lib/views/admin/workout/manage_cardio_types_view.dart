// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_CARDIO_TYPES : จัดการประเภทคาร์ดิโอ (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบประเภทคาร์ดิโอ ใช้จัดกลุ่มกิจกรรมคาร์ดิโอในระบบ
// [PAGE_ROUTE] /admin > คาร์ดิโอ > ประเภทคาร์ดิโอ
// [USES_FEATURES] CARDIO
//
// ย้ายจากแอปมือถือ (lib/views/admin/workout/manage_cardio_types_view.dart)
// Logic CRUD เหมือนเดิมทุกจุด (COPY) — layout เปลี่ยนเป็น AdminListHeader + DataTable

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'manage_cardio_activities_view.dart';


// เพิ่ม keyword ภาษาอังกฤษ (hiit/metcon/interval ฯลฯ) ที่ audit เจอว่าตกไปใช้ไอคอนสายฟ้าซ้ำกัน —
// ชื่อที่ยังไม่ตรง keyword ไหนเลยใช้ fallbackIconFor สุ่มตามชื่อแทนไอคอนเดียวตายตัว
IconData _getCardioIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('จักรยาน') || n.contains('ปั่น') || n.contains('cycle') || n.contains('bike')) return Icons.directions_bike_outlined;
  if (n.contains('ว่าย') || n.contains('น้ำ') || n.contains('swim')) return Icons.pool_outlined;
  if (n.contains('วิ่ง') || n.contains('run')) return Icons.directions_run_outlined;
  if (n.contains('เต้น') || n.contains('แอโรบิก') || n.contains('dance') || n.contains('aerobic')) return Icons.music_note_outlined;
  if (n.contains('เดิน') || n.contains('walk')) return Icons.directions_walk_outlined;
  if (n.contains('กีฬา') || n.contains('sport')) return Icons.sports_outlined;
  if (n.contains('หนัก') || n.contains('คาร์ดิโอ') || n.contains('hiit') || n.contains('metcon') || n.contains('interval')) return Icons.fitness_center_outlined;
  return fallbackIconFor(name, const [
    Icons.flash_on_outlined,
    Icons.bolt_outlined,
    Icons.timer_outlined,
    Icons.local_fire_department_outlined,
  ]);
}

// ให้แต่ละหมวดหมู่มีสี identity ต่างกัน (ไม่มีคอลัมน์รูปในตาราง cardio_category —
// ใช้สีแทนรูปภาพ ประเมินว่าเหมาะกับจำนวนหมวดหมู่ที่มีน้อยและคงที่)
Color _getCardioColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('จักรยาน') || n.contains('ปั่น') || n.contains('cycle') || n.contains('bike')) return const Color(0xFF2E7D32);
  if (n.contains('ว่าย') || n.contains('น้ำ') || n.contains('swim')) return const Color(0xFF0277BD);
  if (n.contains('วิ่ง') || n.contains('run')) return const Color(0xFFEF6C00);
  if (n.contains('เต้น') || n.contains('แอโรบิก') || n.contains('dance') || n.contains('aerobic')) return const Color(0xFF8E24AA);
  if (n.contains('เดิน') || n.contains('walk')) return const Color(0xFF00897B);
  if (n.contains('กีฬา') || n.contains('sport')) return const Color(0xFFC62828);
  if (n.contains('หนัก') || n.contains('คาร์ดิโอ') || n.contains('hiit') || n.contains('metcon') || n.contains('interval')) return const Color(0xFFD84315);
  const fallbackColors = [
    Color(0xFF2E7D32),
    Color(0xFF0277BD),
    Color(0xFFEF6C00),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
  ];
  return fallbackColors[name.hashCode.abs() % fallbackColors.length];
}

class ManageCardioTypesView extends StatefulWidget {
  const ManageCardioTypesView({super.key});

  @override
  State<ManageCardioTypesView> createState() => _ManageCardioTypesViewState();
}

class _ManageCardioTypesViewState extends State<ManageCardioTypesView> {
  List<dynamic> categories = [];
  Map<int, int> _activityCounts = {};
  bool isLoading = true;
  bool _hasError = false;
  String _search = '';
  bool _sortAscending = false;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ไม่ว่างเมื่อคลิกการ์ดดูกิจกรรมในหมวดหมู่ — สลับแสดงเนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell
  int? _drillCatId;

  String get baseUrl => ApiClient.serverUrl;
  String get apiUrl => '${ApiClient.serverUrl}/api/exercises/cardio-categories';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    _fetchActivityCounts();
  }

  // นับจำนวนกิจกรรมคาร์ดิโอที่ผูกกับแต่ละหมวดหมู่ (badge "N กิจกรรม" แบบเดียวกับหน้ากลุ่ม
  // กล้ามเนื้อ) — ดึงกิจกรรมทั้งหมดมานับรวมในเครื่องครั้งเดียว แทนยิง API แยกทีละหมวด
  Future<void> _fetchActivityCounts() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/exercises/cardio'), headers: _authHeaders);
      if (response.statusCode != 200) return;
      final decoded = json.decode(response.body);
      final list = (decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) : decoded) as List;
      final counts = <int, int>{};
      for (final item in list) {
        final catId = item['cdc_id'];
        final id = catId is int ? catId : int.tryParse(catId?.toString() ?? '');
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      if (mounted) setState(() => _activityCounts = counts);
    } catch (e) {
      debugPrint('_fetchActivityCounts error: $e');
    }
  }

  List<dynamic> get _filtered {
    List<dynamic> result = categories;
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      result = result.where((c) => (c['cdc_name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    result = List.from(result)
      ..sort((a, b) {
        final ca = _activityCounts[a['cdc_id']] ?? 0;
        final cb = _activityCounts[b['cdc_id']] ?? 0;
        return ca.compareTo(cb) * (_sortAscending ? 1 : -1);
      });
    return result;
  }

  Future<void> _fetchCategories() async {
    setState(() => _hasError = false);
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: _authHeaders);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        setState(() {
          categories = list;
          isLoading = false;
        });
      } else {
        setState(() { _hasError = true; isLoading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _hasError = true; isLoading = false; });
      debugPrint("fetchCategories exception: $e");
    }
  }

  Future<void> _handleDelete(int id, String name) async {
    _showLoadingDialog();
    int itemCount = 0;
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/exercises/cardio'), headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final items = (data is Map ? (data['data'] ?? data['items'] ?? data['result'] ?? []) : data) as List;
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
        content: 'หมวดหมู่ "$name" ยังมีกิจกรรมคาร์ดิโออยู่ $itemCount รายการ\n\nกรุณาลบหรือย้ายกิจกรรมคาร์ดิโอออกก่อน',
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
          _fetchCategories();
          AdminDataBus.bumpCardioCategories();
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

  Future<void> _handleSave(
    Map<String, dynamic>? oldItem,
    String name,
    String description, {
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
  }) async {
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        // อัปโหลดรูป (ถ้าเลือกไว้) เป็นขั้นถัดไปแยกต่างหาก — endpoint สร้าง/แก้ไขหลักยังเป็น
        // JSON เหมือนเดิม (แอปมือถือยังเรียกอยู่) รูปเลยแยกไป endpoint multipart คนละตัว
        final int catId = oldItem?['cdc_id'] ?? json.decode(response.body)['data']['cdc_id'];
        if (imageBytes != null || imageFile != null) {
          await _uploadCategoryImage(catId, imageFile, imageBytes, imageFileName);
        }
        Navigator.pop(context);
        await _fetchCategories();
        AdminDataBus.bumpCardioCategories();
        if (!mounted) return;
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มสำเร็จ' : 'แก้ไขสำเร็จ', type: AppAlertType.success);
      } else {
        Navigator.pop(context);
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _uploadCategoryImage(int catId, File? imageFile, Uint8List? imageBytes, String? imageFileName) async {
    final request = http.MultipartRequest('PUT', Uri.parse('$apiUrl/$catId/image'));
    request.headers.addAll(_authHeaders);
    if (kIsWeb) {
      if (imageBytes != null && imageFileName != null) {
        request.files.add(http.MultipartFile.fromBytes('cdc_image', imageBytes, filename: imageFileName));
      }
    } else {
      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('cdc_image', imageFile.path));
      }
    }
    await http.Response.fromStream(await request.send());
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
  // [FEATURE] CARDIO
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

  // มาตรฐานตัวกรอง ข้อ 3 (แก้ตามรีวิว 2026-08-29): หน้านี้มีมิติให้เรียงแค่จำนวนกิจกรรมมิติเดียว —
  // ใช้ dropdown ตัวเลือกเดียวแล้วดูเหมือนใช้งานได้ทั้งที่กดแล้วไม่มีอะไรให้เลือก (สับสนกว่าเดิม)
  // เปลี่ยนเป็น label ฟิลด์เฉยๆ (ไม่ใช่ dropdown) + ปุ่มสลับทิศทางแทน — dropdown จริงเก็บไว้ใช้
  // เฉพาะหน้าที่มี ≥2 มิติให้เรียง (เช่นฐานข้อมูลโภชนาการ)
  Widget _buildSortControl() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 170,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        alignment: Alignment.centerLeft,
        child: Row(children: const [
          Icon(Icons.sort, size: 18, color: AppColors.textMuted),
          SizedBox(width: 8),
          Expanded(child: Text('เรียงตามจำนวนกิจกรรม', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted), overflow: TextOverflow.ellipsis)),
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
            Text(_sortAscending ? 'น้อย → มาก' : 'มาก → น้อย', style: const TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['cdc_name'] ?? '');
    final descCtrl = TextEditingController(text: item?['cdc_description'] ?? '');

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    final String existingImage = (item?['cdc_image'] ?? '').toString();
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
            imagePreview = Image.memory(selectedImageBytes!, width: double.infinity, height: double.infinity, fit: BoxFit.cover);
          } else if (existingImage.isNotEmpty) {
            final imgUrl = ApiClient.prefixPath(existingImage);
            imagePreview = imgUrl != null
                ? SizedBox.expand(child: AdminNetworkImage(imgUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.add_a_photo, size: 32)))
                : const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 32, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: SizedBox(
              width: 460,
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
                        child: Text(item == null ? 'เพิ่มประเภทคาร์ดิโอ' : 'แก้ไขประเภทคาร์ดิโอ',
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
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            hintText: 'เช่น วิ่ง, ว่ายน้ำ, ปั่นจักรยาน',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            prefixIcon: const Icon(Icons.flash_on_outlined, color: AppColors.primaryGreen, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text('คำอธิบาย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: descCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'รายละเอียดประเภทคาร์ดิโอ (ไม่บังคับ)',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => _handleSave(
                              item,
                              nameCtrl.text,
                              descCtrl.text,
                              imageFile: selectedImage,
                              imageBytes: selectedImageBytes,
                              imageFileName: selectedImageName,
                            ),
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
    if (_drillCatId != null) {
      return ManageCardioActivitiesView(
        initialCatId: _drillCatId,
        onBack: () => setState(() => _drillCatId = null),
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
                ? (_search.isNotEmpty ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['คาร์ดิโอ', 'ประเภทคาร์ดิโอ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มประเภทคาร์ดิโอ',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อประเภทคาร์ดิโอ...',
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
              // การ์ดรูปใหญ่ fixed 4 คอลัมน์ แบบเดียวกับหน้ากลุ่มกล้ามเนื้อ (มาตรฐานเดียวกันทั้งเว็บ
              // สำหรับหน้า "หมวดหมู่/กลุ่ม" ที่เน้นรูปภาพ)
              : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.92,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        final int catId = item['cdc_id'];
                        final name = (item['cdc_name'] ?? '').toString();
                        final desc = (item['cdc_description'] ?? '').toString();
                        final String cdcImage = (item['cdc_image'] ?? '').toString();

                        return _CardioCategoryCard(
                          imageUrl: cdcImage.isEmpty ? null : ApiClient.prefixPath(cdcImage),
                          icon: _getCardioIcon(name),
                          accentColor: _getCardioColor(name),
                          name: name,
                          description: desc,
                          activityCount: _activityCounts[catId] ?? 0,
                          onTap: () => setState(() => _drillCatId = catId),
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

// การ์ดประเภทคาร์ดิโอในกริด — คัดลอกทรง/interaction มาจาก _MuscleGroupCard ของหน้ากลุ่ม
// กล้ามเนื้อทุกจุด (มาตรฐานเดียวกันทั้งเว็บสำหรับหน้า "หมวดหมู่" ที่เน้นรูปภาพ) ต่างแค่ fallback
// ตอนยังไม่มีรูป ใช้ไอคอน+สี identity ของหมวดหมู่แทนไอคอนเทายืนเดียวของกลุ่มกล้ามเนื้อ เพราะ
// cardio_category เพิ่งมีคอลัมน์รูป หมวดเก่าส่วนใหญ่ยังไม่มีรูปอัปโหลด
class _CardioCategoryCard extends StatefulWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accentColor;
  final String name;
  final String description;
  final int activityCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CardioCategoryCard({
    required this.imageUrl,
    required this.icon,
    required this.accentColor,
    required this.name,
    required this.description,
    required this.activityCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CardioCategoryCard> createState() => _CardioCategoryCardState();
}

class _CardioCategoryCardState extends State<_CardioCategoryCard> {
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
                      // badge จำนวนกิจกรรม มุมซ้ายบนของรูป — ตำแหน่งเดียวกับ badge METs ในหน้า
                      // กิจกรรมคาร์ดิโอ (มาตรฐานเดียวกันทั้งเว็บ ให้จำแพทเทิร์นได้ทันทีว่าคือตัวเลขสรุป)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                          child: Text('${widget.activityCount} กิจกรรม', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (widget.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(widget.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textBody)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

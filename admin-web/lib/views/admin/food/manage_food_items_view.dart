// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_FOOD_ITEMS : จัดการรายการอาหาร (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบข้อมูลอาหาร รวมถึงแคลอรี่ สารอาหาร และรูปภาพอาหาร
// [PAGE_ROUTE] /admin > โภชนาการ > ฐานข้อมูลโภชนาการ
// [USES_FEATURES] FOOD_LOG
//
// ย้ายจากแอปมือถือ (lib/views/admin/food/manage_food_items_view.dart)
// Logic CRUD/validate/upload รูปเหมือนเดิมทุกจุด (COPY) — layout: AppBar+FAB มือถือ +
// sort bottom sheet -> AdminListHeader + DataTable ที่คลิกหัวคอลัมน์เพื่อเรียงได้ตรงๆ
// (ธรรมชาติของเว็บ ไม่ต้องเปิด sheet แยกเหมือนมือถือ) + แถบหมวดหมู่กรองด้านบนตาราง

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/utils/api_error.dart';
import '../../../core/utils/bulk_selection.dart';
import '../../../core/utils/duplicate_name_check.dart';
import '../../../core/widgets/admin_breadcrumb.dart';
import '../../../core/widgets/admin_bulk_action_bar.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_loading_guard.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';

// หน่วยนับที่ใช้จริงในฐานข้อมูล (กรัม = อาหารแข็ง, ออนซ์ = เครื่องดื่ม) — ล็อกเป็น dropdown
// กันพิมพ์เพี้ยน/สะกดไม่ตรงกัน (บรีฟ UX รอบ 2 ข้อ 2) ไม่เพิ่ม/ลบหน่วยเองโดยไม่ถาม
const _kFoodUnits = ['กรัม', 'ออนซ์'];

class _FormState {
  int? selectedCatId;
  String selectedUnit;
  File? selectedImage;
  Uint8List? selectedImageBytes;
  String? selectedImageName;
  _FormState({this.selectedCatId, this.selectedUnit = 'กรัม'});
}

enum SortField { calories, protein, carbs, fat }


class ManageFoodItemsView extends StatefulWidget {
  // เปิดจากการคลิกการ์ดประเภทโภชนาการ (drill-down, บรีฟ P2 ข้อ 11) — พรีเซ็ตตัวกรองหมวดหมู่
  // ให้ทันที; null = เปิดจากเมนู sidebar ปกติ ไม่ล็อกตัวกรอง
  final int? initialCategoryId;
  final VoidCallback? onBack;
  const ManageFoodItemsView({super.key, this.initialCategoryId, this.onBack});
  @override
  State<ManageFoodItemsView> createState() => _ManageFoodItemsViewState();
}

class _ManageFoodItemsViewState extends State<ManageFoodItemsView> {
  List<dynamic> foods = [];
  List<dynamic> categories = [];
  bool _isLoading = true;
  bool _hasError = false;

  String _searchQuery = '';
  int _sortColumnIndex = 2; // 0=ชื่อ 1=หมวดหมู่ 2=kcal 3=P 4=C 5=F
  bool _sortAscending = false;
  late int? _selectedCategoryFilter = widget.initialCategoryId;
  int _pageSize = kAdminPageSizeOptions[1];
  int _total = 0;
  bool _isNetworkError = false;

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _selection / _nameCache (bulk action state)
  // [DESCRIPTION] state ของโหมด multi-select — ดูรายละเอียดที่ bulk_selection.dart (COMMON_UI)
  //               _nameCache เก็บชื่ออาหารตาม id ที่เคยโหลดผ่านหน้าไหนก็ได้ (สะสมข้าม pagination)
  //               ใช้แสดงตัวอย่างชื่อในกล่องยืนยันลบแม้รายการที่เลือกไว้จะมาจากคนละหน้า
  //
  //               พักฟีเจอร์นี้ไว้ก่อน (ตัดสินใจ 2026-08-30: ยังไม่จำเป็นกับขนาดข้อมูล/ความถี่การใช้
  //               งานจริงตอนนี้) โค้ดทั้งหมดเก็บไว้ครบ ปิดผ่านจุดเข้าเดียว _kBulkSelectEnabled — เปิด
  //               กลับมาใช้แค่เปลี่ยน false เป็น true (ไม่ต้องแก้ที่อื่น)
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  static const bool _kBulkSelectEnabled = false;
  final BulkSelection _selection = BulkSelection();
  final Map<int, String> _nameCache = {};
  bool _bulkBusy = false;

  // ยกเลิก request เก่าที่ยังไม่ตอบกลับก่อนยิงใหม่ทุกครั้ง (ค้นหา/เปลี่ยนหน้า/เปลี่ยนตัวกรอง)
  // กัน response เก่ามาทีหลัง response ใหม่แล้วทับผลลัพธ์ผิด (มาตรฐานตัวกรอง Flutter integration ข้อ 2)
  CancelToken? _cancelToken;

  // ชื่อประเภทโภชนาการที่กำลังกรองอยู่ (สำหรับ AdminBreadcrumb ตอน drill-down) — ผูกกับ
  // _selectedCategoryFilter/categories ที่มีอยู่แล้ว ไม่สร้าง state ใหม่
  String? get _selectedCategoryName {
    for (final c in categories) {
      if (c['nttc_id'] == _selectedCategoryFilter) return c['nttc_name']?.toString();
    }
    return null;
  }

  // ลายเซ็นของตัวกรองปัจจุบัน — ใช้เทียบว่ารายการที่เลือกไว้ (bulk action) ยังอยู่ในตัวกรอง
  // เดียวกับตอนที่เลือกไหม (ดู BulkSelection.markFilterChanged)
  String get _filterSignature =>
      '$_searchQuery|$_selectedCategoryFilter|${_kcalFilterActive ? '${_kcalRange.start}-${_kcalRange.end}' : ''}';

  int _currentPage = 1;
  // ค่าเริ่มต้นเป็นตาราง (บรีฟ P2 ข้อ 8) — เหมาะกับงานแก้ไขข้อมูลจำนวนมาก (119+ รายการ) มากกว่า
  // การ์ดรูปใหญ่ที่ต้อง scroll หนัก สลับกลับไปดูการ์ดได้จากปุ่มมุมมองข้าง dropdown เรียงลำดับ
  bool _isTableView = false;

  static const _sortKeys = ['name', 'category', 'kcal', 'protein', 'carbs', 'fat'];

  // ตัวกรองช่วงแคลอรี่ (บรีฟ P2 ข้อ 8) — 800+ ปลายเปิด กันรายการพลังงานสูงหลุดขอบสไลเดอร์
  static const _kcalFilterMax = 800.0;
  bool _showKcalFilter = false;
  bool _kcalFilterActive = false;
  RangeValues _kcalRange = const RangeValues(0, _kcalFilterMax);
  Timer? _kcalDebounce;

  @override
  void dispose() {
    _kcalDebounce?.cancel();
    _cancelToken?.cancel('disposed');
    AdminDataBus.nutritionCategories.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  String get baseUrl => ApiClient.serverUrl;
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  String _buildImageUrl(String path) => ApiClient.prefixPath(path) ?? '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    AdminDataBus.nutritionCategories.addListener(_onCategoriesChanged);
  }

  // หน้านี้ถูก cache ค้างไว้ใน IndexedStack ของ admin_shell_view ไม่ได้ rebuild ตอนสลับเมนู —
  // ฟัง AdminDataBus แทน เพื่อรู้ตัวทันทีเวลาหน้าหมวดหมู่ (คนละหน้า คนละ state) เพิ่ม/แก้/ลบสำเร็จ
  Future<void> _onCategoriesChanged() async {
    if (!mounted) return;
    await _fetchCategories();
    if (!mounted) return;
    final filterStillValid = categories.any((c) => c['nttc_id'] == _selectedCategoryFilter);
    if (_selectedCategoryFilter != null && !filterStillValid) {
      setState(() => _selectedCategoryFilter = null);
      _fetchFoods();
    } else {
      setState(() {});
    }
  }

  String _getCatName(dynamic item) {
    if (item['category']?['nttc_name'] != null) return item['category']['nttc_name'];
    final cat = categories.firstWhere((c) => c['nttc_id'] == item['nttc_id'], orElse: () => null);
    return cat?['nttc_name'] ?? 'ไม่มีหมวดหมู่';
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _isNetworkError = false;
    });
    await Future.wait([_fetchCategories(), _fetchFoods()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchCategories() async {
    try {
      final res = await _api.get('/nutrition/categories');
      if (res.statusCode == 200) {
        final data = res.data;
        categories = data['data'] ?? [];
      } else {
        if (mounted) setState(() => _hasError = true);
      }
    } catch (e) {
      debugPrint("Fetch Categories Error: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _fetchFoods
  // [DESCRIPTION] ดึงรายการโภชนาการอาหารจาก GET /api/admin/nutrition/foods ตามตัวกรอง+เรียง+
  //               หน้าปัจจุบัน (server-side search+filter+sort+pagination แทนการโหลดทั้งหมดมา
  //               กรองใน Dart แบบเดิม) ยกเลิก request ก่อนหน้านี้ที่ยังไม่ตอบกลับก่อนยิงใหม่เสมอ
  // [INPUT] _searchQuery, _selectedCategoryFilter, _kcalFilterActive/_kcalRange,
  //         _sortColumnIndex/_sortAscending, _currentPage, _pageSize (state ปัจจุบันของหน้า)
  // [OUTPUT] อัปเดต foods/_total หรือ _hasError/_isNetworkError ตามผลลัพธ์
  // [RELATED] COMMON_UI
  // --------------------------------------------
  // พารามิเตอร์ตัวกรอง (ไม่รวมเรียง/หน้า) — ใช้ร่วมกันทั้ง _fetchFoods (แบ่งหน้า) และ
  // _fetchAllIdsForCurrentFilter (ปุ่ม "เลือกทั้งหมด" ของ bulk action ที่ต้องครอบทุกหน้า)
  Map<String, String> _buildFilterParams() => {
        if (_searchQuery.trim().isNotEmpty) 'search': _searchQuery.trim(),
        if (_selectedCategoryFilter != null) 'category_id': '$_selectedCategoryFilter',
        if (_kcalFilterActive) 'kcal_min': _kcalRange.start.round().toString(),
        if (_kcalFilterActive && _kcalRange.end < _kcalFilterMax) 'kcal_max': _kcalRange.end.round().toString(),
      };

  Future<void> _fetchFoods() async {
    _selection.markFilterChanged(_filterSignature);
    _cancelToken?.cancel('superseded');
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _isNetworkError = false;
    });

    final params = <String, String>{
      ..._buildFilterParams(),
      'sort_by': _sortKeys[_sortColumnIndex],
      'sort_order': _sortAscending ? 'asc' : 'desc',
      'page': '$_currentPage',
      'page_size': '$_pageSize',
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    try {
      final res = await _api.get('/admin/nutrition/foods?$query', cancelToken: token);
      if (!mounted || token.isCancelled) return;
      if (res.statusCode == 200) {
        final data = res.data as Map;
        setState(() {
          foods = (data['data'] ?? []) as List;
          _total = (data['total'] as num?)?.toInt() ?? 0;
          _isLoading = false;
          for (final f in foods) {
            final id = f['ntt_id'];
            if (id != null) _nameCache[id as int] = (f['ntt_food_name'] ?? '').toString();
          }
        });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return; // ถูก request ใหม่กว่าแทนที่ ไม่ต้องทำอะไร
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isNetworkError = isNetworkDioError(e);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Fetch Foods Error: $e");
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _enterSelectMode / _exitSelectMode / _toggleSelect / _handleLongPress
  // [DESCRIPTION] เข้า/ออกโหมดเลือกหลายรายการ — เข้าได้ทั้งกดปุ่ม "เลือก" บน toolbar (ไม่เลือกอะไร
  //               ทันที) หรือกดค้างที่แถว/การ์ด (เข้าโหมด + เลือกแถวนั้นเลย) ออกจากโหมด (ปุ่ม X/Esc)
  //               ล้างรายการที่เลือกทั้งหมดเสมอ (ข้อกำหนด UX ข้อ 1)
  // [INPUT] id ของแถว/การ์ดที่กดค้าง (เฉพาะ _handleLongPress)
  // [OUTPUT] setState เปลี่ยน _selection
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _enterSelectMode() => setState(() => _selection.enter());

  void _exitSelectMode() => setState(() => _selection.exitAndClear());

  void _toggleSelect(int id) => setState(() => _selection.toggle(id, _filterSignature));

  void _handleLongPress(int id) => setState(() {
        _selection.enter();
        _selection.toggle(id, _filterSignature);
      });

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _fetchAllIdsForCurrentFilter
  // [DESCRIPTION] ดึง id ทั้งหมดที่ตรงตัวกรองปัจจุบัน (ครอบทุกหน้า) จาก GET .../foods/ids —
  //               ใช้ตอนกดปุ่ม "เลือกทั้งหมด N รายการที่แสดงอยู่" (ข้อกำหนด UX ข้อ 2 — ต้องหมายถึง
  //               เฉพาะรายการที่ผ่านตัวกรองปัจจุบันเท่านั้น ไม่ใช่ทั้งฐานข้อมูล)
  // [INPUT] ตัวกรองปัจจุบัน (_buildFilterParams)
  // [OUTPUT] List<int> ของ id ทั้งหมดที่ตรงตัวกรอง หรือ [] ถ้าดึงไม่สำเร็จ
  // [RELATED] FOOD_LOG
  // --------------------------------------------
  Future<List<int>> _fetchAllIdsForCurrentFilter() async {
    final params = _buildFilterParams();
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    try {
      final res = await _api.get('/admin/nutrition/foods/ids${query.isEmpty ? '' : '?$query'}');
      if (res.statusCode == 200) {
        final data = res.data as Map;
        return (data['ids'] as List).map((e) => (e as num).toInt()).toList();
      }
    } catch (e) {
      debugPrint('Fetch food ids error: $e');
    }
    return [];
  }

  // ประมาณ "เลือกทั้งหมดแล้ว" จากจำนวนที่เลือก เทียบกับจำนวนที่ตรงตัวกรองปัจจุบัน (_total) — พอสำหรับ
  // สลับข้อความปุ่ม ไม่ต้องยิง /ids ทุกครั้งที่ build (ยิงจริงเฉพาะตอนกดปุ่มเท่านั้น ดู _handleSelectAllToggle)
  bool get _allSelectedForFilter => _total > 0 && _selection.count >= _total;

  Future<void> _handleSelectAllToggle() async {
    setState(() => _bulkBusy = true);
    final ids = await _fetchAllIdsForCurrentFilter();
    if (!mounted) return;
    setState(() {
      if (_allSelectedForFilter) {
        _selection.deselectAllForCurrentFilter(ids);
      } else {
        _selection.selectAllForCurrentFilter(ids, _filterSignature);
      }
      _bulkBusy = false;
    });
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _confirmBulkDelete / _runBulkDelete
  // [DESCRIPTION] ยืนยันก่อนลบหลายรายการ (แสดงชื่อตัวอย่าง 3-5 รายการแรก + "และอีก N รายการ" —
  //               ข้อกำหนด UX ข้อ 5) แล้วยิง POST bulk-delete ทีเดียว ฝั่ง backend ลบทีละรายการ
  //               ไม่ใช้ transaction all-or-nothing (ข้าม FK แทนล้มทั้งชุด) รายการที่ลบไม่สำเร็จ
  //               (ติด FK) ยังคงถูกเลือกอยู่ต่อ ให้ผู้ใช้จัดการต่อได้ทันที (ข้อกำหนด FK ข้อ 4)
  // [INPUT] _selection.ids
  // [OUTPUT] เรียก API, อัปเดต _selection/foods, แสดงสรุปผลลัพธ์
  // [RELATED] FOOD_LOG
  // --------------------------------------------
  Future<void> _confirmBulkDelete() async {
    final ids = _selection.ids.toList();
    if (ids.isEmpty) return;

    final names = ids.map((id) => _nameCache[id]).whereType<String>().toList();
    final preview = names.take(5).toList();
    final remaining = ids.length - preview.length;
    final content = preview.isEmpty
        ? 'ต้องการลบ ${ids.length} รายการที่เลือกไว้ใช่หรือไม่?'
        : 'ต้องการลบ "${preview.join('", "')}"${remaining > 0 ? ' และอีก $remaining รายการ' : ''} ใช่หรือไม่?';

    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ ${ids.length} รายการ?',
      content: content,
      confirmLabel: 'ลบข้อมูล',
    );
    if (!confirm) return;
    await _runBulkDelete(ids);
  }

  Future<void> _runBulkDelete(List<int> ids) async {
    Response? res;
    Object? error;
    await runWithGuardedLoading(
      context: context,
      task: () async {
        try {
          res = await _api.post('/admin/nutrition/foods/bulk-delete', {'ids': ids});
        } catch (e) {
          error = e;
        }
      },
    );
    if (!mounted) return;
    if (error != null) {
      _showSnackBar('Error: $error');
      return;
    }
    if (res!.statusCode != 200) {
      _showSnackBar('ลบไม่สำเร็จ: ${res!.statusCode}');
      return;
    }

    final data = res!.data as Map;
    final succeeded = (data['succeeded'] as List?) ?? [];
    final failed = (data['failed'] as List?) ?? [];

    setState(() {
      _selection.removeAll(succeeded.map((e) => (e['id'] as num).toInt()));
    });
    ApiClient.clearCache();
    await _fetchFoods();
    if (!mounted) return;
    _showBulkResultSummary(succeeded: succeeded, failed: failed, actionLabel: 'ลบ');
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _showBulkResultSummary
  // [DESCRIPTION] สรุปผลหลังทำ bulk action เสร็จ — สำเร็จกี่รายการ/ไม่สำเร็จรายการไหนพร้อมเหตุผล
  //               ภาษาไทยที่ผู้ใช้เข้าใจ (backend แปลไว้แล้ว เช่น "มีสมาชิกใช้บันทึกอยู่ 12 ครั้ง")
  //               ไม่โชว์ error ดิบจากฐานข้อมูล (ข้อกำหนด FK ข้อ 3) — ถ้าไม่มีรายการล้มเหลวเลย
  //               ใช้แค่ toast สั้นๆ พอ ไม่ต้องเปิด dialog
  // [INPUT] succeeded/failed (จาก response ของ bulk-delete หรือ bulk-move-category), actionLabel
  // [OUTPUT] dialog สรุปผล หรือ toast (ถ้าไม่มีรายการล้มเหลว)
  // [RELATED] FOOD_LOG
  // --------------------------------------------
  Future<void> _showBulkResultSummary({required List succeeded, required List failed, required String actionLabel}) async {
    if (failed.isEmpty) {
      if (mounted) showAdminTopToast(context, '$actionLabelสำเร็จ ${succeeded.length} รายการ');
      return;
    }
    await showAdminDialog(
      context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ผลลัพธ์การ$actionLabel', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'สำเร็จ ${succeeded.length} รายการ · ไม่สำเร็จ ${failed.length} รายการ',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: failed.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final item = failed[i] as Map;
                      final name = (item['name'] ?? '').toString();
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isEmpty ? 'รายการ #${item['id']}' : name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text(item['reason']?.toString() ?? '', style: const TextStyle(fontSize: 12.5, color: AppColors.textBody)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('รับทราบ')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _confirmBulkMoveCategory / _runBulkMoveCategory
  // [DESCRIPTION] ย้ายประเภทโภชนาการของรายการที่เลือกไว้ทั้งหมดไปหมวดเดียวกัน มี snackbar ปุ่ม
  //               "เลิกทำ" ให้ย้อนกลับได้ (ข้อกำหนด UX ข้อ 6) — Undo เรียก endpoint เดิมซ้ำ โดยย้าย
  //               แต่ละรายการกลับไปหมวดเดิมของตัวเอง (old_nttc_id ที่ backend ส่งกลับมาตอนสำเร็จ)
  // [INPUT] _selection.ids, หมวดหมู่ปลายทางที่เลือกจาก dialog
  // [OUTPUT] เรียก API, อัปเดต _selection/foods, แสดง snackbar/สรุปผล
  // [RELATED] FOOD_LOG
  // --------------------------------------------
  Future<int?> _pickCategoryDialog() {
    int? chosen = categories.isNotEmpty ? categories.first['nttc_id'] as int : null;
    return showAdminDialog<int>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) => AlertDialog(
          title: const Text('ย้ายไปหมวดหมู่'),
          content: DropdownButtonFormField<int>(
            initialValue: chosen,
            items: categories.map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(value: c['nttc_id'] as int, child: Text(c['nttc_name'] ?? ''))).toList(),
            onChanged: (v) => setModalState(() => chosen = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('ยกเลิก')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx2, chosen), child: const Text('ย้าย')),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBulkMoveCategory() async {
    if (_selection.isEmpty) return;
    final targetId = await _pickCategoryDialog();
    if (targetId == null || !mounted) return;
    final updates = _selection.ids.map((id) => {'id': id, 'nttc_id': targetId}).toList();
    await _runBulkMoveCategory(updates, isUndo: false);
  }

  Future<void> _runBulkMoveCategory(List<Map<String, dynamic>> updates, {required bool isUndo}) async {
    Response? res;
    Object? error;
    await runWithGuardedLoading(
      context: context,
      task: () async {
        try {
          res = await _api.put('/admin/nutrition/foods/bulk-move-category', {'updates': updates});
        } catch (e) {
          error = e;
        }
      },
    );
    if (!mounted) return;
    if (error != null) {
      _showSnackBar('Error: $error');
      return;
    }
    if (res!.statusCode != 200) {
      _showSnackBar('ย้ายหมวดหมู่ไม่สำเร็จ: ${res!.statusCode}');
      return;
    }

    final data = res!.data as Map;
    final succeeded = (data['succeeded'] as List?) ?? [];
    final failed = (data['failed'] as List?) ?? [];

    setState(() {
      _selection.removeAll(succeeded.map((e) => (e['id'] as num).toInt()));
    });
    ApiClient.clearCache();
    await _fetchFoods();
    if (!mounted) return;

    if (failed.isNotEmpty) {
      await _showBulkResultSummary(succeeded: succeeded, failed: failed, actionLabel: 'ย้ายหมวดหมู่');
      if (!mounted) return;
    }
    if (succeeded.isEmpty) return;

    if (isUndo) {
      showAdminTopToast(context, 'เลิกทำสำเร็จ');
      return;
    }
    final undoUpdates = succeeded
        .map((e) => {'id': (e as Map)['id'], 'nttc_id': e['old_nttc_id']})
        .toList();
    showAppAlert(
      context,
      'ย้ายหมวดหมู่สำเร็จ ${succeeded.length} รายการ',
      type: AppAlertType.success,
      actionLabel: 'เลิกทำ',
      onAction: () => _runBulkMoveCategory(List<Map<String, dynamic>>.from(undoUpdates), isUndo: true),
    );
  }

  // --------------------------------------------
  // [FEATURE] FOOD_LOG
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหาและตัวกรองเสริมทั้งหมด (หมวดหมู่ + ช่วงแคลอรี่) กลับค่าเริ่มต้น —
  //               ใช้ร่วมกันทั้งปุ่ม "ล้างตัวกรอง" บน AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() {
    _kcalDebounce?.cancel();
    setState(() {
      _searchQuery = '';
      _selectedCategoryFilter = null;
      _kcalRange = const RangeValues(0, _kcalFilterMax);
      _kcalFilterActive = false;
      _currentPage = 1;
    });
    _fetchFoods();
  }

  Future<void> _handleDelete(int id, String name) async {
    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      http.Response? res;
      Object? error;
      await runWithGuardedLoading(
        context: context,
        task: () async {
          try {
            res = await http.delete(Uri.parse('$baseUrl/api/nutrition/foods/$id'), headers: _authHeaders);
          } catch (e) {
            error = e;
          }
        },
      );
      if (!mounted) return;
      if (error != null) {
        _showSnackBar('Error: $error');
        return;
      }
      if (res!.statusCode == 200) {
        ApiClient.clearCache();
        await _fetchFoods();
        if (!mounted) return;
        showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
      } else {
        _showSnackBar('ลบไม่สำเร็จ: ${res!.statusCode}');
      }
    }
  }

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
    // เช็คชื่อซ้ำจริงทำที่ฟอร์ม (เช็คสด ครอบทั้งระบบผ่าน API ไม่ใช่แค่หน้าปัจจุบัน — ดู _showForm)
    // ตรงนี้เหลือแค่ unique constraint ฝั่ง backend เป็นด่านสุดท้าย (ดู error handling ท้ายฟังก์ชัน)

    if (calories.trim().isEmpty || protein.trim().isEmpty || carbs.trim().isEmpty || fat.trim().isEmpty) {
      _showSnackBar('กรุณากรอกค่าแคลอรี่และสารอาหารให้ครบ', type: AppAlertType.warning);
      return;
    }

    final parsedCalories = double.tryParse(calories) ?? 0;
    final parsedProtein = double.tryParse(protein) ?? 0;
    final parsedCarbs = double.tryParse(carbs) ?? 0;
    final parsedFat = double.tryParse(fat) ?? 0;
    final parsedServingWeight = double.tryParse(servingWeight) ?? 100;
    if (parsedCalories < 0 || parsedProtein < 0 || parsedCarbs < 0 || parsedFat < 0 || parsedServingWeight <= 0) {
      _showSnackBar('ค่าแคลอรี่/สารอาหาร/น้ำหนักต้องไม่ติดลบ', type: AppAlertType.warning);
      return;
    }
    if (parsedCalories == 0 && parsedProtein == 0 && parsedCarbs == 0 && parsedFat == 0) {
      _showSnackBar('ค่าแคลอรี่และสารอาหารต้องไม่เป็น 0 ทั้งหมด', type: AppAlertType.warning);
      return;
    }

    // ตรวจสอบว่า kcal ที่กรอกสอดคล้องกับ P/C/F ไหม (P,C = 4 kcal/g, F = 9 kcal/g ตามบทที่ 2)
    // เตือนเฉยๆ ไม่บล็อก เผื่อ admin ตั้งใจกรอกค่าจากแหล่งข้อมูลอื่นที่ปัดเศษต่างไป
    final expectedCalories = parsedProtein * 4 + parsedCarbs * 4 + parsedFat * 9;
    if (expectedCalories > 0) {
      final diffRatio = (parsedCalories - expectedCalories).abs() / expectedCalories;
      if (diffRatio > 0.10) {
        final proceed = await showAppConfirmDialog(
          context,
          icon: Icons.warning_amber_rounded,
          title: 'ค่าพลังงานไม่ตรงกับสารอาหาร',
          content: 'จาก P/C/F ที่กรอก ควรมีพลังงานประมาณ ${expectedCalories.toStringAsFixed(0)} kcal '
              'แต่กรอกไว้ ${parsedCalories.toStringAsFixed(0)} kcal (ต่างกันเกิน 10%)\nต้องการบันทึกต่อหรือไม่?',
          confirmLabel: 'บันทึกต่อ',
          cancelLabel: 'กลับไปแก้ไข',
          color: AppColors.alertWarning,
        );
        if (!proceed) return;
      }
    }

    final isEdit = oldItem != null;
    http.Response? response;
    Object? error;
    await runWithGuardedLoading(
      context: context,
      task: () async {
        try {
          final url = isEdit ? '$baseUrl/api/nutrition/foods/${oldItem['ntt_id']}' : '$baseUrl/api/nutrition/foods';
          var request = http.MultipartRequest(isEdit ? 'PUT' : 'POST', Uri.parse(url));
          request.headers.addAll(_authHeaders);
          request.fields['ntt_food_name'] = name;
          request.fields['nttc_id'] = catId.toString();
          request.fields['ntt_calories'] = parsedCalories.toString();
          request.fields['ntt_protein'] = parsedProtein.toString();
          request.fields['ntt_carbs'] = parsedCarbs.toString();
          request.fields['ntt_fat'] = parsedFat.toString();
          request.fields['ntt_serving_weight'] = parsedServingWeight.toString();
          request.fields['ntt_unit'] = unit.isEmpty ? 'กรัม' : unit;

          if (kIsWeb) {
            if (imageBytes != null && imageFileName != null) {
              request.files.add(http.MultipartFile.fromBytes('ntt_food_image', imageBytes, filename: imageFileName));
            }
          } else {
            if (imageFile != null) {
              request.files.add(await http.MultipartFile.fromPath('ntt_food_image', imageFile.path));
            }
          }

          final streamedResponse = await request.send();
          response = await http.Response.fromStream(streamedResponse);
        } catch (e) {
          error = e;
        }
      },
    );
    if (!mounted) return;
    if (error != null) {
      _showSnackBar('Error: $error');
      return;
    }
    if (response!.statusCode == 200 || response!.statusCode == 201) {
      ApiClient.clearCache();
      await _fetchFoods();
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar(isEdit ? 'แก้ไขข้อมูลสำเร็จ' : 'เพิ่มข้อมูลสำเร็จ', type: AppAlertType.success);
    } else {
      // backend แปล unique constraint error เป็นข้อความไทยที่เข้าใจง่ายไว้แล้ว (เช่น "มีอาหารชื่อ
      // นี้อยู่แล้ว" ตอน 409) เดิมโค้ดนี้ทิ้งข้อความนั้นไปโชว์แค่ status code แทน — ดึง response.body
      // มาใช้ ถ้า parse ไม่ได้ค่อย fallback เป็นข้อความ status code เดิม
      String msg = 'ไม่สามารถบันทึกได้ (${response!.statusCode})';
      try {
        final body = json.decode(response!.body);
        if (body is Map && body['error'] != null) msg = body['error'].toString();
      } catch (_) {}
      _showSnackBar(msg);
    }
  }

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['ntt_food_name'] ?? '');
    final proteinCtrl = TextEditingController(text: item?['ntt_protein']?.toString() ?? '');
    final carbCtrl = TextEditingController(text: item?['ntt_carbs']?.toString() ?? '');
    final fatCtrl = TextEditingController(text: item?['ntt_fat']?.toString() ?? '');
    final calCtrl = TextEditingController(text: item?['ntt_calories']?.toString() ?? '');
    final servingCtrl = TextEditingController(text: item?['ntt_serving_weight']?.toString() ?? '100');

    // เช็คชื่อซ้ำครอบทั้งระบบสด — debounce 400ms เหมือนช่องค้นหา + cancel request เก่าตอนพิมพ์ต่อ
    // (มาตรฐานตัวกรอง Flutter integration ข้อ 2) ห้าม block ปุ่มบันทึกถ้าเช็คไม่สำเร็จ (network/
    // server error) ให้ unique constraint ฝั่ง backend เป็นด่านสุดท้ายแทน (ดู _handleSave)
    Timer? nameCheckDebounce;
    CancelToken? nameCheckToken;
    bool isDuplicateName = false;
    bool dialogClosed = false;

    final bool isAdding = item == null;
    final int? lockedCatId = isAdding ? _selectedCategoryFilter : null;
    final bool showCatSelector = lockedCatId == null;

    final existingUnit = (item?['ntt_unit'] ?? 'กรัม').toString();
    final fs = _FormState(
      selectedCatId: lockedCatId ?? item?['nttc_id'] ?? (categories.isNotEmpty ? categories.first['nttc_id'] : null),
      selectedUnit: existingUnit,
    );
    // เผื่อข้อมูลเก่ามีหน่วยแปลกที่ไม่อยู่ใน list มาตรฐาน — โชว์ไว้เป็นตัวเลือกเพิ่ม ไม่บังคับเปลี่ยนให้เงียบๆ
    final unitOptions = _kFoodUnits.contains(existingUnit) ? _kFoodUnits : [..._kFoodUnits, existingUnit];
    final picker = ImagePicker();

    showAdminDialog(
      context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // --------------------------------------------
          // [FEATURE] FOOD_LOG
          // [FUNCTION] _showForm (checkNameDuplicate — เช็คชื่อซ้ำสดครอบทั้งระบบ)
          // [DESCRIPTION] เรียก checkExactNameDuplicate ผ่าน endpoint ค้นหาเดิม (ไม่สร้างใหม่)
          //               debounce 400ms + cancel request เก่าทุกครั้งที่พิมพ์ต่อ ไม่นับซ้ำกับ
          //               รายการที่กำลังแก้ไขอยู่เอง (excludeId)
          // [INPUT] ชื่อที่พิมพ์ในช่องชื่ออาหาร, item?['ntt_id'] (ตอนแก้ไข)
          // [OUTPUT] setModalState อัปเดต isDuplicateName ให้ปุ่มบันทึก disable + โชว์ข้อความเตือน
          // [RELATED] COMMON_UI
          // --------------------------------------------
          void checkNameDuplicate(String value) {
            nameCheckDebounce?.cancel();
            nameCheckDebounce = Timer(const Duration(milliseconds: 400), () async {
              nameCheckToken?.cancel('superseded');
              final token = CancelToken();
              nameCheckToken = token;
              try {
                final dup = await checkExactNameDuplicate(
                  api: _api,
                  path: '/admin/nutrition/foods',
                  nameField: 'ntt_food_name',
                  idField: 'ntt_id',
                  name: value,
                  excludeId: item?['ntt_id'],
                  cancelToken: token,
                );
                if (dialogClosed) return;
                setModalState(() => isDuplicateName = dup);
              } on DioException catch (e) {
                if (e.type != DioExceptionType.cancel && !dialogClosed) {
                  setModalState(() => isDuplicateName = false);
                }
              }
            });
          }

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
          } else if (item?['ntt_food_image'] != null && item?['ntt_food_image'] != "") {
            imagePreview = AdminNetworkImage(_buildImageUrl(item!['ntt_food_image']), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.add_a_photo, size: 40));
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            child: Container(
              width: 520,
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
                      Expanded(child: Text(item == null ? 'เพิ่มรายการอาหาร' : 'แก้ไขรายการอาหาร', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))),
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
                              child: Stack(children: [
                                Container(height: 100, width: 100, decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200, width: 2)), clipBehavior: Clip.hardEdge, child: imagePreview),
                                Positioned(bottom: 2, right: 2, child: Container(padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14))),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Center(child: Text('แตะวงกลมเพื่อเปลี่ยนรูปภาพ', style: TextStyle(color: Colors.grey, fontSize: 11))),
                          const SizedBox(height: 16),
                          const Text('ชื่ออาหาร *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            onChanged: checkNameDuplicate,
                            decoration: InputDecoration(
                              hintText: 'เช่น ข้าวผัด, สลัดผัก...',
                              prefixIcon: const Icon(Icons.restaurant_menu, color: AppColors.primaryGreen, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          if (isDuplicateName) ...[
                            const SizedBox(height: 4),
                            const Text('มีชื่ออาหารนี้ในระบบแล้ว กรุณาใช้ชื่ออื่น', style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: 10),
                          const Text('หมวดหมู่ *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          if (showCatSelector)
                            DropdownButtonFormField<int>(
                              initialValue: fs.selectedCatId,
                              items: categories.map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(value: c['nttc_id'] as int, child: Text(c['nttc_name'] ?? '', style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setModalState(() => fs.selectedCatId = v),
                              decoration: InputDecoration(prefixIcon: const Icon(Icons.category, color: AppColors.primaryGreen, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3))),
                              child: Row(children: [
                                const Icon(Icons.category, color: AppColors.primaryGreen, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(categories.firstWhere((c) => c['nttc_id'] == fs.selectedCatId, orElse: () => {'nttc_name': ''})['nttc_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen))),
                              ]),
                            ),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: _nutriField(ctrl: proteinCtrl, label: 'โปรตีน (g) *', color: Colors.blue, icon: Icons.fitness_center)),
                            const SizedBox(width: 6),
                            Expanded(child: _nutriField(ctrl: carbCtrl, label: 'คาร์โบไฮเดรต (g) *', color: Colors.purple, icon: Icons.grain)),
                            const SizedBox(width: 6),
                            Expanded(child: _nutriField(ctrl: fatCtrl, label: 'ไขมัน (g) *', color: Colors.orange, icon: Icons.water_drop)),
                          ]),
                          const SizedBox(height: 16),
                          const Text('พลังงาน (kcal) *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(controller: calCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'เช่น 200', prefixIcon: const Icon(Icons.local_fire_department, color: Colors.orange, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12))),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('ขนาดต่อหน่วย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              TextField(controller: servingCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'เช่น 100', prefixIcon: const Icon(Icons.scale, color: Colors.teal, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12))),
                            ])),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('หน่วย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: fs.selectedUnit,
                                isExpanded: true,
                                decoration: InputDecoration(prefixIcon: const Icon(Icons.straighten, color: Colors.teal, size: 18), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                                items: unitOptions.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) => setModalState(() => fs.selectedUnit = v!),
                              ),
                            ])),
                          ]),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: isDuplicateName ? null : () => _handleSave(item, nameCtrl.text, fs.selectedCatId, proteinCtrl.text, carbCtrl.text, fatCtrl.text, calCtrl.text, servingCtrl.text, fs.selectedUnit, fs.selectedImage, fs.selectedImageBytes, fs.selectedImageName),
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
    ).then((_) {
      // ปิด dialog แล้ว (ปุ่ม X/แตะ backdrop/บันทึกสำเร็จ) — ยกเลิก debounce/request เช็คชื่อซ้ำ
      // ที่ค้างอยู่ กัน setModalState เรียกซ้ำหลัง StatefulBuilder ถูก dispose ไปแล้ว
      dialogClosed = true;
      nameCheckDebounce?.cancel();
      nameCheckToken?.cancel('dialog closed');
    });
  }

  Widget _nutriField({required TextEditingController ctrl, required String label, required Color color, required IconData icon}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '0', prefixIcon: Icon(icon, color: color, size: 16), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6)),
          ),
        ],
      );

  // Dropdown หมวดหมู่ — กลับมาใช้ dropdown แทน chip (ตัดสินใจแล้ว 2026-08-29: ประเภทโภชนาการ
  // มีจำนวนมากกว่าหมวดคาร์ดิโอ/กลุ่มกล้ามเนื้อ เรียงเป็น chip แถวยาวเกินไป ไม่เหมาะกับจำนวนหมวดนี้)
  Widget _buildCategoryDropdown() {
    final allCategories = <Map<String, dynamic>>[
      {'nttc_id': null, 'nttc_name': 'ทั้งหมด'},
      ...categories.map((c) => Map<String, dynamic>.from(c)),
    ];
    // ระหว่างโหลด categories ยังไม่มาถึง แต่ _selectedCategoryFilter อาจถูกพรีเซ็ตไว้แล้ว
    // (เช่นเปิดจากการ์ด drill-down) — ถ้า id นั้นยังไม่อยู่ใน items ให้ fallback เป็น null
    // กัน DropdownButtonFormField assert พังตอน initialValue ไม่ match รายการไหนเลย
    final validCatIds = allCategories.map((c) => c['nttc_id'] as int?).toSet();
    final safeInitialValue = validCatIds.contains(_selectedCategoryFilter) ? _selectedCategoryFilter : null;

    return SizedBox(
      width: 220,
      height: 40,
      child: DropdownButtonFormField<int?>(
        key: ValueKey('cat_filter_${categories.length}'),
        initialValue: safeInitialValue,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: const Icon(Icons.category_outlined, size: 18, color: AppColors.primaryGreen),
        ),
        items: allCategories.map((cat) {
          final catId = cat['nttc_id'] as int?;
          final catName = cat['nttc_name'] ?? '';
          return DropdownMenuItem<int?>(value: catId, child: Text(catName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)));
        }).toList(),
        onChanged: (v) {
          setState(() {
            _selectedCategoryFilter = v;
            _currentPage = 1;
            // มีตัวกรองหมวดหมู่แล้ว "เรียงตามหมวดหมู่" ไม่มีผลอะไรให้เห็น (ทุกแถวหมวดเดียวกันหมด) —
            // ตัวเลือกนี้จะถูกซ่อนไปเลย (ดู _buildSortControl) เลยต้อง fallback ออกจากมันด้วย
            // กันค่าที่เลือกไว้ค้างเป็น index ที่ไม่มีใน dropdown แล้ว (assert พังแบบเดียวกับ #2)
            if (v != null && _sortColumnIndex == 1) _sortColumnIndex = 2;
          });
          _fetchFoods();
        },
      ),
    );
  }

  static const _sortLabels = ['ชื่อ', 'หมวดหมู่', 'kcal', 'โปรตีน', 'คาร์โบไฮเดรต', 'ไขมัน'];

  // การ์ดกริดไม่มีหัวตารางให้คลิกสลับเรียงเหมือน DataTable เดิม ย้ายมาเป็น dropdown เลือก field
  // (มีหลายมิติให้เรียง ไม่เหมือนหน้าอื่นที่เรียงมิติเดียว) + ปุ่มสลับทิศทางสไตล์ pill เขียว
  // ให้ตรงกับ chip ตัวกรอง/ปุ่มสลับทิศทางหน้าอื่น (มาตรฐานเดียวกันทั้งเว็บ)
  Widget _buildSortControl() {
    // เลือกหมวดหมู่ไว้แล้ว (filter) ซ่อน "เรียงตามหมวดหมู่" ออกจากตัวเลือก — ไม่ให้สองตัวกรอง
    // มาชนกันแบบดูเหมือนใช้งานได้แต่ไม่มีผลจริง (ทุกแถวที่กรองมาเป็นหมวดเดียวกันหมดอยู่แล้ว)
    final availableIndices = [
      for (int i = 0; i < _sortLabels.length; i++)
        if (i != 1 || _selectedCategoryFilter == null) i,
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 150,
        height: 40,
        child: DropdownButtonFormField<int>(
          key: ValueKey('sort_control_${_selectedCategoryFilter == null}'),
          initialValue: _sortColumnIndex,
          isDense: true,
          isExpanded: true,
          decoration: const InputDecoration(
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            prefixIcon: Icon(Icons.sort, size: 18, color: AppColors.textMuted),
          ),
          items: [
            for (final i in availableIndices)
              DropdownMenuItem(value: i, child: Text('เรียงตาม${_sortLabels[i]}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          ],
          onChanged: (v) {
            setState(() {
              _sortColumnIndex = v ?? 2;
              _currentPage = 1;
            });
            _fetchFoods();
          },
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () {
          setState(() {
            _sortAscending = !_sortAscending;
            _currentPage = 1;
          });
          _fetchFoods();
        },
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

  // สลับมุมมองตาราง/การ์ด (บรีฟ P2 ข้อ 8) — ตารางเหมาะงานแก้ข้อมูลจำนวนมาก การ์ดเหมาะดูภาพรวมรูปอาหาร
  Widget _buildViewToggle() {
    Widget btn(IconData icon, bool selected, VoidCallback onTap, String tooltip) => Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryGreen.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: selected ? AppColors.primaryGreen : AppColors.textMuted),
            ),
          ),
        );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.grid_view_outlined, !_isTableView, () => setState(() => _isTableView = false), 'มุมมองการ์ด'),
        btn(Icons.table_rows_outlined, _isTableView, () => setState(() => _isTableView = true), 'มุมมองตาราง'),
      ]),
    );
  }

  String get _kcalRangeLabel {
    final end = _kcalRange.end >= _kcalFilterMax ? '${_kcalFilterMax.toStringAsFixed(0)}+' : _kcalRange.end.toStringAsFixed(0);
    return '${_kcalRange.start.toStringAsFixed(0)}-$end kcal';
  }

  // ปุ่มเปิด/ปิดแผงตัวกรองช่วงแคลอรี่ (บรีฟ P2 ข้อ 8) — ไฮไลต์เขียวเมื่อมีการกรองจริง (ไม่ใช่แค่เปิดแผงดู)
  Widget _buildKcalFilterToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showKcalFilter = !_showKcalFilter),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _kcalFilterActive ? AppColors.primaryGreen.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kcalFilterActive ? AppColors.primaryGreen : Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.tune, size: 16, color: _kcalFilterActive ? AppColors.primaryGreen : AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            _kcalFilterActive ? _kcalRangeLabel : 'ช่วงแคลอรี่ (kcal)',
            style: TextStyle(fontSize: 12.5, color: _kcalFilterActive ? AppColors.primaryGreen : AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }

  Widget _buildKcalFilterPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          const Text('ช่วงแคลอรี่ (kcal):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(_kcalRange.start.toStringAsFixed(0), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Expanded(
            child: RangeSlider(
              min: 0,
              max: _kcalFilterMax,
              divisions: 16,
              values: _kcalRange,
              activeColor: AppColors.primaryGreen,
              labels: RangeLabels(_kcalRange.start.toStringAsFixed(0), _kcalRange.end >= _kcalFilterMax ? '${_kcalFilterMax.toStringAsFixed(0)}+' : _kcalRange.end.toStringAsFixed(0)),
              // ลากระหว่างทาง: อัปเดตแค่ตำแหน่ง slider/label ทันที ไม่กระทบรายการที่กรอง (ไม่ debounce)
              // ปล่อยนิ้ว/เมาส์: ค่อย debounce สั้นๆ ก่อนใช้กรองจริง กัน re-filter รัวๆ ระหว่างลาก
              onChanged: (v) => setState(() => _kcalRange = v),
              onChangeEnd: (v) {
                _kcalDebounce?.cancel();
                _kcalDebounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) {
                    setState(() {
                      _kcalFilterActive = v.start > 0 || v.end < _kcalFilterMax;
                      _currentPage = 1;
                    });
                    _fetchFoods();
                  }
                });
              },
            ),
          ),
          Text(_kcalRange.end >= _kcalFilterMax ? '${_kcalFilterMax.toStringAsFixed(0)}+' : _kcalRange.end.toStringAsFixed(0), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () {
              _kcalDebounce?.cancel();
              setState(() {
                _kcalRange = const RangeValues(0, _kcalFilterMax);
                _kcalFilterActive = false;
                _currentPage = 1;
              });
              _fetchFoods();
            },
            child: const Text('รีเซ็ต'),
          ),
        ]),
      ),
    );
  }

  Widget _imageOverlayButton({required IconData icon, required Color color, required VoidCallback onPressed, required String tooltip}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))]),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        icon: Icon(icon, color: color),
        onPressed: () {
          // ปิด tooltip ค้างก่อนเปิด dialog — ไม่งั้น hover ปุ่มแล้วเด้ง dialog ทับ
          // pointer-exit ไม่ยิง ทำให้ tooltip ค้างอยู่หลังปิด dialog (Flutter web hover bug)
          Tooltip.dismissAllToolTips();
          onPressed();
        },
      ),
    );
  }

  Widget _macroBadge(String label, double value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color, width: 0.5)),
        child: Text('$label ${value.toStringAsFixed(0)}g', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  // badge หมวดหมู่บนการ์ด — แบบเดียวกับ _smallBadge ของหน้ากิจกรรมคาร์ดิโอ (มาตรฐานเดียวกันทั้งเว็บ)
  // แทนข้อความเปล่าที่ปนกับหน่วยบริโภคจนแยกไม่ออกว่าอันไหนคือหมวดหมู่
  Widget _smallBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color, width: 0.5)),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  // การ์ดแนวตั้งภาพใหญ่ (บรีฟรอบ 3 ข้อ 7.2) — สไตล์เดียวกับท่าฝึกเวท (ข้อ 3.2) ให้ดูรู้ทันทีว่าเป็นอาหารอะไร
  Widget _buildFoodCard(Map<String, dynamic> item) {
    final id = item['ntt_id'] as int;
    final catName = _getCatName(item);
    final imgPath = item['ntt_food_image'] as String?;
    final calories = (item['ntt_calories'] as num?)?.toDouble() ?? 0;
    final protein = (item['ntt_protein'] as num?)?.toDouble() ?? 0;
    final carbs = (item['ntt_carbs'] as num?)?.toDouble() ?? 0;
    final fat = (item['ntt_fat'] as num?)?.toDouble() ?? 0;
    final serving = item['ntt_serving_weight'];
    final unit = item['ntt_unit'] ?? 'กรัม';
    final name = (item['ntt_food_name'] ?? '').toString();
    final selected = _selection.contains(id);

    // hover state ของปุ่มแก้ไข/ลบ — ตัวแปรอยู่นอก StatefulBuilder.builder ให้จำค่าข้ามการ hover
    // แต่ละครั้งได้ (ตรงกับ pattern เดียวกับหน้ากลุ่มกล้ามเนื้อ/หมวดคาร์ดิโอ/กิจกรรมคาร์ดิโอ/ท่าฝึกเวท)
    bool hovering = false;
    // [FEATURE] FOOD_LOG — เข้าโหมดเลือกด้วยกดค้าง (long-press) ที่การ์ด, โหมดเลือกอยู่แล้วให้แตะ
    // ธรรมดาก็ toggle ได้เลย (ไม่ต้องกดค้างซ้ำทุกรายการ) ขอบเขียว = ถูกเลือกอยู่
    return GestureDetector(
      onLongPress: _kBulkSelectEnabled ? () => _handleLongPress(id) : null,
      onTap: (_kBulkSelectEnabled && _selection.isActive) ? () => _toggleSelect(id) : null,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: selected ? Border.all(color: AppColors.primaryGreen, width: 2) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatefulBuilder(builder: (context, setLocalState) {
            return MouseRegion(
              onEnter: (_) => setLocalState(() => hovering = true),
              onExit: (_) => setLocalState(() => hovering = false),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: AspectRatio(
                      aspectRatio: 1.4,
                      child: Container(
                        color: AppColors.calorieBadgeBg,
                        child: (imgPath != null && imgPath.isNotEmpty)
                            ? AdminNetworkImage(_buildImageUrl(imgPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 40))
                            : const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 40),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: hovering ? 1 : 0,
                    child: Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), color: Colors.black.withValues(alpha: 0.05)),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8, right: 8,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: hovering ? 1 : 0,
                      child: Row(children: [
                        _imageOverlayButton(icon: Icons.edit_outlined, color: AppColors.primaryGreen, onPressed: () => _showForm(item: item), tooltip: 'แก้ไข'),
                        const SizedBox(width: 6),
                        _imageOverlayButton(icon: Icons.delete_outline, color: Colors.redAccent, onPressed: () => _handleDelete(item['ntt_id'], item['ntt_food_name']), tooltip: 'ลบ'),
                      ]),
                    ),
                  ),
                  Positioned(
                    bottom: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                      child: Text('${calories.toStringAsFixed(0)} kcal', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (_selection.isActive)
                    Positioned(
                      top: 8, left: 8,
                      child: GestureDetector(
                        onTap: () => _toggleSelect(id),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)]),
                          child: Checkbox(value: selected, onChanged: (_) => _toggleSelect(id), activeColor: AppColors.primaryGreen, visualDensity: VisualDensity.compact),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('$serving $unit ต่อหน่วย', style: const TextStyle(fontSize: 12, color: AppColors.textBody)),
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  _smallBadge(catName.isEmpty ? 'ไม่มีหมวดหมู่' : catName, AppColors.textMuted),
                  _macroBadge('P', protein, Colors.blue),
                  _macroBadge('C', carbs, Colors.purple),
                  _macroBadge('F', fat, Colors.orange),
                ]),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // มุมมองตาราง (บรีฟ P2 ข้อ 8) — รูปย่อ/ชื่อ/หมวด/หน่วยบริโภค/kcal/P/C/F/จัดการ เห็นได้ทีละ ~20 แถว
  // ต่อจอ เหมาะงานเทียบค่าโภชนาการหลายรายการมากกว่าการ์ดรูปใหญ่ที่ต้อง scroll หนัก
  // คอลัมน์ชื่อ/หมวดหมู่ยืด-หดตามพื้นที่จอจริงเสมอ (สัดส่วน 60/40 ของพื้นที่ที่เหลือ) แบบเดียวกับ
  // ตารางกิจกรรมคาร์ดิโอ/ท่าฝึกเวท (มาตรฐานเดียวกันทั้งเว็บ) แทน fixed width เดิมที่เหลือพื้นที่ว่าง
  // โล่งด้านขวาตอนจอกว้าง — กว้างไม่พอ (ต่ำกว่า min) fallback ไปเปิด scroll แนวนอนของ AdminDataTable เอง
  static const double _thumbW = 56;
  static const double _servingW = 110;
  static const double _kcalW = 70;
  static const double _macroW = 52;
  static const double _actionW = 88;
  static const double _nameMin = 180, _catMin = 130;
  // คอลัมน์ checkbox ของโหมด multi-select — โผล่เฉพาะตอน _selection.isActive เท่านั้น (ข้อกำหนด
  // UX ข้อ 1) ไม่ต้องแก้ AdminDataTable กลาง เพราะ AdminDataColumn/AdminDataCell ยืดหยุ่นพอให้เพิ่ม
  // คอลัมน์เองจากฝั่งหน้าได้อยู่แล้ว
  static const double _checkW = 44;

  Widget _buildFoodTable(List<dynamic> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool selecting = _kBulkSelectEnabled && _selection.isActive;
        const double reserve = 8;
        final double checkboxTotal = selecting ? _checkW : 0;
        final double fixedTotal = checkboxTotal + _thumbW + _servingW + _kcalW + _macroW * 3 + _actionW + reserve;
        final double flexAvailable = constraints.maxWidth - fixedTotal;
        final double minFlexTotal = _nameMin + _catMin;
        final double flexTotal = flexAvailable < minFlexTotal ? minFlexTotal : flexAvailable;
        final double nameW = (flexTotal * 0.6) < _nameMin ? _nameMin : flexTotal * 0.6;
        final double catWRaw = flexTotal - nameW;
        final double catW = catWRaw < _catMin ? _catMin : catWRaw;

        final columns = [
          if (selecting) AdminDataColumn(key: 'check', label: '', width: _checkW),
          AdminDataColumn(key: 'thumb', label: '', width: _thumbW),
          AdminDataColumn(key: 'name', label: 'ชื่ออาหาร', width: nameW, sortable: true),
          AdminDataColumn(key: 'category', label: 'หมวดหมู่', width: catW, sortable: true),
          AdminDataColumn(key: 'serving', label: 'หน่วยบริโภค', width: _servingW),
          AdminDataColumn(key: 'kcal', label: 'kcal', width: _kcalW, numeric: true, sortable: true),
          AdminDataColumn(key: 'protein', label: 'P', width: _macroW, numeric: true, sortable: true),
          AdminDataColumn(key: 'carbs', label: 'C', width: _macroW, numeric: true, sortable: true),
          AdminDataColumn(key: 'fat', label: 'F', width: _macroW, numeric: true, sortable: true),
        ];

        return AdminDataTable(
          columns: columns,
          rowCount: rows.length,
          actionColumnWidth: _actionW,
          rowHeight: 60,
          sortKey: _sortKeys[_sortColumnIndex],
          sortAscending: _sortAscending,
          onSort: (key) {
            setState(() {
              final idx = _sortKeys.indexOf(key);
              if (_sortColumnIndex == idx) {
                _sortAscending = !_sortAscending;
              } else {
                _sortColumnIndex = idx;
                _sortAscending = true;
              }
              _currentPage = 1;
            });
            _fetchFoods();
          },
          cellsBuilder: (context, index) {
            final item = rows[index];
            final id = item['ntt_id'] as int;
            final imgPath = item['ntt_food_image'] as String?;
            final calories = (item['ntt_calories'] as num?)?.toDouble() ?? 0;
            final protein = (item['ntt_protein'] as num?)?.toDouble() ?? 0;
            final carbs = (item['ntt_carbs'] as num?)?.toDouble() ?? 0;
            final fat = (item['ntt_fat'] as num?)?.toDouble() ?? 0;
            final serving = item['ntt_serving_weight'];
            final unit = item['ntt_unit'] ?? 'กรัม';
            final name = (item['ntt_food_name'] ?? '').toString();

            return GestureDetector(
              onLongPress: _kBulkSelectEnabled ? () => _handleLongPress(id) : null,
              onTap: selecting ? () => _toggleSelect(id) : null,
              child: Row(children: [
              if (selecting)
                AdminDataCell(
                  width: _checkW,
                  child: Checkbox(
                    value: _selection.contains(id),
                    onChanged: (_) => _toggleSelect(id),
                    activeColor: AppColors.primaryGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              AdminDataCell(
                width: _thumbW,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36, height: 36,
                    color: AppColors.calorieBadgeBg,
                    child: (imgPath != null && imgPath.isNotEmpty)
                        ? AdminNetworkImage(_buildImageUrl(imgPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 18))
                        : const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 18),
                  ),
                ),
              ),
              AdminDataCell(width: nameW, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
              AdminDataCell(width: catW, child: Text(_getCatName(item), maxLines: 1, overflow: TextOverflow.ellipsis)),
              AdminDataCell(width: _servingW, child: Text('$serving $unit', style: const TextStyle(fontSize: 12.5, color: AppColors.textBody))),
              AdminDataCell(width: _kcalW, numeric: true, child: Text(calories.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w600))),
              AdminDataCell(width: _macroW, numeric: true, child: Text(protein.toStringAsFixed(0), style: const TextStyle(color: Colors.blue))),
              AdminDataCell(width: _macroW, numeric: true, child: Text(carbs.toStringAsFixed(0), style: const TextStyle(color: Colors.purple))),
              AdminDataCell(width: _macroW, numeric: true, child: Text(fat.toStringAsFixed(0), style: const TextStyle(color: Colors.orange))),
              ]),
            );
          },
          actionsBuilder: (context, index) {
            final item = rows[index];
            return Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'แก้ไข',
                icon: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 18),
                onPressed: () {
                  Tooltip.dismissAllToolTips();
                  _showForm(item: item);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                onPressed: () {
                  Tooltip.dismissAllToolTips();
                  _handleDelete(item['ntt_id'], item['ntt_food_name']);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ]);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = foods;

    final AdminListState? stateOverride = _isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : _total == 0
                ? (_searchQuery.isNotEmpty || _selectedCategoryFilter != null || _kcalFilterActive ? AdminListState.noResult : AdminListState.empty)
                : null;

    // เปิดจากการ์ดประเภทโภชนาการ = แสดงเนื้อหาแทนที่อยู่ในสล็อตเดิมของ sidebar shell (ไม่ push
    // route ใหม่ — sidebar ยังอยู่ตลอด) initialCategoryId == null = เปิดจาก sidebar เมนูปกติ
    final bool isDrillDown = widget.initialCategoryId != null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          leading: isDrillDown ? AppBackButton(onTap: widget.onBack) : null,
          breadcrumb: const ['โภชนาการ', 'โภชนาการ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มรายการอาหาร',
          trailingActions: [
            if (_kBulkSelectEnabled && !_selection.isActive)
              OutlinedButton.icon(
                onPressed: _enterSelectMode,
                icon: const Icon(Icons.checklist_rtl, size: 18),
                label: const Text('เลือก'),
              ),
          ],
        ),
        // --------------------------------------------
        // [FEATURE] FOOD_LOG
        // [FUNCTION] AdminBreadcrumb (ใช้งานใน ManageFoodItemsView)
        // [DESCRIPTION] แสดง "ประเภทโภชนาการ › ชื่อหมู่ที่คลิกเข้ามา" เฉพาะตอน drill-down
        //               จากการ์ดประเภทโภชนาการ กดที่ root กลับไปหน้าประเภทโภชนาการ
        // [INPUT] isDrillDown, _selectedCategoryName, widget.onBack
        // [OUTPUT] แถบ breadcrumb เหนือแถบค้นหา/ตัวกรอง
        // [RELATED] COMMON_UI
        // --------------------------------------------
        if (isDrillDown)
          AdminBreadcrumb(
            rootLabel: 'ประเภทโภชนาการ',
            currentLabel: _selectedCategoryName,
            onRootTap: widget.onBack,
          ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่ออาหาร หรือ หมวดหมู่...',
          onSearchChanged: (v) {
            setState(() {
              _searchQuery = v;
              _currentPage = 1;
            });
            _fetchFoods();
          },
          trailing: [
            _buildCategoryDropdown(),
            _buildKcalFilterToggle(),
            // เดิมซ่อนตอนมุมมองตาราง (ใช้ sortable header แทน) แต่ header กับ dropdown นี้ผูก
            // _sortColumnIndex/_sortAscending ตัวเดียวกันอยู่แล้ว โชว์คู่กันได้ทั้งสองมุมมอง
            // (มาตรฐาน P3 ข้อ 1 — sort ต้อง sync และแสดง dropdown เสมอ)
            _buildSortControl(),
          ],
          viewToggle: _buildViewToggle(),
          resultCount: _total,
          showClearButton: _searchQuery.isNotEmpty || _selectedCategoryFilter != null || _kcalFilterActive,
          onClearFilters: _clearFilters,
        ),
        if (_showKcalFilter) _buildKcalFilterPanel(),
        if (stateOverride == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Text('P = โปรตีน · C = คาร์โบไฮเดรต · F = ไขมัน (กรัม ต่อหน่วยบริโภค)', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: _isTableView ? AdminSkeletonVariant.table : AdminSkeletonVariant.cards,
                  errorMessage: _isNetworkError ? 'เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่' : 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์ ลองใหม่อีกครั้ง',
                  onAdd: () => _showForm(),
                  onRetry: _loadInitialData,
                  onClearFilter: _clearFilters,
                )
              : _isTableView
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _buildFoodTable(rows),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
                        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: rows.map((item) => SizedBox(width: width, child: _buildFoodCard(item))).toList(),
                        );
                      }),
                    ),
        ),
        if (stateOverride == null)
          AdminPaginationBar(
            totalItems: _total,
            pageSize: _pageSize,
            currentPage: _currentPage,
            onPageSizeChanged: (v) {
              setState(() {
                _pageSize = v;
                _currentPage = 1;
              });
              _fetchFoods();
            },
            onPageChanged: (v) {
              setState(() => _currentPage = v);
              _fetchFoods();
            },
          ),
      ],
    );

    // --------------------------------------------
    // [FEATURE] FOOD_LOG
    // [FUNCTION] build (ปุ่ม Esc + แถบลอย AdminBulkActionBar ของโหมด multi-select)
    // [DESCRIPTION] ปุ่ม Esc ออกจากโหมดเลือก + ล้างรายการที่เลือกทั้งหมด (ข้อกำหนด UX ข้อ 1 คู่กับ
    //               ปุ่ม X บน AdminBulkActionBar) แถบลอยติดขอบล่างแสดงเมื่ออยู่ในโหมดเลือกเท่านั้น
    //               ปุ่ม "ย้ายหมวดหมู่" ส่งผ่าน middleActions ส่วนปุ่มลบสีแดงแยกออกในตัว widget เอง
    //               (ข้อกำหนด UX ข้อ 3 — กันกดพลาด)
    // [INPUT] _selection
    // [OUTPUT] Stack ทับแถบลอยไว้เหนือเนื้อหาเดิม
    // [RELATED] COMMON_UI
    // --------------------------------------------
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            if (_selection.isActive) _exitSelectMode();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          canRequestFocus: false,
          descendantsAreFocusable: true,
          child: Stack(
            children: [
              content,
              if (_selection.isActive)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AdminBulkActionBar(
                    selectedCount: _selection.count,
                    totalForCurrentFilter: _total,
                    allSelectedForCurrentFilter: _allSelectedForFilter,
                    hasSelectionOutsideFilter: _selection.hasSelectionOutsideFilter,
                    onSelectAllForCurrentFilter: _bulkBusy ? () {} : _handleSelectAllToggle,
                    onClose: _exitSelectMode,
                    middleActions: [
                      OutlinedButton.icon(
                        onPressed: _bulkBusy ? null : _confirmBulkMoveCategory,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                        icon: const Icon(Icons.drive_file_move_outline, size: 16),
                        label: const Text('ย้ายหมวดหมู่'),
                      ),
                    ],
                    onDelete: _bulkBusy ? () {} : _confirmBulkDelete,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

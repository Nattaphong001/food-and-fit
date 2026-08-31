// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_CARDIO_ACTIVITIES : จัดการกิจกรรมคาร์ดิโอ (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบประเภทกิจกรรมคาร์ดิโอที่ผู้ใช้สามารถเลือกออกกำลังกายได้
//                รวมค่า METs ที่ใช้คำนวณพลังงานเผาผลาญ (ดู CLAUDE.md ข้อ 5 — ห้ามแก้สูตร)
// [PAGE_ROUTE] /admin > คาร์ดิโอ > กิจกรรมคาร์ดิโอ & METs
// [USES_FEATURES] CARDIO
//
// ย้ายจากแอปมือถือ (lib/views/admin/workout/manage_cardio_activities_view.dart)
// Logic CRUD/validate เหมือนเดิมทุกจุด (COPY) — เปลี่ยนจุดที่ใช้บนเว็บไม่ได้:
//   flutter_inappwebview (InAppWebView) -> YoutubeEmbedView (iframe ผ่าน dart:ui_web,
//   ไม่ต้องเพิ่ม dependency ใหม่นอกจาก package:web ที่มากับ Flutter SDK) เพราะ
//   flutter_inappwebview ไม่รองรับ Flutter Web ตามเอกสารทางการของ plugin
// Layout: AppBar+FAB มือถือ -> AdminListHeader + DataTable, sort bottom sheet -> ปุ่มสลับในหัวตาราง

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/widgets/admin_breadcrumb.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../core/widgets/youtube_embed_view.dart';
import '../../../services/api_client.dart';


class ManageCardioActivitiesView extends StatefulWidget {
  // เปิดจากการคลิกการ์ดประเภทคาร์ดิโอ (drill-down แบบเดียวกับกลุ่มกล้ามเนื้อ -> ท่าฝึกเวท)
  // พรีเซ็ตตัวกรองหมวดหมู่ให้ทันที; null = เปิดจากเมนู sidebar ปกติ ไม่ล็อกตัวกรอง
  final int? initialCatId;
  final VoidCallback? onBack;
  const ManageCardioActivitiesView({super.key, this.initialCatId, this.onBack});

  @override
  State<ManageCardioActivitiesView> createState() => _ManageCardioActivitiesViewState();
}

class _ManageCardioActivitiesViewState extends State<ManageCardioActivitiesView> {
  List<dynamic> activities = [];
  List<dynamic> categories = [];
  bool isLoading = true;
  bool _hasError = false;

  String _searchQuery = '';
  late int? _selectedCatId = widget.initialCatId;
  bool _sortAscending = false;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  bool _isTableView = false;

  // ชื่อประเภทคาร์ดิโอที่กำลังกรองอยู่ (สำหรับ AdminBreadcrumb ตอน drill-down) — ผูกกับ
  // _selectedCatId/categories ที่มีอยู่แล้ว ไม่สร้าง state ใหม่
  String? get _selectedCatName {
    for (final c in categories) {
      if (c['cdc_id'] == _selectedCatId) return c['cdc_name']?.toString();
    }
    return null;
  }

  String get baseUrl => ApiClient.serverUrl;
  String get cardioApiUrl => '${ApiClient.serverUrl}/api/exercises/cardio';
  String get categoryApiUrl => '${ApiClient.serverUrl}/api/exercises/cardio-categories';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  String _buildImageUrl(String path) => ApiClient.prefixPath(path) ?? '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    AdminDataBus.cardioCategories.addListener(_onCategoriesChanged);
  }

  @override
  void dispose() {
    AdminDataBus.cardioCategories.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  // หน้านี้ถูก cache ค้างไว้ใน IndexedStack ของ admin_shell_view ไม่ได้ rebuild ตอนสลับเมนู —
  // ฟัง AdminDataBus แทน เพื่อรู้ตัวทันทีเวลาหน้าประเภทคาร์ดิโอ (คนละหน้า คนละ state) เพิ่ม/แก้/ลบสำเร็จ
  Future<void> _onCategoriesChanged() async {
    if (!mounted) return;
    await _fetchData();
    if (!mounted) return;
    final filterStillValid = categories.any((c) => c['cdc_id'] == _selectedCatId);
    if (_selectedCatId != null && !filterStillValid) {
      setState(() => _selectedCatId = null);
    }
  }

  List<dynamic> get _filteredActivities {
    List<dynamic> result = List.from(activities);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((item) => (item['cdo_name'] ?? '').toLowerCase().contains(q)).toList();
    }
    if (_selectedCatId != null) {
      result = result.where((item) => item['cdc_id'] == _selectedCatId).toList();
    }
    // เรียงตามหมวดหมู่ก่อน (ตามลำดับที่หมวดหมู่แสดงจริง) แล้วค่อยเรียง METs ภายในหมวดหมู่เดียวกัน
    // แทนการเรียง METs ปนข้ามหมวดหมู่แบบเดิม (จะเห็นกิจกรรมโหดๆ ของหมวดอื่นแทรกอยู่บนสุดของทุกหมวด)
    final catOrder = <int, int>{};
    for (var i = 0; i < categories.length; i++) {
      final id = categories[i]['cdc_id'];
      if (id is int) catOrder[id] = i;
    }
    result.sort((a, b) {
      final catA = catOrder[a['cdc_id']] ?? 1 << 30;
      final catB = catOrder[b['cdc_id']] ?? 1 << 30;
      if (catA != catB) return catA.compareTo(catB);
      final va = (a['cdo_mets'] as num?) ?? 0;
      final vb = (b['cdo_mets'] as num?) ?? 0;
      return _sortAscending ? va.compareTo(vb) : vb.compareTo(va);
    });
    return result;
  }

  Future<void> _fetchData() async {
    setState(() {
      isLoading = true;
      _hasError = false;
    });
    try {
      final results = await Future.wait([
        _api.get('/exercises/cardio'),
        _api.get('/exercises/cardio-categories'),
      ]);
      final resCardio = results[0];
      final resCat = results[1];
      if (!mounted) return;
      setState(() => isLoading = false);
      if (resCardio.statusCode == 200) {
        setState(() => activities = resCardio.data['data'] ?? []);
      } else {
        setState(() => _hasError = true);
      }
      if (resCat.statusCode == 200) {
        setState(() => categories = resCat.data['data'] ?? []);
      } else {
        setState(() => _hasError = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _hasError = true;
      });
      _showSnackBar('เกิดข้อผิดพลาดในการเชื่อมต่อ: $e');
    }
  }

  Future<void> _handleDelete(int id, String name) async {
    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (!confirm) return;
    _showLoadingDialog();
    try {
      final res = await http.delete(Uri.parse('$cardioApiUrl/$id'), headers: _authHeaders);
      if (!mounted) return;
      Navigator.pop(context);
      if (res.statusCode == 200) {
        ApiClient.clearCache();
        _fetchData();
        showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
      } else {
        _showSnackBar('ลบไม่สำเร็จ: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาดในการลบ');
    }
  }

  Future<void> _handleSave(
    Map<String, dynamic>? oldItem,
    String name, String mets, String desc, String technique, String video,
    int? catId, bool hasDistance,
    File? imageFile, Uint8List? imageBytes, String? imageFileName,
    File? loopVideoFile, Uint8List? loopVideoBytes, String? loopVideoFileName,
  ) async {
    if (name.isEmpty || mets.isEmpty || catId == null) {
      _showSnackBar('กรุณากรอกข้อมูลให้ครบถ้วน');
      return;
    }

    // METs กิจกรรมจริงแทบทั้งหมดอยู่ในช่วง 1.5-15 (เดินเบาๆ ~2 ถึงวิ่งเร็วมาก ~14) เตือนเฉยๆ
    // ไม่บล็อก เผื่อมีกิจกรรมจริงหลุดช่วงได้บ้าง
    final parsedMets = double.tryParse(mets);
    if (parsedMets != null && (parsedMets < 1.5 || parsedMets > 15)) {
      final proceed = await showAppConfirmDialog(
        context,
        icon: Icons.warning_amber_rounded,
        title: 'ค่า METs ผิดปกติ',
        content: 'กรอกไว้ $parsedMets ซึ่งอยู่นอกช่วงปกติของกิจกรรมทั่วไป (1.5-15)\nต้องการบันทึกต่อหรือไม่?',
        confirmLabel: 'บันทึกต่อ',
        cancelLabel: 'กลับไปแก้ไข',
        color: AppColors.alertWarning,
      );
      if (!proceed) return;
    }

    final trimmedName = name.trim().toLowerCase();
    final isDuplicate = activities.any((a) {
      if (oldItem != null && a['cdo_id'] == oldItem['cdo_id']) return false;
      return (a['cdo_name'] ?? '').toString().trim().toLowerCase() == trimmedName;
    });
    if (isDuplicate) {
      _showSnackBar('มีกิจกรรมชื่อ "$name" อยู่แล้ว', type: AppAlertType.warning);
      return;
    }

    _showLoadingDialog();
    try {
      final isEdit = oldItem != null;
      final url = isEdit ? '$cardioApiUrl/${oldItem['cdo_id']}' : cardioApiUrl;
      var request = http.MultipartRequest(isEdit ? 'PUT' : 'POST', Uri.parse(url));
      request.headers.addAll(_authHeaders);
      request.fields['cdo_name'] = name.trim();
      request.fields['cdo_mets'] = mets;
      request.fields['cdo_description'] = desc;
      request.fields['cdo_technique'] = technique;
      request.fields['cdo_video'] = video;
      request.fields['cdc_id'] = catId.toString();
      request.fields['cdo_has_distance'] = hasDistance ? '1' : '0';

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes('cdo_image', imageBytes, filename: imageFileName));
        }
        if (loopVideoBytes != null && loopVideoFileName != null) {
          request.files.add(http.MultipartFile.fromBytes('cdo_loop_video', loopVideoBytes, filename: loopVideoFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(await http.MultipartFile.fromPath('cdo_image', imageFile.path));
        }
        if (loopVideoFile != null) {
          request.files.add(await http.MultipartFile.fromPath('cdo_loop_video', loopVideoFile.path));
        }
      }

      final response = await http.Response.fromStream(await request.send());
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200 || response.statusCode == 201) {
        ApiClient.clearCache();
        await _fetchData();
        if (!mounted) return;
        Navigator.pop(context);
        _showSnackBar(isEdit ? 'แก้ไขข้อมูลสำเร็จ' : 'เพิ่มข้อมูลสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาดในการบันทึก: $e');
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
  // [FEATURE] CARDIO
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหาและตัวกรองหมวดหมู่กลับค่าเริ่มต้น — ใช้ร่วมกันทั้งปุ่ม
  //               "ล้างตัวกรอง" บน AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() => setState(() {
        _searchQuery = '';
        _selectedCatId = null;
        _currentPage = 1;
      });

  String? _getYouTubeEmbedUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final regExp = RegExp(r'(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url);
    if (match != null) return 'https://www.youtube.com/embed/${match.group(1)}';
    return null;
  }

  // เปลี่ยนจาก chip เป็น dropdown (มาตรฐานตัวกรอง ข้อ 2) — ประเภทคาร์ดิโอเป็น master data ที่
  // แอดมินเพิ่ม/ลบเองได้ ไม่ใช่ enum ค่าคงที่ ใช้คอนโทรลเดียวกับประเภทโภชนาการ/กลุ่มกล้ามเนื้อ
  Widget _buildCategoryDropdown() {
    // ระหว่างโหลด categories ยังไม่มาถึง แต่ _selectedCatId อาจถูกพรีเซ็ตไว้แล้ว (เปิดจากการ์ด
    // drill-down) — ถ้า id นั้นยังไม่อยู่ใน items ให้ fallback เป็น null กัน DropdownButtonFormField
    // assert พังตอน initialValue ไม่ match รายการไหนเลย (เคสเดียวกับ manage_food_items_view.dart)
    final validCatIds = categories.map((c) => c['cdc_id'] as int?).toSet();
    final safeInitialValue = validCatIds.contains(_selectedCatId) ? _selectedCatId : null;
    return SizedBox(
      width: 190,
      height: 40,
      child: DropdownButtonFormField<int?>(
        key: ValueKey('cardio_cat_filter_${categories.length}'),
        initialValue: safeInitialValue,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          prefixIcon: Icon(Icons.category_outlined, size: 18, color: AppColors.primaryGreen),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('ทุกหมวดหมู่', style: TextStyle(fontSize: 13))),
          ...categories.map((c) => DropdownMenuItem<int?>(value: c['cdc_id'] as int?, child: Text(c['cdc_name'] ?? '', style: const TextStyle(fontSize: 13)))),
        ],
        onChanged: (v) => setState(() {
          _selectedCatId = v;
          _currentPage = 1;
        }),
      ),
    );
  }

  // มาตรฐานตัวกรอง ข้อ 3 (แก้ตามรีวิว 2026-08-29): หน้านี้มีมิติให้เรียงแค่ METs มิติเดียว —
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
          Expanded(child: Text('เรียงตาม METs', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted), overflow: TextOverflow.ellipsis)),
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

  // สลับมุมมองการ์ด/ตาราง แบบเดียวกับหน้าท่าฝึกเวท (มาตรฐานเดียวกันทั้งเว็บ)
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
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.grid_view_outlined, !_isTableView, () => setState(() => _isTableView = false), 'มุมมองการ์ด'),
        btn(Icons.table_rows_outlined, _isTableView, () => setState(() => _isTableView = true), 'มุมมองตาราง'),
      ]),
    );
  }

  // คอลัมน์ thumb/METs/จัดการ กว้างคงที่พอดีเนื้อหา ส่วน ชื่อ/หมวดหมู่/คำอธิบาย ยืด-หดตามพื้นที่
  // จอจริงเสมอ (สัดส่วน 30/20/50% ของพื้นที่ที่เหลือ) แบบเดียวกับตารางท่าฝึกเวท (มาตรฐานเดียวกัน
  // ทั้งเว็บ) ให้คอลัมน์ "จัดการ" ชิดขวาสุดพอดีทุกขนาดจอโดยไม่ต้องเดา px คงที่ — กว้างไม่พอ
  // (ต่ำกว่า min) ค่อย fallback ไปเปิด scroll แนวนอนของ AdminDataTable เอง
  static const double _thumbW = 56;
  static const double _metsW = 90;
  static const double _actionW = 88;
  static const double _nameMin = 200, _catMin = 140, _descMin = 220;

  Widget _buildActivityTable(List<dynamic> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double reserve = 8;
        final double flexAvailable = constraints.maxWidth - _thumbW - _metsW - _actionW - reserve;
        final double minFlexTotal = _nameMin + _catMin + _descMin;
        final double flexTotal = flexAvailable < minFlexTotal ? minFlexTotal : flexAvailable;
        final double nameW = (flexTotal * 0.30) < _nameMin ? _nameMin : flexTotal * 0.30;
        final double catW = (flexTotal * 0.20) < _catMin ? _catMin : flexTotal * 0.20;
        final double descWRaw = flexTotal - nameW - catW;
        final double descW = descWRaw < _descMin ? _descMin : descWRaw;

        final columns = [
          AdminDataColumn(key: 'thumb', label: '', width: _thumbW),
          AdminDataColumn(key: 'name', label: 'ชื่อกิจกรรม', width: nameW),
          AdminDataColumn(key: 'category', label: 'หมวดหมู่', width: catW),
          AdminDataColumn(key: 'mets', label: 'METs', width: _metsW, numeric: true),
          AdminDataColumn(key: 'desc', label: 'คำอธิบาย', width: descW),
        ];

        return AdminDataTable(
          columns: columns,
          rowCount: rows.length,
          actionColumnWidth: _actionW,
          rowHeight: 64,
          cellsBuilder: (context, index) {
            final item = rows[index];
            final String? imgPath = item['cdo_image'];
            final String name = item['cdo_name'] ?? '';
            final cat = categories.firstWhere((c) => c['cdc_id'] == item['cdc_id'], orElse: () => null);
            final String catName = cat?['cdc_name'] ?? '';
            final String desc = item['cdo_description'] ?? '';

            return Row(children: [
              AdminDataCell(
                width: _thumbW,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36, height: 36,
                    color: AppColors.calorieBadgeBg,
                    child: (imgPath != null && imgPath.isNotEmpty)
                        ? AdminNetworkImage(_buildImageUrl(imgPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.directions_run, color: AppColors.primaryGreen, size: 18))
                        : const Icon(Icons.directions_run, color: AppColors.primaryGreen, size: 18),
                  ),
                ),
              ),
              AdminDataCell(width: nameW, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
              AdminDataCell(width: catW, child: Text(catName.isEmpty ? 'ไม่มีหมวดหมู่' : catName, style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              AdminDataCell(width: _metsW, numeric: true, child: Text('${item['cdo_mets']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              AdminDataCell(width: descW, child: Text(desc.isEmpty ? '-' : desc, style: const TextStyle(fontSize: 12.5, color: AppColors.textBody), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]);
          },
          actionsBuilder: (context, index) {
            final item = rows[index];
            final String name = item['cdo_name'] ?? '';
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
                  _handleDelete(item['cdo_id'], name);
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

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['cdo_name'] ?? '');
    final metCtrl = TextEditingController(text: item?['cdo_mets']?.toString() ?? '');
    final descCtrl = TextEditingController(text: item?['cdo_description'] ?? '');
    final List<TextEditingController> techniqueItemCtrls = (item?['cdo_technique'] ?? '')
        .toString()
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => TextEditingController(text: s))
        .toList();
    if (techniqueItemCtrls.isEmpty) techniqueItemCtrls.add(TextEditingController());
    final videoCtrl = TextEditingController(text: item?['cdo_video'] ?? '');
    final bool isAdding = item == null;
    final int? lockedCatId = isAdding ? _selectedCatId : null;
    final bool showCatSelector = lockedCatId == null;
    int? selectedCatId = lockedCatId ?? item?['cdc_id'] ?? (isAdding && categories.isNotEmpty ? categories.first['cdc_id'] as int? : null);
    bool hasDistance = (item?['cdo_has_distance'] ?? 0) == 1;

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    File? selectedLoopVideo;
    Uint8List? selectedLoopVideoBytes;
    String? selectedLoopVideoName;
    final existingLoopVideo = (item?['cdo_loop_video'] ?? '').toString();
    final ImagePicker picker = ImagePicker();
    String? previewEmbedUrl = _getYouTubeEmbedUrl(item?['cdo_video']);

    showAdminDialog(
      context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickImage() async {
            final pickedFile = await picker.pickImage(source: ImageSource.gallery);
            if (pickedFile != null) {
              final bytes = await pickedFile.readAsBytes();
              setDialogState(() {
                selectedImageBytes = bytes;
                selectedImageName = pickedFile.name;
                if (!kIsWeb) selectedImage = File(pickedFile.path);
              });
            }
          }

          Future<void> pickLoopVideo() async {
            final f = await picker.pickVideo(source: ImageSource.gallery);
            if (f != null) {
              setDialogState(() => selectedLoopVideoName = f.name);
              if (kIsWeb) {
                final bytes = await f.readAsBytes();
                setDialogState(() => selectedLoopVideoBytes = bytes);
              } else {
                setDialogState(() => selectedLoopVideo = File(f.path));
              }
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview = Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if (item?['cdo_image'] != null && item?['cdo_image'] != "") {
            imagePreview = AdminNetworkImage(_buildImageUrl(item!['cdo_image']), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.add_a_photo, size: 40));
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item == null ? 'เพิ่มกิจกรรมคาร์ดิโอ' : 'แก้ไขกิจกรรมคาร์ดิโอ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))),
                      IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20), onPressed: () => Navigator.pop(dialogContext)),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Stack(children: [
                                ClipOval(
                                  child: Container(
                                    height: 100, width: 100,
                                    color: Colors.grey[100],
                                    child: imagePreview,
                                  ),
                                ),
                                Positioned(
                                  bottom: 2, right: 2,
                                  child: Container(padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14)),
                                ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Center(child: Text('แตะวงกลมเพื่อเปลี่ยนรูปภาพ', style: TextStyle(color: Colors.grey, fontSize: 11))),
                          const SizedBox(height: 16),
                          const Text('ชื่อกิจกรรม *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              hintText: 'เช่น วิ่ง, ว่ายน้ำ...',
                              prefixIcon: const Icon(Icons.directions_run, color: AppColors.primaryGreen, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('ประเภท *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          if (showCatSelector)
                            DropdownButtonFormField<int>(
                              initialValue: selectedCatId,
                              items: categories.map<DropdownMenuItem<int>>((cat) => DropdownMenuItem<int>(value: cat['cdc_id'], child: Text(cat['cdc_name'] ?? '', style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setDialogState(() => selectedCatId = v),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.category, color: AppColors.primaryGreen, size: 18),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3))),
                              child: Row(children: [
                                const Icon(Icons.category, color: AppColors.primaryGreen, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(categories.firstWhere((c) => c['cdc_id'] == selectedCatId, orElse: () => {'cdc_name': ''})['cdc_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen))),
                              ]),
                            ),
                          const SizedBox(height: 10),
                          const Text('ค่าความหนักของกิจกรรม (METs) *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 2),
                          Text('ตัวเลขบ่งชี้ความหนักของกิจกรรม ยิ่งสูงยิ่งเผาผลาญพลังงานมาก ใช้คำนวณแคลอรี่ที่เผาผลาญ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: metCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: 'เช่น 7.0',
                              prefixIcon: const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.straighten, color: AppColors.primaryGreen, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(child: Text('มีการวัดระยะทาง', style: TextStyle(fontSize: 13, color: Colors.black87))),
                              Switch(value: hasDistance, activeThumbColor: AppColors.primaryGreen, onChanged: (v) => setDialogState(() => hasDistance = v)),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          const Text('คำอธิบาย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(controller: descCtrl, minLines: 3, maxLines: 6, keyboardType: TextInputType.multiline, decoration: InputDecoration(hintText: 'อธิบายลักษณะกิจกรรมโดยย่อ...', contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12))),
                          const SizedBox(height: 14),
                          const Text('เทคนิคการฝึก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 2),
                          Text('เพิ่มทีละข้อ จะแสดงเป็นขั้นตอนในแอปมือถือ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          ...techniqueItemCtrls.asMap().entries.map((e) {
                            final int idx = e.key;
                            final TextEditingController ctrl = e.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                Container(
                                  width: 26, height: 26,
                                  decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                                  child: Center(child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: ctrl,
                                    decoration: InputDecoration(
                                      hintText: 'ขั้นตอนที่ ${idx + 1}...',
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
                                  tooltip: 'ลบข้อนี้',
                                  onPressed: techniqueItemCtrls.length == 1
                                      ? null
                                      : () => setDialogState(() => techniqueItemCtrls.removeAt(idx)),
                                ),
                              ]),
                            );
                          }),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setDialogState(() => techniqueItemCtrls.add(TextEditingController())),
                              icon: const Icon(Icons.add, size: 18, color: AppColors.primaryGreen),
                              label: const Text('เพิ่มขั้นตอน', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _videoFieldBlock(
                            icon: Icons.play_circle_outline,
                            iconColor: Colors.redAccent,
                            title: 'วิดีโอสอน (YouTube)',
                            helper: 'วางลิงก์ YouTube (ต้องขึ้นต้นด้วย https://) ของวิดีโอสอนเต็ม แสดงในหน้ารายละเอียดกิจกรรม',
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              TextField(
                                controller: videoCtrl,
                                onChanged: (v) => setDialogState(() => previewEmbedUrl = _getYouTubeEmbedUrl(v)),
                                decoration: InputDecoration(
                                  hintText: 'https://youtube.com/...',
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                ),
                              ),
                              if (previewEmbedUrl != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5))),
                                  child: YoutubeEmbedView(embedUrl: previewEmbedUrl!, borderRadius: '11px'),
                                ),
                              ],
                            ]),
                          ),
                          const SizedBox(height: 14),
                          _videoFieldBlock(
                            icon: Icons.loop,
                            iconColor: AppColors.primaryGreen,
                            title: 'วิดีโอ Loop (ระหว่างฝึก)',
                            helper: 'อัปโหลดไฟล์วิดีโอสั้น (MP4) เล่นวนซ้ำ แสดงระหว่างฝึกในแอปมือถือ ไม่บังคับกรอก',
                            child: InkWell(
                              onTap: pickLoopVideo,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                                child: Row(children: [
                                  const Icon(Icons.upload_file, color: AppColors.primaryGreen, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(selectedLoopVideoName ?? (existingLoopVideo.isNotEmpty ? existingLoopVideo.split('/').last : 'แตะเพื่อเลือกไฟล์วิดีโอ loop'), overflow: TextOverflow.ellipsis)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: () => _handleSave(item, nameCtrl.text, metCtrl.text, descCtrl.text, techniqueItemCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).join('\n'), videoCtrl.text, selectedCatId, hasDistance, selectedImage, selectedImageBytes, selectedImageName, selectedLoopVideo, selectedLoopVideoBytes, selectedLoopVideoName),
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

  // เปิดวิดีโอในแท็บใหม่แทนฝัง iframe ใน Dialog — Flutter Web มีข้อจำกัดของ engine ที่ platform
  // view (HtmlElementView) ในนี้ showDialog/Overlay ไม่รับ pointer event เลย (กดเล่น/แชร์/ดูใน
  // YouTube ไม่ได้สักปุ่ม แม้ iframe จะโหลดและแสดงผลปกติ) ยืนยันแล้วทั้งจากคลิกจริงและ Playwright
  // — ดู manage_weight_exercises_view.dart ประกอบ (บั๊กเดียวกัน แก้จุดเดียวกัน)
  void _showVideoDialog(String videoUrl) {
    final embedUrl = _getYouTubeEmbedUrl(videoUrl);
    if (embedUrl == null) {
      _showSnackBar('ลิงก์วิดีโอไม่ถูกต้อง');
      return;
    }
    web.window.open(videoUrl, '_blank');
  }

  // เล่นวิดีโอ loop (ไฟล์อัปโหลด) เปิดแท็บใหม่แทนฝัง Dialog — เหตุผลเดียวกับ _showVideoDialog
  // ดู manage_weight_exercises_view.dart ประกอบ (บั๊กเดียวกัน แก้จุดเดียวกัน)
  void _showLoopVideoDialog(String loopVideoPath) {
    final url = ApiClient.prefixPath(loopVideoPath);
    if (url == null) {
      _showSnackBar('ไฟล์วิดีโอ loop ไม่ถูกต้อง');
      return;
    }
    web.window.open(url, '_blank');
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
          Tooltip.dismissAllToolTips();
          onPressed();
        },
      ),
    );
  }

  // บล็อกฟอร์มวิดีโอ 1 ช่อง (สอน หรือ loop) — แยกกรอบชัดเจนคนละบล็อกพร้อม title/helper text กันสับสน
  // ระหว่าง 2 ฟิลด์ที่ทำหน้าที่ต่างกัน (วิดีโอสอนเต็ม vs. loop clip เล่นวนตอนฝึก — เก็บไว้ทั้งคู่
  // ตามที่ตัดสินใจแล้ว ไม่ลบอันใดอันหนึ่ง)
  Widget _videoFieldBlock({required IconData icon, required Color iconColor, required String title, required String helper, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: iconColor.withValues(alpha: 0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          ]),
          const SizedBox(height: 3),
          Text(helper, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _smallBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color, width: 0.5)),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  // การ์ดแนวตั้งขนาดใหญ่ (บรีฟรอบ 3 ข้อ 5.2) — สไตล์เดียวกับท่าฝึกเวท (ข้อ 3.2) เพื่อความสม่ำเสมอ
  Widget _buildActivityCard(Map<String, dynamic> item) {
    final String? imgPath = item['cdo_image'];
    final bool hasVideo = item['cdo_video'] != null && item['cdo_video'].toString().isNotEmpty;
    final bool hasLoopVideo = item['cdo_loop_video'] != null && item['cdo_loop_video'].toString().isNotEmpty;
    final bool hasDistance = (item['cdo_has_distance'] ?? 0) == 1;
    final cat = categories.firstWhere((c) => c['cdc_id'] == item['cdc_id'], orElse: () => null);
    final String catName = cat?['cdc_name'] ?? '';
    final String desc = item['cdo_description'] ?? '';
    final String name = item['cdo_name'] ?? '';

    // hover state ของปุ่มแก้ไข/ลบ — ประกาศ bool ไว้นอก StatefulBuilder.builder (ไม่ใช่ข้างใน)
    // เพราะ setLocalState เรียกซ้ำ builder ตัวเดียวกันโดยไม่ rebuild _buildActivityCard ใหม่
    // ต้องให้ตัวแปรอยู่ใน closure ข้างนอกถึงจะจำค่าข้ามการ hover แต่ละครั้งได้ (ตรงกับ pattern
    // _MuscleGroupCard/_CardioCategoryCard ที่ใช้ StatefulWidget เต็มรูปแบบ — ที่นี่การ์ดมี
    // dependency ผูกกับ method อื่นในหน้าเยอะ จึงใช้ StatefulBuilder ห่อเฉพาะโซนรูปแทนแยกคลาส)
    bool hovering = false;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]),
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
                      aspectRatio: 1.5,
                      child: Container(
                        color: AppColors.calorieBadgeBg,
                        child: (imgPath != null && imgPath.isNotEmpty)
                            ? AdminNetworkImage(_buildImageUrl(imgPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.directions_run, color: AppColors.primaryGreen, size: 40))
                            : const Icon(Icons.directions_run, color: AppColors.primaryGreen, size: 40),
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
                        _imageOverlayButton(icon: Icons.delete_outline, color: Colors.redAccent, onPressed: () => _handleDelete(item['cdo_id'], name), tooltip: 'ลบ'),
                      ]),
                    ),
                  ),
                  Positioned(
                    bottom: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                      child: Text('${item['cdo_mets']} METs', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (hasVideo || hasLoopVideo)
                    Positioned(
                      bottom: 8, right: 8,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (hasLoopVideo)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Tooltip(
                              message: 'ดูวิดีโอ loop',
                              child: GestureDetector(
                                onTap: () => _showLoopVideoDialog(item['cdo_loop_video']),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.loop, size: 16, color: Colors.white, semanticLabel: 'ดูวิดีโอ loop'),
                                ),
                              ),
                            ),
                          ),
                        if (hasVideo)
                          Tooltip(
                            message: 'ดูวิดีโอสาธิต',
                            child: GestureDetector(
                              onTap: () => _showVideoDialog(item['cdo_video']),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.play_circle_fill, size: 16, color: Colors.white, semanticLabel: 'ดูวิดีโอสาธิต'),
                              ),
                            ),
                          ),
                      ]),
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
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  _smallBadge(catName.isEmpty ? 'ไม่มีหมวดหมู่' : catName, AppColors.textMuted),
                  if (hasDistance) _smallBadge('มีระยะทาง', AppColors.primaryGreen),
                ]),
                if (desc.isNotEmpty) ...[const SizedBox(height: 8), Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textBody))],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRows = _filteredActivities;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? (_searchQuery.isNotEmpty || _selectedCatId != null ? AdminListState.noResult : AdminListState.empty)
                : null;

    // เปิดจากการ์ดประเภทคาร์ดิโอ = แสดงเนื้อหาแทนที่อยู่ในสล็อตเดิมของ sidebar shell (ไม่ push
    // route ใหม่ — sidebar ยังอยู่ตลอด) initialCatId == null = เปิดจาก sidebar เมนูปกติ
    final bool isDrillDown = widget.initialCatId != null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          leading: isDrillDown ? AppBackButton(onTap: widget.onBack) : null,
          breadcrumb: const ['คาร์ดิโอ', 'กิจกรรมคาร์ดิโอ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มกิจกรรม',
        ),
        // --------------------------------------------
        // [FEATURE] COMMON_UI
        // [FUNCTION] AdminBreadcrumb (ใช้งานใน ManageCardioActivitiesView)
        // [DESCRIPTION] แสดง "ประเภทคาร์ดิโอ › ชื่อหมู่ที่คลิกเข้ามา" เฉพาะตอน drill-down
        //               จากการ์ดประเภทคาร์ดิโอ กดที่ root กลับไปหน้าประเภทคาร์ดิโอ
        // [INPUT] isDrillDown, _selectedCatName, widget.onBack
        // [OUTPUT] แถบ breadcrumb เหนือแถบค้นหา/ตัวกรอง
        // [RELATED] CARDIO
        // --------------------------------------------
        if (isDrillDown)
          AdminBreadcrumb(
            rootLabel: 'ประเภทคาร์ดิโอ',
            currentLabel: _selectedCatName,
            onRootTap: widget.onBack,
          ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อกิจกรรม...',
          onSearchChanged: (v) => setState(() {
            _searchQuery = v;
            _currentPage = 1;
          }),
          trailing: [
            _buildSortControl(),
            _buildCategoryDropdown(),
          ],
          viewToggle: _buildViewToggle(),
          resultCount: allRows.length,
          showClearButton: _searchQuery.isNotEmpty || _selectedCatId != null,
          onClearFilters: _clearFilters,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: _isTableView ? AdminSkeletonVariant.table : AdminSkeletonVariant.cards,
                  onAdd: () => _showForm(),
                  onRetry: _fetchData,
                  onClearFilter: _clearFilters,
                )
              : _isTableView
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _buildActivityTable(rows),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
                        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: rows.map((item) => SizedBox(width: width, child: _buildActivityCard(item))).toList(),
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

    return content;
  }
}

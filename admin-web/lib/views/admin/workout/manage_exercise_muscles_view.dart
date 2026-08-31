// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_EXERCISE_MUSCLES : เชื่อมโยงท่าฝึกกับกล้ามเนื้อ (เว็บ)
// [PAGE_PURPOSE] Admin กำหนดกล้ามเนื้อหลักและรองให้กับแต่ละท่าฝึก ใช้เป็นข้อมูลแสดงในหน้ารายละเอียดท่าฝึก
// [PAGE_ROUTE] /admin > เวทเทรนนิ่ง > เชื่อมโยงท่าฝึกกับกล้ามเนื้อ
// [USES_FEATURES] WEIGHT_TRAINING
//
// ย้ายจากแอปมือถือ (lib/views/admin/workout/manage_exercise_muscles_view.dart)
// ตารางจัดกลุ่มเป็น 1 แถว = 1 ท่าฝึก กล้ามเนื้อทุกตัวของท่านั้นแสดงเป็น chip (read-only) ในเซลล์เดียว
// คลิกแถว/ไอคอนแก้ไข = เปิดแผงข้าง (_showMusclePanel) แยกหลัก/รองเป็น 2 บล็อก เพิ่ม/ลบกล้ามเนื้อทีละตัว
// ที่นั่น — ตารางหลักไม่รองรับแก้ไข inline แล้ว
// ปุ่ม "เพิ่มการเชื่อมโยง" มุมขวาบน = เปิดฟอร์มเลือกท่าฝึก+กล้ามเนื้อแบบอิสระ (ไม่ล็อกท่า)
// เพิ่ม checkbox + แถบ bulk action ลบ/เพิ่มกล้ามเนื้อรองหลายท่าฝึกพร้อมกัน และคลิกหัวคอลัมน์ "ท่าฝึก"
// เพื่อเรียง ก-ฮ/ฮ-ก

import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';

// 1 กลุ่ม = 1 ท่าฝึก รวม mapping กล้ามเนื้อทุกตัวของท่านั้นไว้ด้วยกัน (บรีฟ P2 ข้อ 3 — ลดจาก
// ~97 แถว/1 กล้ามเนื้อต่อแถว เหลือ ~48 แถว/1 ท่าฝึกต่อแถว)
class _ExerciseGroup {
  final int wetId;
  final String exerciseName;
  final List<Map<String, dynamic>> mappings = [];
  _ExerciseGroup({required this.wetId, required this.exerciseName});
}

// สถานะการเชื่อมโยง สำหรับตัวกรองใน toolbar (บรีฟ UX รอบ 4 ข้อ 3) — ช่วยหาท่าที่ยังไม่มีข้อมูล
enum _LinkStatus { all, linked, unlinked }

class ManageExerciseMusclesView extends StatefulWidget {
  const ManageExerciseMusclesView({super.key});

  @override
  State<ManageExerciseMusclesView> createState() => _ManageExerciseMusclesViewState();
}

class _ManageExerciseMusclesViewState extends State<ManageExerciseMusclesView> {
  List<Map<String, dynamic>> mappings = [];
  List<Map<String, dynamic>> exercisesList = [];
  List<Map<String, dynamic>> musclesList = [];
  bool isLoading = true;
  bool _hasError = false;
  String _search = '';
  int? _filterMugId;
  _LinkStatus _filterLinkStatus = _LinkStatus.all;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  bool _sortAscending = true;
  final Set<int> _selectedWetIds = {};

  String get baseUrl => ApiClient.serverUrl;
  String get apiUrl => "$baseUrl/api/exercise-muscles";
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _fetchMappings();
    _fetchDropdownData();
    AdminDataBus.muscleGroups.addListener(_onMuscleGroupsChanged);
  }

  @override
  void dispose() {
    AdminDataBus.muscleGroups.removeListener(_onMuscleGroupsChanged);
    super.dispose();
  }

  // หน้านี้ถูก cache ค้างไว้ใน IndexedStack ของ admin_shell_view ไม่ได้ rebuild ตอนสลับเมนู —
  // ฟัง AdminDataBus แทน เพื่อรู้ตัวทันทีเวลาหน้ากลุ่มกล้ามเนื้อ (คนละหน้า คนละ state) เพิ่ม/แก้/ลบสำเร็จ
  Future<void> _onMuscleGroupsChanged() async {
    if (!mounted) return;
    await _fetchDropdownData();
    if (!mounted) return;
    final filterStillValid = musclesList.any((m) => m['mug_id'] == _filterMugId);
    if (_filterMugId != null && !filterStillValid) {
      setState(() => _filterMugId = null);
    }
  }

  // จับกลุ่มทุกท่าฝึก (จาก exercisesList) ไว้ก่อน แล้วเติม mapping กล้ามเนื้อของแต่ละท่าเข้าไป —
  // ต่างจากเดิมที่จับกลุ่มจาก mappings อย่างเดียว (ท่าที่ยังไม่มี mapping เลยจะไม่ขึ้นแถว) เปลี่ยนมา
  // รวม exercisesList ด้วยเพื่อให้ท่า "ยังไม่เชื่อม" ก็ยังเป็นแถวในตาราง (บรีฟ UX รอบ 4 ข้อ 3/7 —
  // ต้องเห็นท่าที่ยังไม่มีข้อมูลได้ ไม่ใช่แค่กรองแล้วหาย)
  Map<int, _ExerciseGroup> get _allGroupsByWetId {
    final map = <int, _ExerciseGroup>{};
    for (final ex in exercisesList) {
      final wetId = (ex['wet_id'] as num?)?.toInt();
      if (wetId == null) continue;
      map[wetId] = _ExerciseGroup(wetId: wetId, exerciseName: (ex['wet_name'] ?? '').toString());
    }
    for (final m in mappings) {
      final wetId = (m['wet_id'] as num?)?.toInt();
      if (wetId == null) continue;
      final group = map.putIfAbsent(
        wetId,
        () => _ExerciseGroup(wetId: wetId, exerciseName: (m['exercise'] ?? '').toString()),
      );
      group.mappings.add(m);
    }
    return map;
  }

  // จับกลุ่มแล้วกรองตามตัวกรอง/ค้นหา/สถานะการเชื่อมโยง แล้วเรียงชื่อท่าฝึก ก-ฮ/ฮ-ก ตาม _sortAscending
  List<_ExerciseGroup> get _groupedRows {
    var list = _allGroupsByWetId.values.toList();

    if (_filterMugId != null) {
      list = list.where((g) => g.mappings.any((m) => (m['mug_id'] as num?)?.toInt() == _filterMugId)).toList();
    }
    if (_filterLinkStatus == _LinkStatus.linked) {
      list = list.where((g) => g.mappings.isNotEmpty).toList();
    } else if (_filterLinkStatus == _LinkStatus.unlinked) {
      list = list.where((g) => g.mappings.isEmpty).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      list = list.where((g) =>
          g.exerciseName.toLowerCase().contains(q) ||
          g.mappings.any((m) => (m['muscle'] ?? '').toString().toLowerCase().contains(q))).toList();
    }

    list.sort((a, b) => a.exerciseName.compareTo(b.exerciseName) * (_sortAscending ? 1 : -1));
    return list;
  }

  bool get _hasActiveFilter => _search.isNotEmpty || _filterMugId != null || _filterLinkStatus != _LinkStatus.all;

  void _clearFilters() => setState(() {
        _search = '';
        _filterMugId = null;
        _filterLinkStatus = _LinkStatus.all;
        _currentPage = 1;
      });

  Future<void> _fetchMappings() async {
    setState(() {
      isLoading = true;
      _hasError = false;
    });
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
          mappings = List<Map<String, dynamic>>.from(list);
          isLoading = false;
        });
      } else {
        setState(() { isLoading = false; _hasError = true; });
        debugPrint("fetchMappings error: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      debugPrint("Error fetching mappings: $e");
      if (!mounted) return;
      setState(() { isLoading = false; _hasError = true; });
    }
  }

  Future<void> _fetchDropdownData() async {
    try {
      final results = await Future.wait([
        _api.get('/exercises/weights'),
        _api.get('/exercises/muscle-groups'),
      ]);
      if (!mounted) return;
      final resWe = results[0];
      final resMu = results[1];
      if (resWe.statusCode == 200) {
        final decoded = resWe.data;
        List<dynamic> list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? []) as List : decoded is List ? decoded : [];
        setState(() => exercisesList = List<Map<String, dynamic>>.from(list));
      }
      if (resMu.statusCode == 200) {
        final decoded = resMu.data;
        List<dynamic> list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? []) as List : decoded is List ? decoded : [];
        setState(() => musclesList = List<Map<String, dynamic>>.from(list));
      }
    } catch (e) {
      debugPrint("Error fetching dropdowns: $e");
    }
  }

  void _showLoading() {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)));
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // อ่านข้อความ error เฉพาะที่ backend ส่งมา (เช่น "ท่านี้ผูกกับกล้ามเนื้อกลุ่มนี้อยู่แล้ว" ตอนซ้ำ)
  // แทนที่จะโชว์ข้อความทั่วไปทุกกรณี — คืน null ถ้า parse ไม่ได้ ให้ caller ใช้ fallback ของตัวเอง
  String? _extractErrorMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
    } catch (_) {}
    return null;
  }

  Future<void> _handleSave(int wetId, int mugId, int typeInt) async {
    _showLoading();
    try {
      final body = json.encode({"exm_type": typeInt, "wet_id": wetId, "mug_id": mugId});
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      final response = await http.post(Uri.parse(apiUrl), headers: headers, body: body);

      Navigator.pop(context); // ปิด Loading
      Navigator.pop(context); // ปิด Form Dialog

      if (response.statusCode == 200 || response.statusCode == 201) {
        _fetchMappings();
        _showSnackBar('เพิ่มการเชื่อมโยงสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar(_extractErrorMessage(response.body) ?? 'เกิดข้อผิดพลาดในการบันทึก');
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // ลบ mapping ทั้งหมดของท่าฝึก 1 ท่า จากปุ่มถังขยะท้ายแถว (บรีฟ UX รอบ 4 ข้อ 5 — แยกจาก
  // _handleBulkDelete ที่ผูกกับ _selectedWetIds เพื่อไม่ให้ไปยุ่งกับ checkbox ที่ผู้ใช้เลือกไว้อยู่)
  Future<void> _handleDeleteGroup(int wetId, String exerciseName) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ลบการเชื่อมโยงกล้ามเนื้อทั้งหมดของ "$exerciseName" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );
    if (!confirm) return;

    final idsToDelete = _mappingsForWet(wetId).map((m) => m['id'] as int).toList();
    _showLoading();
    try {
      await Future.wait(idsToDelete.map((id) => http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders)));
      if (!mounted) return;
      Navigator.pop(context);
      await _fetchMappings();
      showAdminTopToast(context, 'ลบข้อมูลเรียบร้อย');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ลบ mapping ทั้งหมดของท่าฝึกที่เลือกไว้ (checkbox + bulk action bar ตามบรีฟ P2 ข้อ 3)
  Future<void> _handleBulkDelete() async {
    final count = _selectedWetIds.length;
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ลบการเชื่อมโยงกล้ามเนื้อทั้งหมดของ $count ท่าฝึกที่เลือกใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );
    if (!confirm) return;

    final idsToDelete = mappings
        .where((m) => _selectedWetIds.contains((m['wet_id'] as num?)?.toInt()))
        .map((m) => m['id'] as int)
        .toList();

    _showLoading();
    try {
      await Future.wait(idsToDelete.map((id) => http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders)));
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _selectedWetIds.clear());
      await _fetchMappings();
      showAdminTopToast(context, 'ลบข้อมูลเรียบร้อย ($count ท่าฝึก)');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ── เวอร์ชัน "เงียบ" (ไม่เปิด loading dialog / ไม่ pop route ของใครทั้งนั้น) ใช้ในแผงข้าง
  // (_showMusclePanel) ที่ต้องเรียกซ้ำได้หลายครั้งโดยแผงไม่ปิดตัวเอง ต่างจาก _handleSave/_handleDelete
  // เดิมที่ผูก pop ไว้กับฟอร์ม dialog เก่า (เรียกจากแผงจะทำให้แผงปิดไปด้วยโดยไม่ตั้งใจ)
  // คืน null = สำเร็จ, non-null = ข้อความ error ให้ caller โชว์ (แก้บั๊กเดิมที่แผงข้างเงียบสนิทเวลา
  // backend ปฏิเสธ เช่น เพิ่มกล้ามเนื้อซ้ำ — ผู้ใช้เห็น dropdown เคลียร์เหมือนสำเร็จทั้งที่ไม่ได้บันทึก)
  Future<String?> _createMappingSilent(int wetId, int mugId, int typeInt) async {
    try {
      final body = json.encode({"exm_type": typeInt, "wet_id": wetId, "mug_id": mugId});
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      final response = await http.post(Uri.parse(apiUrl), headers: headers, body: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchMappings();
        return null;
      }
      return _extractErrorMessage(response.body) ?? 'เพิ่มกล้ามเนื้อไม่สำเร็จ';
    } catch (e) {
      debugPrint("Error creating mapping: $e");
      return 'เพิ่มกล้ามเนื้อไม่สำเร็จ: $e';
    }
  }

  Future<String?> _deleteMappingSilent(int id) async {
    try {
      final response = await http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders);
      if (response.statusCode == 200) {
        await _fetchMappings();
        return null;
      }
      return _extractErrorMessage(response.body) ?? 'ลบกล้ามเนื้อไม่สำเร็จ';
    } catch (e) {
      debugPrint("Error deleting mapping: $e");
      return 'ลบกล้ามเนื้อไม่สำเร็จ: $e';
    }
  }

  List<Map<String, dynamic>> _mappingsForWet(int wetId) =>
      mappings.where((m) => (m['wet_id'] as num?)?.toInt() == wetId).toList();

  // เพิ่มกล้ามเนื้อ "รอง" ให้หลายท่าฝึกพร้อมกัน (bulk action จากแถบด้านล่างตอนติ๊ก checkbox
  // หลายแถว) — ข้ามท่าที่มีกล้ามเนื้อตัวนี้ผูกอยู่แล้ว (ไม่ว่าหลักหรือรอง) กันซ้ำ/error จาก backend
  Future<void> _handleBulkAddSecondary() async {
    int? chosenMugId = musclesList.isNotEmpty ? musclesList.first['mug_id'] as int? : null;

    final confirmed = await showAdminDialog<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          // ล็อกความกว้างไว้ (เหมือน dialog อื่นในไฟล์นี้) — ไม่งั้น Row(Expanded ปุ่ม) ข้างล่างจะดึง
          // Dialog ให้ยืดเต็มจอบนเว็บ
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('เพิ่มกล้ามเนื้อรองให้ ${_selectedWetIds.length} ท่าฝึก', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('ท่าที่มีกล้ามเนื้อนี้ผูกอยู่แล้วจะถูกข้ามอัตโนมัติ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: chosenMugId,
                    isExpanded: true,
                    decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                    items: musclesList.map((e) => DropdownMenuItem<int>(value: e['mug_id'], child: Text(e['mug_name'], overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setD(() => chosenMugId = v),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                        onPressed: chosenMugId == null ? null : () => Navigator.pop(ctx, true),
                        child: const Text('เพิ่ม', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || chosenMugId == null) return;

    final targetWetIds = _selectedWetIds.where((wetId) => !_mappingsForWet(wetId).any((m) => (m['mug_id'] as num?)?.toInt() == chosenMugId)).toList();
    if (targetWetIds.isEmpty) {
      _showSnackBar('ท่าที่เลือกไว้มีกล้ามเนื้อนี้ผูกอยู่แล้วทุกท่า', type: AppAlertType.warning);
      return;
    }

    _showLoading();
    try {
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      await Future.wait(targetWetIds.map((wetId) => http.post(
            Uri.parse(apiUrl),
            headers: headers,
            body: json.encode({"exm_type": 2, "wet_id": wetId, "mug_id": chosenMugId}),
          )));
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _selectedWetIds.clear());
      await _fetchMappings();
      showAdminTopToast(context, 'เพิ่มกล้ามเนื้อรองแล้ว (${targetWetIds.length} ท่าฝึก)');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // แผงข้าง (slide-over) รายละเอียดท่าฝึก 1 ท่า — แยกกล้ามเนื้อหลัก/รองเป็น 2 บล็อกชัดเจน พร้อม
  // dropdown ค้นหา+เพิ่ม และปุ่มลบต่อรายการ (บรีฟ UX รอบ 2 ข้อ 5 — แทนการแก้ inline ในตารางเดิม)
  void _showMusclePanel(int wetId, String exerciseName) {
    int? addingMainMugId;
    int? addingSecondaryMugId;
    bool busy = false;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ปิดแผง',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondaryAnim) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: StatefulBuilder(
              builder: (ctx, setPanelState) {
                final current = _mappingsForWet(wetId);
                final mains = current.where((m) => m['type'] == 'หลัก').toList();
                final secondaries = current.where((m) => m['type'] == 'รอง').toList();
                final usedMugIds = current.map((m) => (m['mug_id'] as num?)?.toInt()).toSet();
                final availableMuscles = musclesList.where((m) => !usedMugIds.contains(m['mug_id'] as int?)).toList();

                Future<void> addMuscle(int typeInt) async {
                  final mugId = typeInt == 1 ? addingMainMugId : addingSecondaryMugId;
                  if (mugId == null) return;
                  setPanelState(() => busy = true);
                  final error = await _createMappingSilent(wetId, mugId, typeInt);
                  setPanelState(() {
                    busy = false;
                    if (error == null) {
                      addingMainMugId = null;
                      addingSecondaryMugId = null;
                    }
                  });
                  if (error != null && mounted) _showSnackBar(error);
                }

                void cancelAdding(int typeInt) => setPanelState(() {
                      if (typeInt == 1) {
                        addingMainMugId = null;
                      } else {
                        addingSecondaryMugId = null;
                      }
                    });

                Future<void> removeMuscle(Map<String, dynamic> m) async {
                  setPanelState(() => busy = true);
                  final error = await _deleteMappingSilent(m['id'] as int);
                  setPanelState(() => busy = false);
                  if (error != null && mounted) _showSnackBar(error);
                }

                Widget section({required String title, required IconData icon, required Color color, required List<Map<String, dynamic>> items, required int typeInt}) {
                  final addingId = typeInt == 1 ? addingMainMugId : addingSecondaryMugId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.25))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
                          const SizedBox(width: 6),
                          Text('(${items.length})', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ]),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('ยังไม่มีกล้ามเนื้อในกลุ่มนี้', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: items.map((m) => Container(
                                  padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.4))),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text((m['muscle'] ?? '').toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: busy ? null : () => removeMuscle(m),
                                      child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: color.withValues(alpha: 0.8))),
                                    ),
                                  ]),
                                ))
                                .toList(),
                          ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: addingId,
                              isExpanded: true,
                              hint: const Text('เลือกกล้ามเนื้อเพื่อเพิ่ม...', style: TextStyle(fontSize: 12.5)),
                              decoration: const InputDecoration(isDense: true, filled: true, fillColor: Colors.white, contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
                              items: availableMuscles.map((e) => DropdownMenuItem<int>(value: e['mug_id'], child: Text(e['mug_name'], style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: busy ? null : (v) => setPanelState(() => typeInt == 1 ? addingMainMugId = v : addingSecondaryMugId = v),
                            ),
                          ),
                          // ปุ่มยืนยัน/ยกเลิกซ่อนไว้จนกว่าจะเลือกกล้ามเนื้อในดรอปดาวน์ก่อน — เลิกโชว์ "+"
                          // จางๆ กดไม่ได้ตลอดเวลา (งงว่าคืออะไร) เปลี่ยนเป็นโผล่คู่ ✓ เขียว/✕ แดง ทันที
                          // ที่มีอะไรให้ยืนยันหรือยกเลิก (ทำเล็กกว่าเดิมเพราะมี 2 ปุ่มติดกัน)
                          if (addingId != null) ...[
                            const SizedBox(width: 6),
                            IconButton.filled(
                              onPressed: busy ? null : () => cancelAdding(typeInt),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.3),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filled(
                              onPressed: busy ? null : () => addMuscle(typeInt),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                disabledBackgroundColor: AppColors.primaryGreen.withValues(alpha: 0.3),
                                minimumSize: const Size(32, 32),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.check, size: 16, color: Colors.white),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  );
                }

                return Material(
                  elevation: 8,
                  child: Container(
                    width: 420,
                    height: double.infinity,
                    color: AppColors.dialogBackground,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                          decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                          child: Row(children: [
                            Container(width: 4, height: 22, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(exerciseName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
                                const Text('กล้ามเนื้อหลัก / รอง', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ]),
                            ),
                            IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400), onPressed: () => Navigator.pop(ctx)),
                          ]),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                section(title: 'กล้ามเนื้อหลัก', icon: Icons.star_rounded, color: AppColors.primaryGreen, items: mains, typeInt: 1),
                                section(title: 'กล้ามเนื้อรอง', icon: Icons.star_border_rounded, color: Colors.grey.shade700, items: secondaries, typeInt: 2),
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
          ),
        );
      },
    );
  }

  void _showForm() {
    int? selectedWetId;
    int? selectedMugId;
    String selectedType = 'หลัก';

    showAdminDialog(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เพิ่มการเชื่อมโยง', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    const Text('เลือกท่าฝึก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: selectedWetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                      items: exercisesList.map((e) => DropdownMenuItem<int>(value: e['wet_id'], child: Text(e['wet_name'], overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) => setModalState(() => selectedWetId = val),
                    ),
                    const SizedBox(height: 15),
                    const Text('เลือกกล้ามเนื้อ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: selectedMugId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                      items: musclesList.map((e) => DropdownMenuItem<int>(value: e['mug_id'], child: Text(e['mug_name'], overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) => setModalState(() => selectedMugId = val),
                    ),
                    const SizedBox(height: 15),
                    const Text('ประเภทกล้ามเนื้อ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                      items: ['หลัก', 'รอง'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) => setModalState(() => selectedType = val!),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, padding: const EdgeInsets.symmetric(vertical: 15)),
                        onPressed: () {
                          if (selectedWetId != null && selectedMugId != null) {
                            int typeInt = selectedType == 'หลัก' ? 1 : 2;
                            _handleSave(selectedWetId!, selectedMugId!, typeInt);
                          } else {
                            _showSnackBar("กรุณาเลือกท่าฝึกและกล้ามเนื้อให้ครบถ้วน");
                          }
                        },
                        child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ความกว้างคอลัมน์ select/action คงที่ ส่วนท่าฝึก/กล้ามเนื้อคำนวณตามพื้นที่จริงใน _buildTable
  // (checkbox 48px / ท่าฝึก 25% / กล้ามเนื้อกินที่เหลือทั้งหมด / จัดการ 100px — บรีฟ UX รอบ 4 ข้อ 1)
  static const _colSelectWidth = 48.0;
  static const _actionColumnWidth = 100.0;
  static const _rowHeight = 88.0;

  // chip กล้ามเนื้อในแถวตาราง — read-only ล้วน (บรีฟ UX รอบ 2 ข้อ 5: ตารางหลักดูอย่างเดียว
  // แก้ไข/ลบย้ายไปทำในแผงข้าง _showMusclePanel ทั้งหมด ลดพื้นที่คลิกเล็กๆ ที่กดพลาดง่ายในแถว)
  // หลัก = พื้นเขียวทึบ ตัวอักษรขาว, รอง = พื้นโปร่ง ขอบเทา ตัวอักษรเทา (เลิกใช้ ★/☆ แยกเพราะดูยาก
  // ตามบรีฟ UX รอบ 4 ข้อ 2)
  Widget _buildMuscleChipReadOnly(Map<String, dynamic> m) {
    final isMain = m['type'] == 'หลัก';
    final muscleName = (m['muscle'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isMain ? AppColors.primaryGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isMain ? null : Border.all(color: Colors.grey.shade400, width: 0.8),
      ),
      child: Text(
        muscleName,
        style: TextStyle(fontSize: 11.5, color: isMain ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMuscleCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
      child: Text('$count', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
    );
  }

  // chip กล้ามเนื้อทั้งหมดของท่านั้น (ไม่ย่อ +N อีกต่อไป — ต้องเห็นครบทุกตัวในตาราง) ต่อท้ายด้วย badge
  // จำนวนรวม — หลักมาก่อนรองเสมอ, ท่าที่ยังไม่ผูกกล้ามเนื้อเลยแสดง chip เทา "ยังไม่ระบุ" แทนช่องว่าง
  // (บรีฟ UX รอบ 4 ข้อ 2/7 + feedback ผู้ใช้: ห้ามย่อ, ย้ายเลขจำนวนมาไว้ท้ายการ์ดสุดท้าย)
  Widget _buildMuscleChipsRow(_ExerciseGroup group) {
    if (group.mappings.isEmpty) {
      return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: Text('ยังไม่ระบุ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ),
        _buildMuscleCountBadge(0),
      ]);
    }
    final sorted = [...group.mappings]..sort((a, b) {
        final aMain = a['type'] == 'หลัก' ? 0 : 1;
        final bMain = b['type'] == 'หลัก' ? 0 : 1;
        return aMain.compareTo(bMain);
      });
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [...sorted.map(_buildMuscleChipReadOnly), _buildMuscleCountBadge(sorted.length)],
    );
  }

  static const _linkStatusLabels = {
    _LinkStatus.all: 'ทุกสถานะ',
    _LinkStatus.linked: 'เชื่อมแล้ว',
    _LinkStatus.unlinked: 'ยังไม่เชื่อม',
  };

  // legend อธิบายสีหลัก/รอง 1 บรรทัด ใต้ toolbar (บรีฟ UX รอบ 4 ข้อ 2)
  Widget _buildLegend() {
    Widget swatch(Widget chip, String label) => Row(mainAxisSize: MainAxisSize.min, children: [chip, const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(spacing: 20, runSpacing: 4, children: [
        swatch(
          Container(width: 14, height: 14, decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(4))),
          'กล้ามเนื้อหลัก',
        ),
        swatch(
          Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade400))),
          'กล้ามเนื้อรอง',
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRows = _groupedRows;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? (_hasActiveFilter ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['เวทเทรนนิ่ง', 'เชื่อมโยงท่าฝึกกับกล้ามเนื้อ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มการเชื่อมโยง',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อท่าฝึกหรือกล้ามเนื้อ...',
          onSearchChanged: (v) => setState(() {
            _search = v;
            _currentPage = 1;
          }),
          trailing: [
            SizedBox(
              width: 190,
              height: 40,
              child: DropdownButtonFormField<int?>(
                initialValue: _filterMugId,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: Icon(Icons.accessibility_new, size: 18, color: AppColors.primaryGreen),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('ทุกกลุ่มกล้ามเนื้อ', style: TextStyle(fontSize: 13))),
                  ...musclesList.map((m) => DropdownMenuItem<int?>(value: m['mug_id'] as int?, child: Text(m['mug_name'] ?? '', style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (v) => setState(() {
                  _filterMugId = v;
                  _currentPage = 1;
                }),
              ),
            ),
            SizedBox(
              width: 160,
              height: 40,
              child: DropdownButtonFormField<_LinkStatus>(
                initialValue: _filterLinkStatus,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: Icon(Icons.link, size: 18, color: AppColors.primaryGreen),
                ),
                items: _LinkStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(_linkStatusLabels[s]!, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() {
                  _filterLinkStatus = v ?? _LinkStatus.all;
                  _currentPage = 1;
                }),
              ),
            ),
          ],
          resultCount: allRows.length,
          showClearButton: _hasActiveFilter,
          onClearFilters: _clearFilters,
        ),
        _buildLegend(),
        if (_selectedWetIds.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Text('เลือก ${_selectedWetIds.length} ท่าฝึก', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
              const Spacer(),
              TextButton(onPressed: () => setState(() => _selectedWetIds.clear()), child: const Text('ยกเลิกการเลือก')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _handleBulkAddSecondary,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('เพิ่มกล้ามเนื้อรอง'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryGreen, side: const BorderSide(color: AppColors.primaryGreen)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _handleBulkDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบที่เลือก'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.table,
                  onAdd: () => _showForm(),
                  onRetry: _fetchMappings,
                  onClearFilter: _clearFilters,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: LayoutBuilder(builder: (context, constraints) {
                    // สัดส่วนคอลัมน์: checkbox 48px คงที่ / ท่าฝึก 25% ของพื้นที่ที่เหลือ / กล้ามเนื้อ
                    // กินที่เหลือทั้งหมด / จัดการ 100px คงที่ — ให้ตารางเต็มความกว้างเสมอ ไม่เหลือ
                    // ช่องว่างขวามือ (บรีฟ UX รอบ 4 ข้อ 1)
                    // หัก 2px เผื่อเส้นขอบ container ของ AdminDataTable (ดูคอมเมนต์ borderInset ใน
                    // admin_data_table.dart) กันไม่ให้ตกขอบพอดีจนต้องขึ้น horizontal scroll โดยไม่จำเป็น
                    final remaining = (constraints.maxWidth - _colSelectWidth - _actionColumnWidth - 2).clamp(280.0, double.infinity);
                    final colExercise = (remaining * 0.25).clamp(140.0, 320.0);
                    final colMuscles = remaining - colExercise;
                    final columns = [
                      const AdminDataColumn(key: 'select', label: '', width: _colSelectWidth),
                      AdminDataColumn(key: 'exercise', label: 'ท่าฝึก', width: colExercise, sortable: true),
                      AdminDataColumn(key: 'muscles', label: 'กล้ามเนื้อ (หลัก/รอง)', width: colMuscles),
                    ];

                    return AdminDataTable(
                      columns: columns,
                      rowCount: rows.length,
                      actionColumnWidth: _actionColumnWidth,
                      rowHeight: _rowHeight,
                      sortKey: 'exercise',
                      sortAscending: _sortAscending,
                      onSort: (_) => setState(() {
                        _sortAscending = !_sortAscending;
                        _currentPage = 1;
                      }),
                      cellsBuilder: (context, index) {
                        final group = rows[index];
                        final selected = _selectedWetIds.contains(group.wetId);
                        void openPanel() => _showMusclePanel(group.wetId, group.exerciseName);
                        return Row(children: [
                          AdminDataCell(
                            width: _colSelectWidth,
                            child: Checkbox(
                              value: selected,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selectedWetIds.add(group.wetId);
                                } else {
                                  _selectedWetIds.remove(group.wetId);
                                }
                              }),
                            ),
                          ),
                          AdminDataCell(
                            width: colExercise,
                            child: InkWell(
                              onTap: openPanel,
                              child: Text(group.exerciseName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          AdminDataCell(
                            width: colMuscles,
                            child: InkWell(
                              onTap: openPanel,
                              child: _buildMuscleChipsRow(group),
                            ),
                          ),
                        ]);
                      },
                      actionsBuilder: (context, index) {
                        final group = rows[index];
                        final hasMappings = group.mappings.isNotEmpty;
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'แก้ไขกล้ามเนื้อ',
                            icon: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: () {
                              Tooltip.dismissAllToolTips();
                              _showMusclePanel(group.wetId, group.exerciseName);
                            },
                          ),
                          IconButton(
                            tooltip: 'ลบการเชื่อมโยงทั้งหมด',
                            icon: Icon(Icons.delete_outline, color: hasMappings ? Colors.redAccent : Colors.grey.shade300, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: hasMappings
                                ? () {
                                    Tooltip.dismissAllToolTips();
                                    _handleDeleteGroup(group.wetId, group.exerciseName);
                                  }
                                : null,
                          ),
                        ]);
                      },
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

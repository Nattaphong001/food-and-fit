// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_WEIGHT_EXERCISES : จัดการท่าเวทเทรนนิ่ง (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบท่าฝึกเวทเทรนนิ่ง พร้อมอัปโหลดภาพ/วิดีโอ และกำหนด
//                กล้ามเนื้อโฟกัส (หลัก/รอง) ต่อท่าฝึกแบบอินไลน์ในการ์ดเดียวกัน
// [PAGE_ROUTE] /admin > เวทเทรนนิ่ง > ท่าฝึกเวท
// [USES_FEATURES] WEIGHT_TRAINING
//
// ย้ายจากแอปมือถือ (lib/views/admin/workout/manage_weight_exercises_view.dart)
// Logic CRUD/validate/upload/focus-mapping เหมือนเดิมทุกจุด (COPY) — คงเป็นการ์ดต่อท่าฝึก
// เหมือนมือถือ (ไม่บังคับ DataTable) เพราะแต่ละการ์ดมี chip กล้ามเนื้อโฟกัสที่ต้องแตะ/กดค้าง
// แยกทีละอันได้ ใส่ใน cell ตารางจะกดยากกว่าเดิม — ปรับแค่ความกว้าง responsive (grid 2 คอลัมน์
// บนจอกว้าง) + filter chip ความยาก แทน AppBar/FAB มือถือ
// header/filter/pagination ใช้ AdminPageHeader + AdminFilterBar + AdminPaginationBar
// (client-side pagination ตาม pattern เดียวกับ manage_muscle_group_view.dart — backend
// ยังไม่รองรับ page/limit) — filter chip ความยาก (เดิม) ย้ายไปอยู่ trailing ของ AdminFilterBar
// flutter_inappwebview -> YoutubeEmbedView (เหตุผลเดียวกับ manage_cardio_activities_view.dart)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/utils/api_error.dart';
import '../../../core/utils/duplicate_name_check.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/admin_breadcrumb.dart';
import '../../../core/widgets/admin_data_table.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../core/widgets/youtube_embed_view.dart';
import '../../../services/api_client.dart';


class ManageWeightExercisesView extends StatefulWidget {
  // เปิดจากการคลิกการ์ดกลุ่มกล้ามเนื้อ (drill-down, บรีฟ P2 ข้อ 1) — พรีเซ็ตตัวกรองกลุ่มกล้ามเนื้อ
  // ให้ทันที ไม่ต้องเลือกจาก dropdown ซ้ำ; null = เปิดจากเมนู sidebar ปกติ ไม่ล็อกตัวกรอง
  final int? initialMugId;
  // เรียกตอนกดปุ่ม back ตอนดูแบบ drill-down (แทนที่ Navigator.pop เดิม เพราะตอนนี้ฝัง
  // เนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell ไม่ใช่ route ที่ pop ได้)
  final VoidCallback? onBack;
  const ManageWeightExercisesView({super.key, this.initialMugId, this.onBack});

  @override
  State<ManageWeightExercisesView> createState() => _ManageWeightExercisesViewState();
}

class _ManageWeightExercisesViewState extends State<ManageWeightExercisesView> {
  List<dynamic> exercises = [];
  List<Map<String, dynamic>> musclesList = [];
  Map<int, List<Map<String, dynamic>>> focusMap = {};
  int _total = 0;

  bool _isLoading = true;
  bool _hasError = false;
  bool _isNetworkError = false;
  String _searchQuery = '';
  int _filterDiff = 0;
  late int? _filterMugId = widget.initialMugId;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ค่าเริ่มต้นเป็นการ์ด (มีรูป/คำอธิบาย/เทคนิคที่ตารางแสดงไม่หมด) สลับไปตารางได้เวลาต้องแก้
  // ข้อมูลจำนวนมาก (บรีฟ P2 ข้อ 7 — เหมือนที่ทำให้หน้าฐานข้อมูลโภชนาการไปแล้ว)
  bool _isTableView = false;

  // ยกเลิก request เก่าที่ยังไม่ตอบกลับก่อนยิงใหม่ทุกครั้ง (ค้นหา/เปลี่ยนหน้า/เปลี่ยนตัวกรอง)
  // กัน response เก่ามาทีหลัง response ใหม่แล้วทับผลลัพธ์ผิด (มาตรฐานตัวกรอง Flutter integration ข้อ 2)
  CancelToken? _cancelToken;

  // ชื่อกลุ่มกล้ามเนื้อที่กำลังกรองอยู่ (สำหรับ AdminBreadcrumb ตอน drill-down) — ผูกกับ
  // _filterMugId/musclesList ที่มีอยู่แล้ว ไม่สร้าง state ใหม่
  String? get _filterMugName {
    for (final m in musclesList) {
      if (m['mug_id'] == _filterMugId) return m['mug_name']?.toString();
    }
    return null;
  }

  String get baseUrl => ApiClient.serverUrl;
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _loadAll();
    AdminDataBus.muscleGroups.addListener(_onMuscleGroupsChanged);
  }

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    AdminDataBus.muscleGroups.removeListener(_onMuscleGroupsChanged);
    super.dispose();
  }

  // หน้านี้ถูก cache ค้างไว้ใน IndexedStack ของ admin_shell_view ไม่ได้ rebuild ตอนสลับเมนู —
  // ฟัง AdminDataBus แทน เพื่อรู้ตัวทันทีเวลาหน้ากลุ่มกล้ามเนื้อ (คนละหน้า คนละ state) เพิ่ม/แก้/ลบสำเร็จ
  Future<void> _onMuscleGroupsChanged() async {
    if (!mounted) return;
    await _fetchMuscles();
    if (!mounted) return;
    final filterStillValid = musclesList.any((m) => m['mug_id'] == _filterMugId);
    if (_filterMugId != null && !filterStillValid) {
      setState(() => _filterMugId = null);
      _fetchExercises();
    }
  }

  // โหลดครั้งแรกที่เปิดหน้า + ตอน retry เต็มหน้า/หลัง CRUD สำเร็จ — ต้องดึง musclesList/focusMap
  // (master data ที่ไม่ผูกกับตัวกรอง/หน้า) ใหม่ด้วยเสมอ ต่างจาก _fetchExercises เดี่ยวๆ ที่ใช้ตอน
  // แค่เปลี่ยนตัวกรอง/หน้า (ไม่ต้องดึง 2 อย่างนั้นซ้ำ)
  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _isNetworkError = false;
    });
    await Future.wait([_fetchExercises(), _fetchMuscles(), _fetchFocusMap()]);
    if (mounted) setState(() => _isLoading = false);
  }

  // --------------------------------------------
  // [FEATURE] WEIGHT_TRAINING
  // [FUNCTION] _fetchExercises
  // [DESCRIPTION] ดึงรายการท่าฝึกเวทจาก GET /api/admin/exercises/weights ตามตัวกรอง+หน้าปัจจุบัน
  //               (server-side search+filter+pagination แทนการโหลดทั้งหมดมากรองใน Dart แบบเดิม)
  //               ยกเลิก request ก่อนหน้านี้ที่ยังไม่ตอบกลับก่อนยิงใหม่เสมอ กัน race condition
  // [INPUT] _searchQuery, _filterMugId, _filterDiff, _currentPage, _pageSize (state ปัจจุบัน)
  // [OUTPUT] อัปเดต exercises/_total หรือ _hasError/_isNetworkError ตามผลลัพธ์
  // [RELATED] COMMON_UI
  // --------------------------------------------
  Future<void> _fetchExercises() async {
    _cancelToken?.cancel('superseded');
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _isNetworkError = false;
    });

    final params = <String, String>{
      if (_searchQuery.trim().isNotEmpty) 'search': _searchQuery.trim(),
      if (_filterMugId != null) 'muscle_group_id': '$_filterMugId',
      if (_filterDiff != 0) 'difficulty_id': '$_filterDiff',
      'page': '$_currentPage',
      'page_size': '$_pageSize',
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    try {
      final res = await _api.get('/admin/exercises/weights?$query', cancelToken: token);
      if (!mounted || token.isCancelled) return;
      if (res.statusCode == 200) {
        final data = res.data as Map;
        setState(() {
          exercises = (data['data'] ?? []) as List;
          _total = (data['total'] as num?)?.toInt() ?? 0;
          _isLoading = false;
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
      debugPrint("Fetch exercises error: $e");
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Future<void> _fetchMuscles() async {
    try {
      final res = await _api.get('/exercises/muscle-groups');
      if (res.statusCode == 200) {
        final decoded = res.data;
        List<dynamic> list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? []) as List : decoded is List ? decoded : [];
        if (mounted) setState(() => musclesList = List<Map<String, dynamic>>.from(list));
      }
    } catch (e) {
      debugPrint("Fetch muscles error: $e");
    }
  }

  Future<void> _fetchFocusMap() async {
    try {
      final res = await http.get(Uri.parse("$baseUrl/api/exercise-muscles"), headers: _authHeaders);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        List<dynamic> list = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List : decoded is List ? decoded : [];
        final Map<int, List<Map<String, dynamic>>> map = {};
        for (final item in list) {
          final wetId = item['wet_id'] as int?;
          if (wetId == null) continue;
          map.putIfAbsent(wetId, () => []);
          map[wetId]!.add(Map<String, dynamic>.from(item));
        }
        if (mounted) setState(() => focusMap = map);
      }
    } catch (e) {
      debugPrint("Fetch focus map error: $e");
    }
  }

  void _showLoading() => showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)));

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  // --------------------------------------------
  // [FEATURE] WEIGHT_TRAINING
  // [FUNCTION] _clearFilters
  // [DESCRIPTION] รีเซ็ตช่องค้นหาและตัวกรองเสริมทั้งหมด (กลุ่มกล้ามเนื้อ + ระดับความยาก) กลับ
  //               ค่าเริ่มต้น — ใช้ร่วมกันทั้งปุ่ม "ล้างตัวกรอง" บน AdminFilterBar และปุ่มในหน้า noResult
  // [INPUT] -
  // [OUTPUT] -
  // [RELATED] COMMON_UI
  // --------------------------------------------
  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _filterDiff = 0;
      _filterMugId = null;
      _currentPage = 1;
    });
    _fetchExercises();
  }

  String _getDiffText(int diff) => diff == 1 ? "ง่าย" : diff == 2 ? "ปานกลาง" : diff == 3 ? "ยาก" : "ไม่ระบุ";

  Color _getDiffColor(int diff) => diff == 1 ? Colors.green : diff == 2 ? Colors.amber.shade700 : diff == 3 ? Colors.red : Colors.grey;

  String? _toEmbedUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final regExp = RegExp(r'(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url.trim());
    if (match != null) return 'https://www.youtube.com/embed/${match.group(1)}?playsinline=1&rel=0';
    return null;
  }

  // เปิดวิดีโอในแท็บใหม่แทนการฝัง iframe ใน Dialog — Flutter Web มีข้อจำกัดของ engine ที่
  // platform view (HtmlElementView อย่าง iframe/<video>) ที่อยู่ใน showDialog/Overlay จะไม่รับ
  // pointer event เลยแม้ CSS/DOM จะดูปกติทุกอย่าง (ยืนยันแล้วด้วยการคลิกจริงทั้งจากผู้ใช้และ
  // Playwright — เห็นวิดีโอ/ปุ่มเล่นแต่กดไม่ได้สักปุ่ม) เปิดแท็บใหม่ไปที่หน้า YouTube จริงเลย
  // ทำงานได้ 100% ไม่ต้องพึ่ง platform view ใน dialog เลย
  void _showVideoDialog(String videoUrl) {
    final embedUrl = _toEmbedUrl(videoUrl);
    if (embedUrl == null) {
      _showSnackBar('ลิงก์วิดีโอไม่ถูกต้อง');
      return;
    }
    web.window.open(videoUrl, '_blank');
  }

  // เล่นวิดีโอ loop (ไฟล์อัปโหลด ไม่ใช่ลิงก์ YouTube) — badge "Loop" บนการ์ดกดแล้วเปิดแท็บใหม่
  // (เหตุผลเดียวกับ _showVideoDialog — Chrome มี native video player ให้เองเมื่อเปิด .mp4 ตรงๆ)
  void _showLoopVideoDialog(String loopVideoPath) {
    final url = ApiClient.prefixPath(loopVideoPath);
    if (url == null) {
      _showSnackBar('ไฟล์วิดีโอ loop ไม่ถูกต้อง');
      return;
    }
    web.window.open(url, '_blank');
  }

  Future<void> _handleSaveExercise(
    Map<String, dynamic>? item,
    String name, String desc, String technique, int diff, int equipment, int exerciseType, String videoLink,
    File? imageFile, Uint8List? imageBytes, String? imageFileName,
    File? loopVideoFile, Uint8List? loopVideoBytes, String? loopVideoFileName, {
    List<Map<String, dynamic>>? pendingFocus,
  }) async {
    if (name.trim().isEmpty) return;
    final isEdit = item != null;

    // เช็คชื่อซ้ำจริงทำที่ฟอร์ม (เช็คสด ครอบทั้งระบบผ่าน API ไม่ใช่แค่หน้าปัจจุบัน — ดู
    // _showExerciseForm) ตรงนี้เหลือแค่ unique constraint ฝั่ง backend เป็นด่านสุดท้าย

    _showLoading();
    try {
      final url = isEdit ? "$baseUrl/api/exercises/weights/${item['wet_id'] ?? item['WetID']}" : "$baseUrl/api/exercises/weights";

      var request = http.MultipartRequest(isEdit ? 'PUT' : 'POST', Uri.parse(url));
      request.headers.addAll(_authHeaders);
      request.fields['wet_name'] = name.trim();
      request.fields['wet_description'] = desc;
      request.fields['wet_technique'] = technique;
      request.fields['wet_difficulty'] = diff.toString();
      request.fields['wet_equipment'] = equipment.toString();
      request.fields['wet_exercise_type'] = exerciseType.toString();
      request.fields['wet_video'] = videoLink;

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes('wet_image', imageBytes, filename: imageFileName));
        }
        if (loopVideoBytes != null && loopVideoFileName != null) {
          request.files.add(http.MultipartFile.fromBytes('wet_loop_video', loopVideoBytes, filename: loopVideoFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(await http.MultipartFile.fromPath('wet_image', imageFile.path));
        }
        if (loopVideoFile != null) {
          request.files.add(await http.MultipartFile.fromPath('wet_loop_video', loopVideoFile.path));
        }
      }

      final response = await http.Response.fromStream(await request.send());
      Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // ท่าใหม่พร้อมกล้ามเนื้อโฟกัสที่เลือกไว้ในฟอร์ม (ตอนสร้างยังไม่มี wet_id ยิง API ไม่ได้ —
        // ดู _showExerciseForm) ยิงสร้าง mapping ทีเดียวตอนนี้ที่รู้ wet_id ที่เพิ่งสร้างแล้ว
        int focusFailCount = 0;
        if (!isEdit && pendingFocus != null && pendingFocus.isNotEmpty) {
          try {
            final body = json.decode(response.body);
            num? newId;
            if (body is Map && body['data'] is Map) {
              newId = (body['data'] as Map)['wet_id'] as num?;
            }
            if (newId != null) {
              final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
              for (final f in pendingFocus) {
                final exmType = f['exm_type'] ?? (f['type'] == 'หลัก' ? 1 : 2);
                try {
                  final r = await http.post(
                    Uri.parse("$baseUrl/api/exercise-muscles"),
                    headers: headers,
                    body: json.encode({"exm_type": exmType, "wet_id": newId.toInt(), "mug_id": f['mug_id']}),
                  );
                  if (r.statusCode != 200 && r.statusCode != 201) focusFailCount++;
                } catch (_) {
                  focusFailCount++;
                }
              }
            } else {
              focusFailCount = pendingFocus.length;
            }
          } catch (_) {
            focusFailCount = pendingFocus.length;
          }
        }
        ApiClient.clearCache();
        await _loadAll();
        Navigator.pop(context);
        if (focusFailCount > 0) {
          _showSnackBar('เพิ่มท่าสำเร็จ แต่เพิ่มกล้ามเนื้อโฟกัสไม่สำเร็จ $focusFailCount รายการ กรุณาเพิ่มใหม่', type: AppAlertType.warning);
        } else {
          _showSnackBar(isEdit ? 'แก้ไขสำเร็จ' : 'เพิ่มข้อมูลสำเร็จ', type: AppAlertType.success);
        }
      } else {
        // backend แปล unique constraint error เป็นข้อความไทยไว้แล้ว (เช่น "มีท่าฝึกชื่อนี้อยู่แล้ว"
        // ตอน 409) ดึง response.body มาใช้แทนโชว์แค่ status code เดิม
        String msg = 'เกิดข้อผิดพลาด (${response.statusCode})';
        try {
          final body = json.decode(response.body);
          if (body is Map && body['error'] != null) msg = body['error'].toString();
        } catch (_) {}
        _showSnackBar(msg);
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _handleDeleteExercise(int id, String name) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$name" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      _showLoading();
      try {
        final res = await http.delete(Uri.parse("$baseUrl/api/exercises/weights/$id"), headers: _authHeaders);
        Navigator.pop(context);
        if (res.statusCode == 200) {
          ApiClient.clearCache();
          await _loadAll();
          showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
        } else {
          try {
            final body = json.decode(res.body);
            _showSnackBar(body['error'] ?? 'ลบไม่สำเร็จ');
          } catch (_) {
            _showSnackBar('ลบไม่สำเร็จ (${res.statusCode})');
          }
        }
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('เกิดข้อผิดพลาด: $e');
      }
    }
  }

  Future<void> _handleSaveFocus(int wetId, int mugId, int typeInt, {int? editId, required List<Map<String, dynamic>> existingFocusList}) async {
    final sameMuscle = existingFocusList.any((f) {
      if (editId != null && (f['id'] ?? f['exm_id']) == editId) return false;
      return f['mug_id'] == mugId;
    });
    if (sameMuscle) {
      _showSnackBar('กล้ามเนื้อนี้ถูกเพิ่มในท่านี้แล้ว', type: AppAlertType.warning);
      return;
    }
    if (typeInt == 1) {
      final alreadyHasMain = existingFocusList.any((f) {
        if (editId != null && (f['id'] ?? f['exm_id']) == editId) return false;
        final fType = f['exm_type'] ?? f['type'];
        return fType == 1 || fType == 'หลัก';
      });
      if (alreadyHasMain) {
        _showSnackBar('ท่านี้มีกล้ามเนื้อหลักอยู่แล้ว', type: AppAlertType.warning);
        return;
      }
    }

    _showLoading();
    try {
      final body = json.encode({"exm_type": typeInt, "wet_id": wetId, "mug_id": mugId});
      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      final url = editId == null ? "$baseUrl/api/exercise-muscles" : "$baseUrl/api/exercise-muscles/$editId";
      final res = editId == null ? await http.post(Uri.parse(url), headers: headers, body: body) : await http.put(Uri.parse(url), headers: headers, body: body);

      Navigator.pop(context);
      Navigator.pop(context);

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _fetchFocusMap();
        setState(() {});
        _showSnackBar(editId == null ? 'เพิ่มโฟกัสสำเร็จ' : 'แก้ไขโฟกัสสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${res.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _handleDeleteFocus(int id, String muscleName, String exerciseName) async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$muscleName" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      _showLoading();
      try {
        final res = await http.delete(Uri.parse("$baseUrl/api/exercise-muscles/$id"), headers: _authHeaders);
        Navigator.pop(context);
        if (res.statusCode == 200) {
          await _fetchFocusMap();
          setState(() {});
          showAdminTopToast(context, 'ลบ "$muscleName" เรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${res.statusCode}');
        }
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('เกิดข้อผิดพลาด: $e');
      }
    }
  }

  void _showExerciseForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['wet_name'] ?? item?['WetName'] ?? '');
    final descCtrl = TextEditingController(text: item?['wet_description'] ?? item?['WetDescription'] ?? '');
    final List<TextEditingController> techniqueItemCtrls = (item?['wet_technique'] ?? item?['WetTechnique'] ?? '')
        .toString()
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => TextEditingController(text: s))
        .toList();
    if (techniqueItemCtrls.isEmpty) techniqueItemCtrls.add(TextEditingController());
    final videoCtrl = TextEditingController(text: item?['wet_video'] ?? item?['WetVideo'] ?? '');
    final bool isAdding = item == null;
    final int? lockedDiff = isAdding && _filterDiff != 0 ? _filterDiff : null;
    final bool showDiffSelector = lockedDiff == null;

    int selectedDiff = lockedDiff ?? (item?['wet_difficulty'] ?? item?['WetDifficulty']) ?? 1;
    int selectedEquipment = (item?['wet_equipment'] ?? item?['WetEquipment']) ?? 5;
    int selectedExerciseType = (item?['wet_exercise_type'] ?? item?['WetExerciseType']) ?? 1;

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    File? selectedLoopVideo;
    Uint8List? selectedLoopVideoBytes;
    String? selectedLoopVideoName;
    final existingLoopVideo = (item?['wet_loop_video'] ?? item?['WetLoopVideo'] ?? '').toString();
    final picker = ImagePicker();
    String? previewEmbedUrl = _toEmbedUrl(item?['wet_video'] ?? item?['WetVideo']);

    // กล้ามเนื้อโฟกัส (หลัก/รอง) — ย้ายมาให้แก้ในฟอร์มนี้ตรงๆ แทนต้องปิดฟอร์มแล้วไปกดที่การ์ด/
    // ตารางแยกต่างหาก (เดิมมีแค่ _showFocusForm) ตอนแก้ไข (มี wetId แล้ว) ยิง API ทันทีทีละรายการ
    // เหมือนเดิมทุกจุด ตอนเพิ่มท่าใหม่ (ยังไม่มี wetId) เก็บไว้ใน focusList ก่อนเฉยๆ แล้วค่อยยิง
    // API สร้าง mapping ทีเดียวหลังสร้างท่าสำเร็จ (ดู _handleSaveExercise)
    final int? wetId = item?['wet_id'] ?? item?['WetID'];
    List<Map<String, dynamic>> focusList = wetId != null ? List<Map<String, dynamic>>.from(focusMap[wetId] ?? []) : [];
    int? addMugId;
    String addType = 'หลัก';

    // เช็คชื่อซ้ำครอบทั้งระบบสด — debounce 400ms เหมือนช่องค้นหา + cancel request เก่าตอนพิมพ์ต่อ
    // (มาตรฐานตัวกรอง Flutter integration ข้อ 2) ห้าม block ปุ่มบันทึกถ้าเช็คไม่สำเร็จ (network/
    // server error) ให้ unique constraint ฝั่ง backend เป็นด่านสุดท้ายแทน (ดู _handleSaveExercise)
    Timer? nameCheckDebounce;
    CancelToken? nameCheckToken;
    bool isDuplicateName = false;
    bool dialogClosed = false;

    InputDecoration fieldDeco({IconData? icon, String? hint}) => InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon: icon != null ? Icon(icon, color: AppColors.primaryGreen, size: 20) : null,
        );

    Widget lbl(String label, Widget field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 6),
            field,
          ],
        );

    Widget chipSelector<T>({
      required List<(T value, String label, IconData icon)> options,
      required T selected,
      required void Function(T) onSelect,
    }) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final bool isSel = o.$1 == selected;
            return InkWell(
              onTap: () => onSelect(o.$1),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isSel ? AppColors.primaryGreen.withValues(alpha: 0.14) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSel ? AppColors.primaryGreen : Colors.grey.shade300, width: isSel ? 1.6 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(o.$3, size: 17, color: isSel ? AppColors.primaryGreen : Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(o.$2, style: TextStyle(fontSize: 13, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? Colors.black87 : Colors.black54)),
                ]),
              ),
            );
          }).toList(),
        );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // --------------------------------------------
          // [FEATURE] WEIGHT_TRAINING
          // [FUNCTION] _showExerciseForm (checkNameDuplicate — เช็คชื่อซ้ำสดครอบทั้งระบบ)
          // [DESCRIPTION] เรียก checkExactNameDuplicate ผ่าน endpoint ค้นหาเดิม (ไม่สร้างใหม่)
          //               debounce 400ms + cancel request เก่าทุกครั้งที่พิมพ์ต่อ ไม่นับซ้ำกับ
          //               รายการที่กำลังแก้ไขอยู่เอง (excludeId)
          // [INPUT] ชื่อที่พิมพ์ในช่องชื่อท่าฝึก, item?['wet_id'] (ตอนแก้ไข)
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
                  path: '/admin/exercises/weights',
                  nameField: 'wet_name',
                  idField: 'wet_id',
                  name: value,
                  excludeId: item?['wet_id'] ?? item?['WetID'],
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
            final f = await picker.pickImage(source: ImageSource.gallery);
            if (f != null) {
              final bytes = await f.readAsBytes();
              setModalState(() {
                selectedImageBytes = bytes;
                selectedImageName = f.name;
                if (!kIsWeb) selectedImage = File(f.path);
              });
            }
          }

          Future<void> pickLoopVideo() async {
            final f = await picker.pickVideo(source: ImageSource.gallery);
            if (f != null) {
              setModalState(() => selectedLoopVideoName = f.name);
              if (kIsWeb) {
                final b = await f.readAsBytes();
                setModalState(() => selectedLoopVideoBytes = b);
              } else {
                setModalState(() => selectedLoopVideo = File(f.path));
              }
            }
          }

          // เช็คซ้ำ/เช็คมีหลักแล้วหรือยัง ใช้กติกาเดียวกับ _handleSaveFocus เดิม (ดูฟังก์ชันนั้น)
          // แต่เช็คจาก focusList ในฟอร์มนี้ตรงๆ แทนพารามิเตอร์แยก
          String? focusValidationError(int mugId, int typeInt, {Object? excludeId}) {
            final sameMuscle = focusList.any((f) {
              if (excludeId != null && (f['id'] ?? f['exm_id']) == excludeId) return false;
              return f['mug_id'] == mugId;
            });
            if (sameMuscle) return 'กล้ามเนื้อนี้ถูกเพิ่มในท่านี้แล้ว';
            if (typeInt == 1) {
              final alreadyHasMain = focusList.any((f) {
                if (excludeId != null && (f['id'] ?? f['exm_id']) == excludeId) return false;
                final fType = f['exm_type'] ?? f['type'];
                return fType == 1 || fType == 'หลัก';
              });
              if (alreadyHasMain) return 'ท่านี้มีกล้ามเนื้อหลักอยู่แล้ว';
            }
            return null;
          }

          Future<void> refreshFocusFromServer() async {
            if (wetId == null) return;
            await _fetchFocusMap();
            if (dialogClosed) return;
            setModalState(() => focusList = List<Map<String, dynamic>>.from(focusMap[wetId] ?? []));
          }

          Future<void> addFocusInline() async {
            if (addMugId == null) {
              _showSnackBar('กรุณาเลือกกล้ามเนื้อ');
              return;
            }
            final typeInt = addType == 'หลัก' ? 1 : 2;
            final err = focusValidationError(addMugId!, typeInt);
            if (err != null) {
              _showSnackBar(err, type: AppAlertType.warning);
              return;
            }

            // ท่ายังไม่ถูกสร้าง (isAdding) — ยังไม่มี wetId ยิง API ไม่ได้ เก็บไว้ในฟอร์มก่อน
            // แล้วค่อยยิงทีเดียวหลังสร้างท่าสำเร็จ (ดู _handleSaveExercise)
            if (wetId == null) {
              final mugName = musclesList.firstWhere((m) => m['mug_id'] == addMugId, orElse: () => const {})['mug_name'] ?? '';
              setModalState(() {
                focusList = [...focusList, {'mug_id': addMugId, 'exm_type': typeInt, 'type': addType, 'muscle': mugName, 'id': null}];
                addMugId = null;
                addType = 'หลัก';
              });
              return;
            }

            try {
              final body = json.encode({"exm_type": typeInt, "wet_id": wetId, "mug_id": addMugId});
              final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
              final res = await http.post(Uri.parse("$baseUrl/api/exercise-muscles"), headers: headers, body: body);
              if (dialogClosed) return;
              if (res.statusCode == 200 || res.statusCode == 201) {
                await refreshFocusFromServer();
                if (dialogClosed) return;
                setModalState(() {
                  addMugId = null;
                  addType = 'หลัก';
                });
              } else {
                String msg = 'บันทึกไม่สำเร็จ';
                try {
                  final b = json.decode(res.body);
                  if (b is Map && b['error'] != null) msg = b['error'].toString();
                } catch (_) {}
                _showSnackBar(msg);
              }
            } catch (e) {
              if (!dialogClosed) _showSnackBar('Error: $e');
            }
          }

          Future<void> deleteFocusInline(Map<String, dynamic> f) async {
            final muscleName = (f['muscle'] ?? f['mug_name'] ?? '?').toString();
            final focusId = f['id'] ?? f['exm_id'];

            // รายการที่ยังไม่บันทึกจริง (เพิ่งเพิ่มไว้ระหว่างสร้างท่าใหม่ ยังไม่มี id) — ลบออกจาก
            // state ตรงๆ พอ ไม่ต้องเรียก API/ถามยืนยัน
            if (focusId == null) {
              setModalState(() => focusList = focusList.where((e) => e != f).toList());
              return;
            }

            final confirm = await showAppConfirmDialog(
              context,
              icon: Icons.delete_outline_rounded,
              title: 'ยืนยันการลบ?',
              content: 'ต้องการลบ "$muscleName" ใช่หรือไม่?',
              confirmLabel: 'ลบข้อมูล',
            );
            if (!confirm || dialogClosed) return;

            try {
              final res = await http.delete(Uri.parse("$baseUrl/api/exercise-muscles/$focusId"), headers: _authHeaders);
              if (dialogClosed) return;
              if (res.statusCode == 200) {
                await refreshFocusFromServer();
                if (!dialogClosed) showAdminTopToast(context, 'ลบ "$muscleName" เรียบร้อย');
              } else {
                _showSnackBar('ลบไม่สำเร็จ: ${res.statusCode}');
              }
            } catch (e) {
              if (!dialogClosed) _showSnackBar('เกิดข้อผิดพลาด: $e');
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview = Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['wet_image'] ?? item?['WetImage']) != null && (item?['wet_image'] ?? item?['WetImage']) != "") {
            final imgVal = item!['wet_image'] ?? item['WetImage'];
            final imgUrl = ApiClient.prefixPath(imgVal);
            imagePreview = imgUrl != null ? AdminNetworkImage(imgUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.add_a_photo, size: 40)) : const Icon(Icons.add_a_photo, size: 40);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          final loopVideoLabel = selectedLoopVideoName ?? (existingLoopVideo.isNotEmpty ? existingLoopVideo.split('/').last : null);

          return Dialog(
            backgroundColor: AppColors.dialogBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: 540,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
              decoration: BoxDecoration(color: AppColors.dialogBackground, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                    child: Row(children: [
                      Expanded(child: Text(item == null ? 'เพิ่มท่าฝึกเวท' : 'แก้ไขท่าฝึกเวท', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
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
                                    height: 110,
                                    width: 110,
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
                          lbl('ชื่อท่าฝึก *', TextField(controller: nameCtrl, onChanged: checkNameDuplicate, decoration: fieldDeco(icon: Icons.fitness_center, hint: 'เช่น Bench Press, Squat...'))),
                          if (isDuplicateName) ...[
                            const SizedBox(height: 4),
                            const Text('มีชื่อท่าฝึกนี้ในระบบแล้ว กรุณาใช้ชื่ออื่น', style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: 14),
                          const Text('ระดับความยาก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          if (showDiffSelector)
                            chipSelector<int>(
                              selected: selectedDiff,
                              onSelect: (v) => setModalState(() => selectedDiff = v),
                              options: const [
                                (1, 'ง่าย', Icons.sentiment_satisfied_alt),
                                (2, 'ปานกลาง', Icons.sentiment_neutral),
                                (3, 'ยาก', Icons.local_fire_department),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(color: _getDiffColor(selectedDiff).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _getDiffColor(selectedDiff).withValues(alpha: 0.35))),
                              child: Row(children: [
                                Icon(Icons.bar_chart, color: _getDiffColor(selectedDiff), size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Text(_getDiffText(selectedDiff), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _getDiffColor(selectedDiff)))),
                              ]),
                            ),
                          const SizedBox(height: 14),
                          const Text('อุปกรณ์', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          chipSelector<int>(
                            selected: selectedEquipment,
                            onSelect: (v) => setModalState(() => selectedEquipment = v),
                            options: const [
                              (1, 'บาร์เบล', Icons.fitness_center),
                              (2, 'ดัมเบล', Icons.sports_gymnastics),
                              (3, 'เครื่องออกกำลังกาย', Icons.settings_input_component),
                              (4, 'สายแรงต้าน (Cable)', Icons.cable),
                              (5, 'น้ำหนักตัว (Bodyweight)', Icons.accessibility_new),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text('ประเภทท่าฝึก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          chipSelector<int>(
                            selected: selectedExerciseType,
                            onSelect: (v) => setModalState(() => selectedExerciseType = v),
                            options: const [
                              (1, 'หลายกลุ่มกล้ามเนื้อ', Icons.category_outlined),
                              (2, 'เฉพาะส่วน', Icons.center_focus_strong_outlined),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text('กล้ามเนื้อโฟกัส', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 2),
                          Text('เลือกกล้ามเนื้อที่ท่านี้ใช้งาน กำหนดเป็นหลัก/รองได้', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          if (focusList.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Text('ยังไม่มีกล้ามเนื้อโฟกัส', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: focusList.map((f) {
                                  final isMain = (f['exm_type'] ?? (f['type'] == 'หลัก' ? 1 : 2)) == 1;
                                  final muscleName = (f['muscle'] ?? f['mug_name'] ?? '?').toString();
                                  final chipColor = isMain ? AppColors.primaryGreen : Colors.grey.shade600;
                                  return Container(
                                    padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
                                    decoration: BoxDecoration(
                                      color: isMain ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isMain ? AppColors.primaryGreen.withValues(alpha: 0.4) : Colors.grey.shade300, width: 0.7),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(isMain ? Icons.star_rounded : Icons.star_border_rounded, size: 11, color: chipColor),
                                      const SizedBox(width: 3),
                                      Text(muscleName, style: TextStyle(fontSize: 11, color: chipColor, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => deleteFocusInline(f),
                                        child: Icon(Icons.close_rounded, size: 13, color: chipColor.withValues(alpha: 0.7)),
                                      ),
                                    ]),
                                  );
                                }).toList(),
                              ),
                            ),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<int>(
                                initialValue: addMugId,
                                isExpanded: true,
                                decoration: fieldDeco(hint: 'เลือกกล้ามเนื้อ'),
                                items: musclesList.map((e) => DropdownMenuItem<int>(value: e['mug_id'], child: Text(e['mug_name'] ?? '', overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setModalState(() => addMugId = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: addType,
                                decoration: fieldDeco(),
                                items: const [
                                  DropdownMenuItem(value: 'หลัก', child: Text('หลัก')),
                                  DropdownMenuItem(value: 'รอง', child: Text('รอง')),
                                ],
                                onChanged: (v) => setModalState(() => addType = v ?? 'หลัก'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: IconButton.filled(
                                onPressed: addFocusInline,
                                icon: const Icon(Icons.add),
                                style: IconButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.black),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          lbl('รายละเอียดวิธีฝึก', TextField(controller: descCtrl, minLines: 3, maxLines: 6, keyboardType: TextInputType.multiline, decoration: fieldDeco(icon: Icons.description, hint: 'อธิบายวิธีการทำท่านี้...'))),
                          const SizedBox(height: 14),
                          Text('เทคนิคการฝึก', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
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
                                    decoration: fieldDeco(hint: 'ขั้นตอนที่ ${idx + 1}...'),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
                                  tooltip: 'ลบข้อนี้',
                                  onPressed: techniqueItemCtrls.length == 1
                                      ? null
                                      : () => setModalState(() => techniqueItemCtrls.removeAt(idx)),
                                ),
                              ]),
                            );
                          }),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setModalState(() => techniqueItemCtrls.add(TextEditingController())),
                              icon: const Icon(Icons.add, size: 18, color: AppColors.primaryGreen),
                              label: const Text('เพิ่มขั้นตอน', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _videoFieldBlock(
                            icon: Icons.play_circle_outline,
                            iconColor: Colors.redAccent,
                            title: 'วิดีโอสอน (YouTube)',
                            helper: 'วางลิงก์ YouTube (ต้องขึ้นต้นด้วย https://) ของวิดีโอสอนเต็ม แสดงในหน้ารายละเอียดท่าฝึก',
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              TextField(
                                controller: videoCtrl,
                                onChanged: (v) => setModalState(() => previewEmbedUrl = _toEmbedUrl(v)),
                                decoration: InputDecoration(
                                  hintText: 'https://youtube.com/...',
                                  filled: true, fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                              if (previewEmbedUrl != null) ...[
                                const SizedBox(height: 12),
                                SizedBox(height: 200, width: double.infinity, child: YoutubeEmbedView(embedUrl: previewEmbedUrl!, borderRadius: '12px')),
                              ],
                            ]),
                          ),
                          const SizedBox(height: 16),
                          _videoFieldBlock(
                            icon: Icons.loop,
                            iconColor: AppColors.primaryGreen,
                            title: 'วิดีโอ Loop (ระหว่างฝึก)',
                            helper: 'อัปโหลดไฟล์วิดีโอสั้น (MP4) เล่นวนซ้ำ แสดงระหว่างฝึกในแอปมือถือ ไม่บังคับกรอก',
                            child: InkWell(
                              onTap: pickLoopVideo,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                                child: Row(children: [
                                  const Icon(Icons.upload_file, color: AppColors.primaryGreen, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(loopVideoLabel ?? 'แตะเพื่อเลือกไฟล์วิดีโอ loop', overflow: TextOverflow.ellipsis)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton(
                              onPressed: isDuplicateName ? null : () => _handleSaveExercise(item, nameCtrl.text, descCtrl.text, techniqueItemCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).join('\n'), selectedDiff, selectedEquipment, selectedExerciseType, videoCtrl.text, selectedImage, selectedImageBytes, selectedImageName, selectedLoopVideo, selectedLoopVideoBytes, selectedLoopVideoName, pendingFocus: wetId == null ? focusList : null),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
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

  void _showFocusForm(int wetId, List<Map<String, dynamic>> existingList, {Map<String, dynamic>? editItem}) {
    int? selectedMugId = editItem?['mug_id'];
    String selectedType = editItem?['type'] ?? 'หลัก';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: AppColors.dialogBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(editItem == null ? 'เพิ่มกล้ามเนื้อโฟกัส' : 'แก้ไขกล้ามเนื้อโฟกัส', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close, size: 20, color: Colors.grey), onPressed: () => Navigator.pop(context)),
                  ]),
                  const SizedBox(height: 20),
                  const Text('เลือกกล้ามเนื้อ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: selectedMugId,
                    decoration: const InputDecoration(
                      filled: true, fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    items: musclesList.map((e) => DropdownMenuItem<int>(value: e['mug_id'], child: Text(e['mug_name'] ?? ''))).toList(),
                    onChanged: (v) => setModalState(() => selectedMugId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text('ประเภทกล้ามเนื้อ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['หลัก', 'รอง'].map((type) {
                      final isSelected = selectedType == type;
                      final color = type == 'หลัก' ? AppColors.primaryGreen : Colors.blueGrey;
                      final icon = type == 'หลัก' ? Icons.star_rounded : Icons.star_border_rounded;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedType = type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 1.8 : 1)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
                              const SizedBox(width: 6),
                              Text(type, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? color : Colors.grey)),
                            ]),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedMugId == null) {
                          _showSnackBar('กรุณาเลือกกล้ามเนื้อ');
                          return;
                        }
                        _handleSaveFocus(wetId, selectedMugId!, selectedType == 'หลัก' ? 1 : 2, editId: editItem?['id'], existingFocusList: existingList);
                      },
                      child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static final _diffFilters = [
    [0, 'ทั้งหมด', Colors.grey],
    [1, 'ง่าย', Colors.green],
    [2, 'ปานกลาง', Colors.amber.shade700],
    [3, 'ยาก', Colors.red],
  ];

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

  // คอลัมน์ thumb/ระดับ/จัดการ เป็นเนื้อหาสั้นตายตัว กว้างคงที่พอดีเนื้อหา ส่วน ชื่อ/อุปกรณ์/
  // กล้ามเนื้อโฟกัส ยืด-หดตามพื้นที่จอจริงเสมอ (สัดส่วน 30/18/52% ของพื้นที่ที่เหลือ) เพื่อให้
  // คอลัมน์ "จัดการ" ชิดขวาสุดพอดีทุกขนาดจอโดยไม่ต้องเดา px คงที่ — กว้างไม่พอ (ต่ำกว่า min)
  // ค่อย fallback ไปเปิด scroll แนวนอนของ AdminDataTable เอง
  static const double _thumbW = 60;
  static const double _diffW = 130;
  static const double _actionW = 90;
  static const double _nameMin = 220, _equipMin = 130, _muscleMin = 260;

  // มุมมองตาราง (บรีฟ P2 ข้อ 7) — chip กล้ามเนื้อโฟกัสยังคลิกสลับหลัก/รอง + ลบได้ inline เหมือนการ์ด
  Widget _buildExerciseTable(List<dynamic> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double reserve = 8; // กันขอบเส้นตาราง ไม่ให้ปัดเข้าโหมด scroll แนวนอนโดยไม่จำเป็น
        final double flexAvailable = constraints.maxWidth - _thumbW - _diffW - _actionW - reserve;
        final double minFlexTotal = _nameMin + _equipMin + _muscleMin;
        final double flexTotal = flexAvailable < minFlexTotal ? minFlexTotal : flexAvailable;
        final double nameW = (flexTotal * 0.30) < _nameMin ? _nameMin : flexTotal * 0.30;
        final double equipW = (flexTotal * 0.18) < _equipMin ? _equipMin : flexTotal * 0.18;
        final double muscleWRaw = flexTotal - nameW - equipW;
        final double muscleW = muscleWRaw < _muscleMin ? _muscleMin : muscleWRaw;

        final columns = [
          AdminDataColumn(key: 'thumb', label: '', width: _thumbW),
          AdminDataColumn(key: 'name', label: 'ชื่อท่าฝึก', width: nameW),
          AdminDataColumn(key: 'diff', label: 'ระดับความยาก', width: _diffW),
          AdminDataColumn(key: 'equipment', label: 'อุปกรณ์', width: equipW),
          AdminDataColumn(key: 'muscles', label: 'กล้ามเนื้อโฟกัส', width: muscleW),
        ];

        return AdminDataTable(
          columns: columns,
          rowCount: rows.length,
          actionColumnWidth: _actionW,
          rowHeight: 80,
          cellsBuilder: (context, index) {
            final item = rows[index];
            final String? imgPath = item['wet_image'] ?? item['WetImage'];
            final int diff = (item['wet_difficulty'] ?? item['WetDifficulty']) ?? 1;
            final int wetId = item['wet_id'] ?? item['WetID'] ?? 0;
            final String name = item['wet_name'] ?? item['WetName'] ?? '';
            final int equipment = (item['wet_equipment'] ?? item['WetEquipment']) ?? 5;
            final List<Map<String, dynamic>> focusList = focusMap[wetId] ?? [];

            return Row(children: [
              AdminDataCell(
                width: _thumbW,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44, height: 44,
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    child: (imgPath != null && imgPath.isNotEmpty && ApiClient.prefixPath(imgPath) != null)
                        ? AdminNetworkImage(ApiClient.prefixPath(imgPath)!, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 20))
                        : const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 20),
                  ),
                ),
              ),
              AdminDataCell(width: nameW, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
              AdminDataCell(width: _diffW, child: _diffBadge(diff)),
              AdminDataCell(width: equipW, child: Text(_equipmentText(equipment), style: const TextStyle(fontSize: 12.5))),
              AdminDataCell(
                width: muscleW,
            child: SizedBox(
              height: 64,
              child: Align(
                alignment: Alignment.centerLeft,
                child: focusList.isEmpty
                    ? GestureDetector(
                        onTap: () => _showFocusForm(wetId, focusList),
                        child: const Text('+ เพิ่มกล้ามเนื้อโฟกัส', style: TextStyle(fontSize: 11.5, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                      )
                    // แสดงแค่ 2 ชิปแรกพอดีกับความสูงแถวคงที่ (rowHeight) ของตาราง — เกินกว่านั้นรวมเป็น
                    // ชิป "+N" กดเปิดตัวจัดการกล้ามเนื้อโฟกัสเต็มรูปแบบแทนการสกอลล์ในเซลล์ (ซึ่งทำให้
                    // scrollbar ของแต่ละแถวโผล่มาคั่นกลางตารางแบบเดิม)
                    : Wrap(
                        spacing: 6, runSpacing: 4,
                        children: [
                          ...focusList.take(2).map((f) => _buildFocusChip(wetId, name, f, focusList)),
                          if (focusList.length > 2)
                            GestureDetector(
                              onTap: () => _showFocusForm(wetId, focusList),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: Text('+${focusList.length - 2}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ]);
          },
          actionsBuilder: (context, index) {
            final item = rows[index];
            final int wetId = item['wet_id'] ?? item['WetID'] ?? 0;
            final String name = item['wet_name'] ?? item['WetName'] ?? '';
            return Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'แก้ไข',
                icon: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen, size: 18),
                onPressed: () {
                  Tooltip.dismissAllToolTips();
                  _showExerciseForm(item: item);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                onPressed: () {
                  Tooltip.dismissAllToolTips();
                  _handleDeleteExercise(wetId, name);
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
    final rows = exercises;

    final AdminListState? stateOverride = _isLoading
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : _total == 0
                ? (_searchQuery.isNotEmpty || _filterDiff != 0 || _filterMugId != null ? AdminListState.noResult : AdminListState.empty)
                : null;

    // เปิดจากการ์ดกลุ่มกล้ามเนื้อ = แสดงเนื้อหาแทนที่อยู่ในสล็อตเดิมของ sidebar shell (ไม่ push
    // route ใหม่ — sidebar ยังอยู่ตลอด) initialMugId == null = เปิดจาก sidebar เมนูปกติ
    final bool isDrillDown = widget.initialMugId != null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          leading: isDrillDown ? AppBackButton(onTap: widget.onBack) : null,
          breadcrumb: const ['เวทเทรนนิ่ง', 'ท่าฝึกเวทเทรนนิ่ง'],
          onAdd: () => _showExerciseForm(),
          addLabel: 'เพิ่มท่าฝึกเวท',
        ),
        // --------------------------------------------
        // [FEATURE] COMMON_UI
        // [FUNCTION] AdminBreadcrumb (ใช้งานใน ManageWeightExercisesView)
        // [DESCRIPTION] แสดง "กลุ่มกล้ามเนื้อ › ชื่อกลุ่มที่คลิกเข้ามา" เฉพาะตอน drill-down
        //               จากการ์ดกลุ่มกล้ามเนื้อ กดที่ root กลับไปหน้ากลุ่มกล้ามเนื้อ
        // [INPUT] isDrillDown, _filterMugName, widget.onBack
        // [OUTPUT] แถบ breadcrumb เหนือแถบค้นหา/ตัวกรอง
        // [RELATED] WEIGHT_TRAINING
        // --------------------------------------------
        if (isDrillDown)
          AdminBreadcrumb(
            rootLabel: 'กลุ่มกล้ามเนื้อ',
            currentLabel: _filterMugName,
            onRootTap: widget.onBack,
          ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อท่าฝึกเวท...',
          onSearchChanged: (v) {
            setState(() {
              _searchQuery = v;
              _currentPage = 1;
            });
            _fetchExercises();
          },
          trailing: [
            // filter หลัก = กลุ่มกล้ามเนื้อ (dropdown, เด่นกว่า) filter รอง = ระดับความยาก (chip, เล็กกว่า)
            SizedBox(
              width: 190,
              height: 40,
              child: Builder(builder: (context) {
                final muscleItems = <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(value: null, child: Text('ทุกกลุ่มกล้ามเนื้อ', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13))),
                  ...musclesList.map((m) => DropdownMenuItem<int?>(value: m['mug_id'] as int?, child: Text(m['mug_name'] ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))),
                ];
                // กันเข้ามาจากการ์ดกลุ่มกล้ามเนื้อ (initialMugId พรีเซ็ตไว้ตั้งแต่เฟรมแรก) แต่
                // musclesList ยังโหลดไม่เสร็จ (async) — ถ้าไม่กันจุดนี้ initialValue จะไม่ตรงกับ
                // item ไหนเลยชั่วขณะ ทำให้ DropdownButtonFormField throw assertion (จอแดงวาบแล้วหาย
                // เองตอน musclesList โหลดเสร็จ) ใส่ placeholder ไว้ก่อนกัน assertion นี้
                if (_filterMugId != null && !muscleItems.any((item) => item.value == _filterMugId)) {
                  muscleItems.add(DropdownMenuItem<int?>(value: _filterMugId, child: const Text('กำลังโหลด...', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13))));
                }
                return DropdownButtonFormField<int?>(
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
                  items: muscleItems,
                  onChanged: (v) {
                    setState(() {
                      _filterMugId = v;
                      _currentPage = 1;
                    });
                    _fetchExercises();
                  },
                );
              }),
            ),
            ..._diffFilters.map((e) {
              final val = e[0] as int;
              final label = e[1] as String;
              final color = e[2] as Color;
              final sel = _filterDiff == val;
              // "ทั้งหมด" ไม่ใช่ระดับความยาก ให้ใช้ธีมเขียวอ่อน+ขอบเขียวแบบ chip เลือกอยู่ทั่วไป
              // แทนสีเทาทึบเดิม ซึ่งดูเหมือนปุ่ม disabled
              final isAllFilter = val == 0;
              final themeColor = isAllFilter ? AppColors.primaryGreen : color;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _filterDiff = val;
                    _currentPage = 1;
                  });
                  _fetchExercises();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? (isAllFilter ? themeColor.withValues(alpha: 0.12) : themeColor) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: themeColor),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: sel && !isAllFilter ? Colors.white : themeColor)),
                ),
              );
            }),
          ],
          viewToggle: _buildViewToggle(),
          resultCount: _total,
          showClearButton: _searchQuery.isNotEmpty || _filterDiff != 0 || _filterMugId != null,
          onClearFilters: _clearFilters,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: _isTableView ? AdminSkeletonVariant.table : AdminSkeletonVariant.cards,
                  errorMessage: _isNetworkError ? 'เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่' : 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์ ลองใหม่อีกครั้ง',
                  onAdd: () => _showExerciseForm(),
                  onRetry: _loadAll,
                  onClearFilter: _clearFilters,
                )
              : _isTableView
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _buildExerciseTable(rows),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: LayoutBuilder(builder: (context, constraints) {
                        // ใช้ threshold ตรงๆ กับความกว้างที่เหลือจริงในพื้นที่เนื้อหา (หลังหักฝั่ง sidebar/padding
                        // แล้ว) แทน AppBreakpoints.of ซึ่งคาลิเบรตไว้สำหรับความกว้างหน้าต่างทั้งจอ ไม่ใช่ความกว้าง
                        // ที่เหลือตรงนี้ — ใช้ผิดจุดทำให้ tier ไม่เคยขึ้น wide เลย คอลัมน์เลยค้างที่ 2 ตลอด
                        final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 560 ? 2 : 1;
                        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: rows.map((item) {
                            return SizedBox(width: width, child: _buildExerciseCard(item));
                          }).toList(),
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
              _fetchExercises();
            },
            onPageChanged: (v) {
              setState(() => _currentPage = v);
              _fetchExercises();
            },
          ),
      ],
    );

    return content;
  }

  Widget _buildExerciseCard(Map<String, dynamic> item) {
    final String? imgPath = item['wet_image'] ?? item['WetImage'];
    final String? videoUrl = item['wet_video'] ?? item['WetVideo'];
    final bool hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    final String? loopVideoPath = item['wet_loop_video'] ?? item['WetLoopVideo'];
    final bool hasLoopVideo = loopVideoPath != null && loopVideoPath.isNotEmpty;
    final int diff = (item['wet_difficulty'] ?? item['WetDifficulty']) ?? 1;
    final int wetId = item['wet_id'] ?? item['WetID'] ?? 0;
    final String name = item['wet_name'] ?? item['WetName'] ?? '';
    final String desc = item['wet_description'] ?? item['WetDescription'] ?? '';
    final int equipment = (item['wet_equipment'] ?? item['WetEquipment']) ?? 5;
    final int exType = (item['wet_exercise_type'] ?? item['WetExerciseType']) ?? 1;
    final List<Map<String, dynamic>> focusList = focusMap[wetId] ?? [];

    // การ์ดแนวตั้งขนาดใหญ่ (บรีฟรอบ 3 ข้อ 3.2) — รูปใหญ่เต็มความกว้างด้านบน แทนธัมบ์เนล 56x56 เดิม
    // ให้ดูรู้เลยว่าเป็นท่าอะไรโดยไม่ต้องอ่านชื่อ รายละเอียดไล่เป็นบรรทัดด้านล่าง
    // hover state ของปุ่มแก้ไข/ลบ — ตัวแปรอยู่นอก StatefulBuilder.builder ให้จำค่าข้ามการ hover
    // แต่ละครั้งได้ (ตรงกับ pattern เดียวกับหน้ากลุ่มกล้ามเนื้อ/หมวดคาร์ดิโอ) การ์ดนี้ผูก dependency
    // กับ method อื่นในหน้าเยอะ (focusMap, _showFocusForm ฯลฯ) จึงห่อเฉพาะโซนรูปแทนแยกเป็นคลาส
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
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                        child: (imgPath != null && imgPath.isNotEmpty && ApiClient.prefixPath(imgPath) != null)
                            ? AdminNetworkImage(ApiClient.prefixPath(imgPath)!, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 40))
                            : const Icon(Icons.fitness_center, color: AppColors.primaryGreen, size: 40),
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
                        _imageOverlayButton(icon: Icons.edit_outlined, color: AppColors.primaryGreen, onPressed: () => _showExerciseForm(item: item), tooltip: 'แก้ไข'),
                        const SizedBox(width: 6),
                        _imageOverlayButton(icon: Icons.delete_outline, color: Colors.redAccent, onPressed: () => _handleDeleteExercise(wetId, name), tooltip: 'ลบ'),
                      ]),
                    ),
                  ),
                  // ปุ่มวิดีโอ/loop — สไตล์เดียวกับหน้าคาร์ดิโอ (ไอคอนล้วนมุมขวาล่าง + tooltip
                  // แทน badge มีข้อความมุมซ้ายล่างแบบเดิม) ให้ 2 หน้าดูเป็นระบบเดียวกัน
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
                                onTap: () => _showLoopVideoDialog(loopVideoPath),
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
                              onTap: () => _showVideoDialog(videoUrl),
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
          // โซน 1: ชื่อ + badge สรุปคุณสมบัติท่า — บังคับชื่อ 1 บรรทัดกันการ์ดสูงไม่เท่ากัน
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  _diffBadge(diff),
                  _iconBadge(Icons.fitness_center, _equipmentText(equipment)),
                  _iconBadge(exType == 1 ? Icons.groups_outlined : Icons.person_outline, exType == 1 ? 'หลายกลุ่ม' : 'เฉพาะส่วน'),
                ]),
              ],
            ),
          ),
          // โซน 2: กล้ามเนื้อโฟกัส — ห่อกล่องพื้นหลังอ่อนแยกจาก badge ด้านบนชัดเจน แทนที่จะลอยต่อกัน
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primaryGreen.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.center_focus_strong, size: 13, color: AppColors.primaryGreen),
                    const SizedBox(width: 4),
                    const Text('กล้ามเนื้อโฟกัส', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showFocusForm(wetId, focusList),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primaryGreen, width: 0.6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 12, color: AppColors.primaryGreen), SizedBox(width: 2), Text('เพิ่ม', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.w600))]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (focusList.isEmpty)
                    const Text('ยังไม่มีกล้ามเนื้อโฟกัส', style: TextStyle(fontSize: 11, color: AppColors.textMuted))
                  else
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: focusList.map((f) => _buildFocusChip(wetId, name, f, focusList)).toList(),
                    ),
                ],
              ),
            ),
          ),
          // โซน 3: คำอธิบาย — คั่นด้วยเส้นบางจากโซนโฟกัสด้านบน
          if (desc.isNotEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.4)),
            ),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  // chip กล้ามเนื้อโฟกัส — ใช้ร่วมกันทั้งมุมมองการ์ดและตาราง (บรีฟ P2 ข้อ 7) คลิก chip = แก้ไข,
  // คลิก ✕ = ลบ mapping นี้
  Widget _buildFocusChip(int wetId, String exerciseName, Map<String, dynamic> f, List<Map<String, dynamic>> focusList) {
    final isMain = (f['exm_type'] ?? f['type']) == 1 || (f['type'] == 'หลัก');
    final muscleName = f['muscle'] ?? f['mug_name'] ?? '?';
    final focusId = f['id'] ?? f['exm_id'];
    final chipColor = isMain ? AppColors.primaryGreen : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(color: isMain ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: isMain ? AppColors.primaryGreen.withValues(alpha: 0.4) : Colors.grey.shade300, width: 0.7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => _showFocusForm(wetId, focusList, editItem: f),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isMain ? Icons.star_rounded : Icons.star_border_rounded, size: 11, color: chipColor),
            const SizedBox(width: 3),
            Text(muscleName, style: TextStyle(fontSize: 11, color: chipColor, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _handleDeleteFocus(focusId, muscleName, exerciseName),
          child: Icon(Icons.close_rounded, size: 13, color: chipColor.withValues(alpha: 0.7)),
        ),
      ]),
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
          Tooltip.dismissAllToolTips();
          onPressed();
        },
      ),
    );
  }

  Widget _diffBadge(int diff) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: _getDiffColor(diff).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _getDiffColor(diff), width: 0.5)),
        child: Text(_getDiffText(diff), style: TextStyle(fontSize: 11, color: _getDiffColor(diff), fontWeight: FontWeight.w600)),
      );

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

  // badge เล็กบนรูปการ์ด บอกว่าท่านี้มีวิดีโอสอน (YouTube) / วิดีโอ loop (ไฟล์อัปโหลด) ครบไหม
  // ช่วย audit ข้อมูลทั้งชุดได้เร็วโดยไม่ต้องเปิดฟอร์มทีละท่า (บรีฟ video standard ข้อ 4)
  Widget _iconBadge(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.divider, width: 0.7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ]),
      );

  String _equipmentText(int eq) {
    switch (eq) {
      case 1: return 'บาร์เบล';
      case 2: return 'ดัมเบล';
      case 3: return 'เครื่อง';
      case 4: return 'Cable';
      default: return 'Bodyweight';
    }
  }
}

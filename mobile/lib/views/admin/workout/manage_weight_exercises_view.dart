// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage Weight Exercises (จัดการท่าเวทเทรนนิ่ง)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบท่าฝึกเวทเทรนนิ่ง พร้อมอัปโหลดภาพและวิดีโอ

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';
import 'package:myapp/services/exercise_service.dart';

const Color kGreen = Color(0xFF1A9A90);

class ManageWeightExercisesView extends StatefulWidget {
  const ManageWeightExercisesView({super.key});

  @override
  State<ManageWeightExercisesView> createState() =>
      _ManageWeightExercisesViewState();
}

class _ManageWeightExercisesViewState
    extends State<ManageWeightExercisesView> {
  List<dynamic> exercises = [];
  List<Map<String, dynamic>> musclesList = [];
  Map<int, List<Map<String, dynamic>>> focusMap = {};

  bool _isLoading = true;
  bool _isSearching = false;

  String _searchQuery = '';
  int _filterDiff = 0;
  final TextEditingController _searchCtrl = TextEditingController();

  List<dynamic> get _filteredExercises {
    return exercises.where((item) {
      final name =
          (item['wet_name'] ?? item['WetName'] ?? '').toString().toLowerCase();
      final diff = (item['wet_difficulty'] ?? item['WetDifficulty']) ?? 1;
      final matchSearch =
          _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchDiff = _filterDiff == 0 || diff == _filterDiff;
      return matchSearch && matchDiff;
    }).toList()
      ..sort((a, b) {
        final da = (a['wet_difficulty'] ?? a['WetDifficulty']) ?? 1;
        final db = (b['wet_difficulty'] ?? b['WetDifficulty']) ?? 1;
        return da.compareTo(db);
      });
  }

  String get baseUrl   => ApiClient.serverUrl;
  String get serverUrl => '${ApiClient.serverUrl}/';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchExercises(), _fetchMuscles(), _fetchFocusMap()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchExercises() async {
    try {
      final res = await http.get(
          Uri.parse("$baseUrl/api/exercises/weights"),
          headers: _authHeaders);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        List<dynamic> list = decoded is Map
            ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List
            : decoded is List ? decoded : [];
        if (mounted) setState(() => exercises = list);
      }
    } catch (e) {
      debugPrint("Fetch exercises error: $e");
    }
  }

  Future<void> _fetchMuscles() async {
    try {
      final res = await http.get(
          Uri.parse("$baseUrl/api/exercises/muscle-groups"),
          headers: _authHeaders);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        List<dynamic> list = decoded is Map
            ? (decoded['data'] ?? decoded['items'] ?? []) as List
            : decoded is List ? decoded : [];
        if (mounted) {
          setState(() => musclesList = List<Map<String, dynamic>>.from(list));
        }
      }
    } catch (e) {
      debugPrint("Fetch muscles error: $e");
    }
  }

  Future<void> _fetchFocusMap() async {
    try {
      final res = await http.get(
          Uri.parse("$baseUrl/api/exercise-muscles"),
          headers: _authHeaders);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        List<dynamic> list = decoded is Map
            ? (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List
            : decoded is List ? decoded : [];
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

  // ─── Helpers ────────────────────────────────────────────────────────────────

  void _showLoading() => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  String _getDiffText(int diff) =>
      diff == 1 ? "ง่าย" : diff == 2 ? "ปานกลาง" : diff == 3 ? "ยาก" : "ไม่ระบุ";

  Color _getDiffColor(int diff) =>
      diff == 1 ? Colors.green : diff == 2 ? Colors.orange : diff == 3 ? Colors.red : Colors.grey;

  String? _toEmbedUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final regExp = RegExp(
        r'(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})');
    final match = regExp.firstMatch(url.trim());
    if (match != null) {
      return 'https://www.youtube.com/embed/${match.group(1)}?playsinline=1&rel=0';
    }
    return null;
  }

  void _showVideoDialog(String videoUrl) {
    final embedUrl = _toEmbedUrl(videoUrl);
    if (embedUrl == null) {
      _showSnackBar('⚠️ ลิงก์วิดีโอไม่ถูกต้อง');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.redAccent, Color(0xFFB71C1C)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('วิดีโอประกอบ',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: SizedBox(
                height: 240,
                child: InAppWebView(
                  key: ValueKey(embedUrl),
                  initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Save / Delete Exercise ─────────────────────────────────────────────────

  Future<void> _handleSaveExercise(
    Map<String, dynamic>? item,
    String name,
    String desc,
    String technique,
    int diff,
    int equipment,
    int exerciseType,
    String videoLink,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
    File? loopVideoFile,
    Uint8List? loopVideoBytes,
    String? loopVideoFileName,
  ) async {
    if (name.trim().isEmpty) return;
    final isEdit = item != null;
    final currentId = item?['wet_id'] ?? item?['WetID'];

    final isDuplicate = exercises.any((e) {
      final existingName =
          (e['wet_name'] ?? e['WetName'] ?? '').toString().trim().toLowerCase();
      final existingId = e['wet_id'] ?? e['WetID'];
      if (isEdit && existingId == currentId) return false;
      return existingName == name.trim().toLowerCase();
    });
    if (isDuplicate) {
      _showSnackBar('ชื่อท่าฝึก "$name" มีอยู่ในระบบแล้ว', type: AppAlertType.warning);
      return;
    }

    _showLoading();
    try {
      final url = isEdit
          ? "$baseUrl/api/exercises/weights/${item['wet_id'] ?? item['WetID']}"
          : "$baseUrl/api/exercises/weights";

      var request =
          http.MultipartRequest(isEdit ? 'PUT' : 'POST', Uri.parse(url));
      request.headers.addAll(_authHeaders);
      request.fields['wet_name']          = name.trim();
      request.fields['wet_description']  = desc;
      request.fields['wet_technique']    = technique;
      request.fields['wet_difficulty']   = diff.toString();
      request.fields['wet_equipment']    = equipment.toString();
      request.fields['wet_exercise_type'] = exerciseType.toString();
      request.fields['wet_video']        = videoLink;

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'wet_image', imageBytes, filename: imageFileName));
        }
        if (loopVideoBytes != null && loopVideoFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'wet_loop_video', loopVideoBytes, filename: loopVideoFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(
              await http.MultipartFile.fromPath('wet_image', imageFile.path));
        }
        if (loopVideoFile != null) {
          request.files.add(await http.MultipartFile.fromPath(
              'wet_loop_video', loopVideoFile.path));
        }
      }

      final response = await http.Response.fromStream(await request.send());
      Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        ExerciseService.to.clearExerciseCache();
        await _loadAll();
        Navigator.pop(context);
        _showSnackBar(isEdit ? 'แก้ไขสำเร็จ' : 'เพิ่มข้อมูลสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('เกิดข้อผิดพลาด: ${response.statusCode}');
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
        final res = await http.delete(
            Uri.parse("$baseUrl/api/exercises/weights/$id"),
            headers: _authHeaders);
        Navigator.pop(context);
        if (res.statusCode == 200) {
          ExerciseService.to.clearExerciseCache();
          await _loadAll();
          showAdminTopToast(context, 'ลบสำเร็จ');
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

  // ─── Focus Mapping ──────────────────────────────────────────────────────────

  Future<void> _handleSaveFocus(
    int wetId,
    int mugId,
    int typeInt, {
    int? editId,
    required List<Map<String, dynamic>> existingFocusList,
  }) async {
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
      final body =
          json.encode({"exm_type": typeInt, "wet_id": wetId, "mug_id": mugId});
      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_token"
      };
      final url = editId == null
          ? "$baseUrl/api/exercise-muscles"
          : "$baseUrl/api/exercise-muscles/$editId";
      final res = editId == null
          ? await http.post(Uri.parse(url), headers: headers, body: body)
          : await http.put(Uri.parse(url), headers: headers, body: body);

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

  Future<void> _handleDeleteFocus(
      int id, String muscleName, String exerciseName) async {
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
        final res = await http.delete(
            Uri.parse("$baseUrl/api/exercise-muscles/$id"),
            headers: _authHeaders);
        Navigator.pop(context);
        if (res.statusCode == 200) {
          await _fetchFocusMap();
          setState(() {});
          showAdminTopToast(context, 'ลบโฟกัสเรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${res.statusCode}');
        }
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('เกิดข้อผิดพลาด: $e');
      }
    }
  }

  // ─── Forms ──────────────────────────────────────────────────────────────────

  void _showExerciseForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(
        text: item?['wet_name'] ?? item?['WetName'] ?? '');
    final descCtrl = TextEditingController(
        text: item?['wet_description'] ?? item?['WetDescription'] ?? '');
    final techniqueCtrl = TextEditingController(
        text: item?['wet_technique'] ?? item?['WetTechnique'] ?? '');
    final videoCtrl = TextEditingController(
        text: item?['wet_video'] ?? item?['WetVideo'] ?? '');
    // เมื่อ add ใหม่ในระดับที่กรองอยู่ → ล็อค diff อัตโนมัติ, ซ่อน dropdown
    final bool isAdding = item == null;
    final int? lockedDiff = isAdding && _filterDiff != 0 ? _filterDiff : null;
    final bool showDiffSelector = lockedDiff == null;

    int selectedDiff         = lockedDiff ?? (item?['wet_difficulty'] ?? item?['WetDifficulty']) ?? 1;
    int selectedEquipment    = (item?['wet_equipment']     ?? item?['WetEquipment'])     ?? 5;
    int selectedExerciseType = (item?['wet_exercise_type'] ?? item?['WetExerciseType']) ?? 1;

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    File? selectedLoopVideo;
    Uint8List? selectedLoopVideoBytes;
    String? selectedLoopVideoName;
    final existingLoopVideo = (item?['wet_loop_video'] ?? item?['WetLoopVideo'] ?? '').toString();
    final picker = ImagePicker();
    String? previewEmbedUrl =
        _toEmbedUrl(item?['wet_video'] ?? item?['WetVideo']);

    InputDecoration fieldDeco({IconData? icon, String? hint}) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFA0A1A5), fontSize: 13),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon: icon != null ? Icon(icon, color: kGreen, size: 20) : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGreen, width: 1.5),
          ),
        );

    Widget _lbl(String label, Widget field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
            const SizedBox(height: 6),
            field,
          ],
        );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickImage() async {
            final f = await picker.pickImage(source: ImageSource.gallery);
            if (f != null) {
              final bytes = await f.readAsBytes();
              setModalState(() {
                selectedImageBytes = bytes;
                selectedImageName  = f.name;
                if (!kIsWeb) selectedImage = File(f.path);
              });
            }
          }

          Future<void> pickLoopVideo() async {
            final f = await picker.pickVideo(source: ImageSource.gallery);
            if (f != null) {
              setModalState(() {
                selectedLoopVideoName = f.name;
                if (kIsWeb) {
                  f.readAsBytes().then((b) => setModalState(() => selectedLoopVideoBytes = b));
                } else {
                  selectedLoopVideo = File(f.path);
                }
              });
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview =
                Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['wet_image'] ?? item?['WetImage']) != null &&
              (item?['wet_image'] ?? item?['WetImage']) != "") {
            final imgVal = item!['wet_image'] ?? item['WetImage'];
            final imgUrl = ApiClient.prefixPath(imgVal);
            imagePreview = imgUrl != null
                ? Image.network(imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        const Icon(Icons.add_a_photo, size: 40))
                : const Icon(Icons.add_a_photo, size: 40);
          } else {
            imagePreview =
                const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          final loopVideoLabel = selectedLoopVideoName ??
              (existingLoopVideo.isNotEmpty ? existingLoopVideo.split('/').last : null);

          return Dialog(
            backgroundColor: const Color(0xFFF2F2F7),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Title bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item == null ? 'เพิ่มท่าฝึกเวท' : 'แก้ไขท่าฝึกเวท',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20, right: 20, top: 16,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // รูปภาพ
                          Center(
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: pickImage,
                                  child: Container(
                                    height: 110,
                                    width: 110,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: kGreen, width: 2.5),
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: imagePreview,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text('แตะวงกลมเพื่อเปลี่ยนรูปภาพ',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ชื่อท่า
                          _lbl('ชื่อท่าฝึก *',
                            TextField(
                              controller: nameCtrl,
                              decoration: fieldDeco(icon: Icons.fitness_center,
                                  hint: 'เช่น Bench Press, Squat...'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ระดับความยาก
                          const Text('ระดับความยาก',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          if (showDiffSelector)
                            DropdownButtonFormField<int>(
                              value: selectedDiff,
                              decoration: fieldDeco(icon: Icons.bar_chart),
                              dropdownColor: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text("ง่าย")),
                                DropdownMenuItem(
                                    value: 2, child: Text("ปานกลาง")),
                                DropdownMenuItem(value: 3, child: Text("ยาก")),
                              ],
                              onChanged: (v) =>
                                  setModalState(() => selectedDiff = v!),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _getDiffColor(selectedDiff).withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _getDiffColor(selectedDiff).withOpacity(0.35),
                                    width: 1),
                              ),
                              child: Row(children: [
                                Icon(Icons.bar_chart,
                                    color: _getDiffColor(selectedDiff), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _getDiffText(selectedDiff),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _getDiffColor(selectedDiff)),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _getDiffColor(selectedDiff).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('อัตโนมัติ',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _getDiffColor(selectedDiff),
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                          const SizedBox(height: 12),

                          // รายละเอียด
                          _lbl('รายละเอียดวิธีฝึก',
                            TextField(
                              controller: descCtrl,
                              decoration: fieldDeco(icon: Icons.description,
                                  hint: 'อธิบายวิธีการทำท่านี้...'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // เทคนิค
                          _lbl('เทคนิคการฝึก',
                            TextField(
                              controller: techniqueCtrl,
                              decoration: fieldDeco(icon: Icons.tips_and_updates_outlined,
                                  hint: 'เทคนิคหรือข้อควรระวัง...'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // อุปกรณ์
                          _lbl('อุปกรณ์',
                          DropdownButtonFormField<int>(
                            value: selectedEquipment,
                            decoration: fieldDeco(icon: Icons.sports_gymnastics),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("บาร์เบล")),
                              DropdownMenuItem(value: 2, child: Text("ดัมเบล")),
                              DropdownMenuItem(value: 3, child: Text("เครื่องออกกำลังกาย")),
                              DropdownMenuItem(value: 4, child: Text("สายแรงต้าน (Cable)")),
                              DropdownMenuItem(value: 5, child: Text("น้ำหนักตัว (Bodyweight)")),
                            ],
                            onChanged: (v) => setModalState(() => selectedEquipment = v!),
                          )),
                          const SizedBox(height: 12),

                          // ประเภทท่าฝึก
                          _lbl('ประเภทท่าฝึก',
                          DropdownButtonFormField<int>(
                            value: selectedExerciseType,
                            decoration: fieldDeco(icon: Icons.category_outlined),
                            dropdownColor: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text("หลายกลุ่มกล้ามเนื้อ")),
                              DropdownMenuItem(value: 2, child: Text("เฉพาะส่วน")),
                            ],
                            onChanged: (v) => setModalState(() => selectedExerciseType = v!),
                          )),
                          const SizedBox(height: 12),

                          // ลิงก์วิดีโอ
                          const Text('ลิงก์วิดีโอ (YouTube)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: videoCtrl,
                            onChanged: (v) {
                              setModalState(
                                  () => previewEmbedUrl = _toEmbedUrl(v));
                            },
                            decoration: InputDecoration(
                              hintText: 'https://youtube.com/...',
                              hintStyle: const TextStyle(
                                  color: Color(0xFFA0A1A5), fontSize: 13),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              prefixIcon: const Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.redAccent,
                                  size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: kGreen, width: 1.5),
                              ),
                            ),
                          ),

                          // YouTube Preview
                          if (previewEmbedUrl != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 200,
                                width: double.infinity,
                                child: InAppWebView(
                                  key: ValueKey(previewEmbedUrl),
                                  initialUrlRequest: URLRequest(
                                      url: WebUri(previewEmbedUrl!)),
                                  initialSettings: InAppWebViewSettings(
                                    javaScriptEnabled: true,
                                    mediaPlaybackRequiresUserGesture: false,
                                    allowsInlineMediaPlayback: true,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: const [
                                  Icon(Icons.check_circle,
                                      size: 14, color: kGreen),
                                  SizedBox(width: 4),
                                  Text('พบลิงก์ YouTube แล้ว',
                                      style: TextStyle(
                                          fontSize: 12, color: kGreen)),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),

                          // วิดีโอ loop (แสดงวนซ้ำในหน้ารายละเอียดท่าฝึก)
                          const Text('วิดีโอ Loop (ไม่บังคับ)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: pickLoopVideo,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(children: [
                                const Icon(Icons.videocam_outlined, color: kGreen, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    loopVideoLabel ?? 'แตะเพื่อเลือกวิดีโอ loop',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: loopVideoLabel != null ? Colors.black87 : const Color(0xFFA0A1A5)),
                                  ),
                                ),
                              ]),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ปุ่มบันทึก
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () => _handleSaveExercise(
                                item,
                                nameCtrl.text,
                                descCtrl.text,
                                techniqueCtrl.text,
                                selectedDiff,
                                selectedEquipment,
                                selectedExerciseType,
                                videoCtrl.text,
                                selectedImage,
                                selectedImageBytes,
                                selectedImageName,
                                selectedLoopVideo,
                                selectedLoopVideoBytes,
                                selectedLoopVideoName,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kGreen,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('บันทึกข้อมูล',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
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

  void _showFocusForm(int wetId, List<Map<String, dynamic>> existingList,
      {Map<String, dynamic>? editItem}) {
    int? selectedMugId = editItem?['mug_id'];
    String selectedType = editItem?['type'] ?? 'หลัก';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: const Color(0xFFF2F2F7),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        editItem == null
                            ? 'เพิ่มกล้ามเนื้อโฟกัส'
                            : 'แก้ไขกล้ามเนื้อโฟกัส',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 20, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Dropdown กล้ามเนื้อ
                const Text('เลือกกล้ามเนื้อ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: selectedMugId,
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.inputBorder, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: AppColors.inputBorder, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: kGreen, width: 1.5),
                    ),
                  ),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  items: musclesList
                      .map((e) => DropdownMenuItem<int>(
                            value: e['mug_id'],
                            child: Text(e['mug_name'] ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => selectedMugId = v),
                ),
                const SizedBox(height: 16),

                const Text('ประเภทกล้ามเนื้อ',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: ['หลัก', 'รอง'].map((type) {
                    final isSelected = selectedType == type;
                    final color =
                        type == 'หลัก' ? kGreen : Colors.blueGrey;
                    final icon = type == 'หลัก'
                        ? Icons.star_rounded
                        : Icons.star_border_rounded;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedType = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withOpacity(0.12)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon,
                                  size: 16,
                                  color:
                                      isSelected ? color : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                type,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color:
                                      isSelected ? color : Colors.grey,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.check_circle,
                                    size: 14, color: color),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (selectedMugId == null) {
                        _showSnackBar('กรุณาเลือกกล้ามเนื้อ');
                        return;
                      }
                      _handleSaveFocus(
                        wetId,
                        selectedMugId!,
                        selectedType == 'หลัก' ? 1 : 2,
                        editId: editItem?['id'],
                        existingFocusList: existingList,
                      );
                    },
                    child: const Text('บันทึกข้อมูล',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredExercises;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Column(
        children: [
          // ── Header ──
          SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      AppBackButton(),
                      const Expanded(
                        child: Column(
                          children: [
                            Text(
                              'Weight Exercises',
                              style: AppTextStyles.pageTitle,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'จัดการท่าฝึกเวทเทรนนิ่ง',
                              style: AppTextStyles.pageSubtitle,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isSearching ? Icons.close : Icons.search,
                          color: kGreen,
                        ),
                        onPressed: () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) {
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                      ),
                    ],
                  ),

                  // ── Search bar ──
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isSearching
                        ? Padding(
                            key: const ValueKey('searchbar'),
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'ค้นหาท่าฝึก...',
                                prefixIcon: const Icon(Icons.search,
                                    color: kGreen),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 0, horizontal: 16),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.inputBorder, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: kGreen, width: 1.5),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  ),

                  // ── Filter chips ──
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          ...[
                            [0, 'ทั้งหมด', Colors.grey],
                            [1, 'ง่าย', Colors.green],
                            [2, 'ปานกลาง', Colors.orange],
                            [3, 'ยาก', Colors.red],
                          ].map((e) {
                            final val   = e[0] as int;
                            final label = e[1] as String;
                            final color = e[2] as Color;
                            final sel   = _filterDiff == val;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _filterDiff = val),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: sel ? color : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: color),
                                  ),
                                  child: Text(label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: sel ? Colors.white : color,
                                      )),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── จำนวนรายการ ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'พบ ${filtered.length} รายการ',
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),

          // ── List ──
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
                                size: 60, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              exercises.isEmpty
                                  ? 'ยังไม่มีข้อมูลท่าฝึก'
                                  : 'ไม่พบท่าฝึกที่ค้นหา',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _loadAll();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) =>
                              _buildExerciseCard(filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppFab(onPressed: _showExerciseForm, color: kGreen),
    );
  }

  Widget _buildExerciseCard(Map<String, dynamic> item) {
    final String? imgPath  = item['wet_image'] ?? item['WetImage'];
    final String? videoUrl = item['wet_video'] ?? item['WetVideo'];
    final bool hasVideo    = videoUrl != null && videoUrl.isNotEmpty;
    final int diff         = (item['wet_difficulty'] ?? item['WetDifficulty']) ?? 1;
    final int wetId        = item['wet_id'] ?? item['WetID'] ?? 0;
    final String name      = item['wet_name'] ?? item['WetName'] ?? '';
    final String desc      = item['wet_description'] ?? item['WetDescription'] ?? '';
    final String technique = item['wet_technique'] ?? item['WetTechnique'] ?? '';
    final int equipment    = (item['wet_equipment'] ?? item['WetEquipment']) ?? 5;
    final int exType       = (item['wet_exercise_type'] ?? item['WetExerciseType']) ?? 1;
    final List<Map<String, dynamic>> focusList = focusMap[wetId] ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── หัวการ์ด ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: kGreen.withOpacity(0.1),
                    child: (imgPath != null && imgPath.isNotEmpty && ApiClient.prefixPath(imgPath) != null)
                        ? Image.network(ApiClient.prefixPath(imgPath)!,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(
                                Icons.fitness_center,
                                color: kGreen))
                        : const Icon(Icons.fitness_center, color: kGreen),
                  ),
                ),
                const SizedBox(width: 12),

                // ชื่อ + badge + desc
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                      if (technique.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'เทคนิค: $technique',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.teal.shade700),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _diffBadge(diff),
                          _smallBadge(
                            _equipmentText(equipment),
                            Colors.blueGrey,
                          ),
                          _smallBadge(
                            exType == 1 ? 'หลายกลุ่ม' : 'เฉพาะส่วน',
                            exType == 1 ? Colors.indigo : Colors.deepOrange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (hasVideo) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _showVideoDialog(videoUrl),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.redAccent, width: 0.5),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_circle_fill,
                                        size: 12,
                                        color: Colors.redAccent),
                                    SizedBox(width: 3),
                                    Text('วิดีโอ',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ปุ่ม edit / delete
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: kGreen, size: 20),
                      onPressed: () => _showExerciseForm(item: item),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent, size: 20),
                      onPressed: () =>
                          _handleDeleteExercise(wetId, name),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Divider ──
          Divider(height: 1, color: Colors.grey.shade100),

          // ── กล้ามเนื้อโฟกัส ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                const Icon(Icons.center_focus_strong,
                    size: 13, color: kGreen),
                const SizedBox(width: 4),
                const Text('กล้ามเนื้อโฟกัส',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kGreen)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showFocusForm(wetId, focusList),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kGreen, width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: kGreen),
                        SizedBox(width: 2),
                        Text('เพิ่ม',
                            style: TextStyle(
                                fontSize: 11,
                                color: kGreen,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (focusList.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('ยังไม่มีกล้ามเนื้อโฟกัส',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: focusList.map((f) {
                  final isMain = (f['exm_type'] ?? f['type']) == 1 ||
                      (f['type'] == 'หลัก');
                  final muscleName = f['muscle'] ?? f['mug_name'] ?? '?';
                  return GestureDetector(
                    onLongPress: () => _handleDeleteFocus(
                      f['id'] ?? f['exm_id'],
                      muscleName,
                      name,
                    ),
                    onTap: () =>
                        _showFocusForm(wetId, focusList, editItem: f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isMain
                            ? kGreen.withOpacity(0.08)
                            : Colors.grey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMain
                              ? kGreen.withOpacity(0.4)
                              : Colors.grey.shade300,
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMain
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 11,
                            color: isMain ? kGreen : Colors.grey,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            muscleName,
                            style: TextStyle(
                              fontSize: 11,
                              color: isMain ? kGreen : Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 10),
              child: Text('แตะแท็กเพื่อแก้ไข • กดค้างเพื่อลบ',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _diffBadge(int diff) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _getDiffColor(diff).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _getDiffColor(diff), width: 0.5),
        ),
        child: Text(
          _getDiffText(diff),
          style: TextStyle(
              fontSize: 11,
              color: _getDiffColor(diff),
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _smallBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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
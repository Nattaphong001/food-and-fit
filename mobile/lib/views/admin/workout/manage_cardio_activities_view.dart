// ignore_for_file: use_build_context_synchronously

// หน้า: Admin - Manage Cardio Activities (จัดการกิจกรรมคาร์ดิโอ)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบประเภทกิจกรรมคาร์ดิโอที่ผู้ใช้สามารถเลือกออกกำลังกายได้

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
import 'package:myapp/services/exercise_service.dart';

class ManageCardioActivitiesView extends StatefulWidget {
  const ManageCardioActivitiesView({super.key});

  @override
  State<ManageCardioActivitiesView> createState() =>
      _ManageCardioActivitiesViewState();
}

class _ManageCardioActivitiesViewState
    extends State<ManageCardioActivitiesView> {
  List<dynamic> activities = [];
  List<dynamic> categories = [];
  bool isLoading = true;

  // ── Search / Filter / Sort ────────────────────────────────────────────────
  bool _searchVisible = false;
  String _searchQuery = '';
  int? _selectedCatId;
  bool _sortAscending = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  static const Color _green = Color(0xFF5EA61A);

  String get baseUrl        => ApiClient.serverUrl;
  String get serverUrl      => ApiClient.serverUrl;
  String get cardioApiUrl   => '${ApiClient.serverUrl}/api/exercises/cardio';
  String get categoryApiUrl => '${ApiClient.serverUrl}/api/exercises/cardio-categories';
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  /// แก้ปัญหา double slash: รับ path ดิบแล้วต่อ URL ให้ถูกต้อง
  String _buildImageUrl(String path) => ApiClient.prefixPath(path) ?? '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Filtered ──────────────────────────────────────────────────────────────
  List<dynamic> get _filteredActivities {
    List<dynamic> result = List.from(activities);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((item) {
        final name = (item['cdo_name'] ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    }
    if (_selectedCatId != null) {
      result = result.where((item) => item['cdc_id'] == _selectedCatId).toList();
    }
    result.sort((a, b) {
      final va = (a['cdo_mets'] as num?) ?? 0;
      final vb = (b['cdo_mets'] as num?) ?? 0;
      return _sortAscending ? va.compareTo(vb) : vb.compareTo(va);
    });
    return result;
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────
  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    try {
      final resCardio = await http.get(Uri.parse(cardioApiUrl), headers: _authHeaders);
      final resCat    = await http.get(Uri.parse(categoryApiUrl), headers: _authHeaders);
      if (!mounted) return;
      setState(() => isLoading = false);
      if (resCardio.statusCode == 200) {
        setState(() => activities = json.decode(resCardio.body)['data'] ?? []);
      }
      if (resCat.statusCode == 200) {
        setState(() => categories = json.decode(resCat.body)['data'] ?? []);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showSnackBar('เกิดข้อผิดพลาดในการเชื่อมต่อ: $e');
    }
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

    if (!confirm) return;
    _showLoadingDialog();
    try {
      final res = await http.delete(
          Uri.parse('$cardioApiUrl/$id'), headers: _authHeaders);
      if (!mounted) return;
      Navigator.pop(context);
      if (res.statusCode == 200) {
        ExerciseService.to.clearCardioCache();
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

  // ── Save ──────────────────────────────────────────────────────────────────
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
      request.fields['cdo_name']         = name.trim();
      request.fields['cdo_mets']         = mets;
      request.fields['cdo_description']  = desc;
      request.fields['cdo_technique']    = technique;
      request.fields['cdo_video']        = video;
      request.fields['cdc_id']           = catId.toString();
      request.fields['cdo_has_distance'] = hasDistance ? '1' : '0';

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'cdo_image', imageBytes, filename: imageFileName));
        }
        if (loopVideoBytes != null && loopVideoFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'cdo_loop_video', loopVideoBytes, filename: loopVideoFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(
              await http.MultipartFile.fromPath('cdo_image', imageFile.path));
        }
        if (loopVideoFile != null) {
          request.files.add(await http.MultipartFile.fromPath(
              'cdo_loop_video', loopVideoFile.path));
        }
      }

      final response = await http.Response.fromStream(await request.send());
      if (!mounted) return;
      Navigator.pop(context);
      if (response.statusCode == 200 || response.statusCode == 201) {
        ExerciseService.to.clearCardioCache();
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

  String? _getYouTubeEmbedUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
    );
    final match = regExp.firstMatch(url);
    if (match != null) return 'https://www.youtube.com/embed/${match.group(1)}';
    return null;
  }

  // ── Category Icon Mapper ──────────────────────────────────────────────────
  IconData _getCategoryIcon(String? name) {
    if (name == null) return Icons.grid_view_rounded;
    final n = name.toLowerCase();
    if (n.contains('จักรยาน') || n.contains('ปั่น')) return Icons.directions_bike;
    if (n.contains('ว่าย') || n.contains('น้ำ'))     return Icons.pool;
    if (n.contains('วิ่ง'))                           return Icons.directions_run;
    if (n.contains('เต้น') || n.contains('แอโรบิก')) return Icons.music_note;
    if (n.contains('คาร์ดิโอ') || n.contains('หนัก')) return Icons.fitness_center;
    if (n.contains('เดิน'))                           return Icons.directions_walk;
    if (n.contains('กีฬา'))                           return Icons.sports_soccer;
    return Icons.flash_on_outlined;
  }

  // ── Sort Sheet ────────────────────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              const Text('เรียงค่า METs',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
              const SizedBox(height: 12),
              _directionTile(
                label: 'เรียงจากน้อยไปมาก',
                selected: _sortAscending,
                onTap: () { setSheet(() => _sortAscending = true); setState(() {}); },
              ),
              const SizedBox(height: 4),
              _directionTile(
                label: 'เรียงจากมากไปน้อย',
                selected: !_sortAscending,
                onTap: () { setSheet(() => _sortAscending = false); setState(() {}); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _directionTile({
    required String label, required bool selected, required VoidCallback onTap,
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
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ))),
            if (selected)
              Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(
                    color: _green, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
          ]),
        ),
      );

  // ── Category Tabs ─────────────────────────────────────────────────────────
  Widget _buildCategoryTabs() {
    final allCats = <Map<String, dynamic>>[
      {'cdc_id': null, 'cdc_name': 'ทั้งหมด'},
      ...categories.map((c) => Map<String, dynamic>.from(c)),
    ];

    return SizedBox(
      height: 90,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: allCats.map((cat) {
            final catId    = cat['cdc_id'] as int?;
            final catName  = cat['cdc_name'] ?? '';
            final selected = _selectedCatId == catId;
            final icon     = catId == null
                ? Icons.grid_view_rounded
                : _getCategoryIcon(catName);

            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 60,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCatId = catId),
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

  // ── Form Dialog ───────────────────────────────────────────────────────────
  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl      = TextEditingController(text: item?['cdo_name'] ?? '');
    final metCtrl       = TextEditingController(text: item?['cdo_mets']?.toString() ?? '');
    final descCtrl      = TextEditingController(text: item?['cdo_description'] ?? '');
    final techniqueCtrl = TextEditingController(text: item?['cdo_technique'] ?? '');
    final videoCtrl     = TextEditingController(text: item?['cdo_video'] ?? '');
    // เมื่อ add ใหม่ในหมวดเจาะจง → ล็อค catId จาก filter, ซ่อน dropdown
    final bool isAdding = item == null;
    final int? lockedCatId = isAdding ? _selectedCatId : null;
    final bool showCatSelector = lockedCatId == null;
    int? selectedCatId = lockedCatId
        ?? item?['cdc_id']
        ?? (isAdding && categories.isNotEmpty ? categories.first['cdc_id'] as int? : null);
    bool hasDistance    = (item?['cdo_has_distance'] ?? 0) == 1;

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    File? selectedLoopVideo;
    Uint8List? selectedLoopVideoBytes;
    String? selectedLoopVideoName;
    final existingLoopVideo = (item?['cdo_loop_video'] ?? '').toString();
    final ImagePicker picker = ImagePicker();
    String? previewEmbedUrl = _getYouTubeEmbedUrl(item?['cdo_video']);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickImage() async {
            final pickedFile = await picker.pickImage(source: ImageSource.gallery);
            if (pickedFile != null) {
              final bytes = await pickedFile.readAsBytes();
              setDialogState(() {
                selectedImageBytes = bytes;
                selectedImageName  = pickedFile.name;
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
            imagePreview = Image.network(
              _buildImageUrl(item!['cdo_image']),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.add_a_photo, size: 40),
            );
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
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
                      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                          item == null ? 'เพิ่มกิจกรรมคาร์ดิโอ' : 'แก้ไขกิจกรรมคาร์ดิโอ',
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20, right: 20, top: 16,
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
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
                                    boxShadow: [BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))],
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
                                  style: TextStyle(color: Colors.grey, fontSize: 11))),
                          const SizedBox(height: 16),

                          // ชื่อกิจกรรม
                          const Text('ชื่อกิจกรรม *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              hintText: 'เช่น วิ่ง, ว่ายน้ำ...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.directions_run,
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
                              value: selectedCatId,
                              items: categories.map<DropdownMenuItem<int>>((cat) =>
                                DropdownMenuItem<int>(
                                  value: cat['cdc_id'],
                                  child: Text(cat['cdc_name'] ?? '',
                                      style: const TextStyle(fontSize: 13)),
                                )).toList(),
                              onChanged: (v) => setDialogState(() => selectedCatId = v),
                              decoration: InputDecoration(
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
                                      (c) => c['cdc_id'] == selectedCatId,
                                      orElse: () => {'cdc_name': ''},
                                    )['cdc_name'] ?? '',
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
                          const SizedBox(height: 10),

                          // ค่า METs
                          const Text('ค่า METs *',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: metCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              hintText: 'เช่น 7.0',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.local_fire_department,
                                  color: Colors.orange, size: 18),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // คำอธิบาย
                          const Text('คำอธิบายกิจกรรม',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: descCtrl,
                            decoration: InputDecoration(
                              hintText: 'อธิบายลักษณะกิจกรรมโดยย่อ...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // เทคนิค
                          const Text('เทคนิคการปฏิบัติ',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: techniqueCtrl,
                            decoration: InputDecoration(
                              hintText: 'เทคนิคหรือข้อควรระวัง...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // มีระยะทาง
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              const Icon(Icons.straighten, color: _green, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text('มีการวัดระยะทาง',
                                    style: TextStyle(fontSize: 13, color: Colors.black87)),
                              ),
                              Switch(
                                value: hasDistance,
                                activeColor: _green,
                                onChanged: (v) => setDialogState(() => hasDistance = v),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 10),

                          // ลิงก์วิดีโอ
                          const Text('ลิงก์วิดีโอ (YouTube / Shorts)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: videoCtrl,
                            onChanged: (v) => setDialogState(
                                () => previewEmbedUrl = _getYouTubeEmbedUrl(v)),
                            decoration: InputDecoration(
                              hintText: 'https://youtube.com/...',
                              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA0A1A5)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _green, width: 1.5),
                              ),
                              prefixIcon: const Icon(Icons.play_circle_outline,
                                  color: Colors.redAccent, size: 18),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                            ),
                          ),

                          // YouTube Preview
                          if (previewEmbedUrl != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.redAccent.withOpacity(0.5)),
                                ),
                                child: InAppWebView(
                                  initialUrlRequest:
                                      URLRequest(url: WebUri(previewEmbedUrl!)),
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
                              child: Row(children: const [
                                Icon(Icons.check_circle,
                                    size: 13, color: _green),
                                SizedBox(width: 4),
                                Text('พบลิงก์ YouTube แล้ว',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _green)),
                              ]),
                            ),
                          ],

                          const SizedBox(height: 10),

                          // วิดีโอ loop (แสดงวนซ้ำในหน้ารายละเอียดกิจกรรม)
                          const Text('วิดีโอ Loop (ไม่บังคับ)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: pickLoopVideo,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(children: [
                                const Icon(Icons.videocam_outlined, color: _green, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    selectedLoopVideoName ??
                                        (existingLoopVideo.isNotEmpty
                                            ? existingLoopVideo.split('/').last
                                            : 'แตะเพื่อเลือกวิดีโอ loop'),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: (selectedLoopVideoName != null || existingLoopVideo.isNotEmpty)
                                            ? Colors.black87
                                            : const Color(0xFFA0A1A5)),
                                  ),
                                ),
                              ]),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ปุ่มบันทึก
                          SizedBox(
                            width: double.infinity, height: 48,
                            child: ElevatedButton(
                              onPressed: () => _handleSave(
                                item, nameCtrl.text, metCtrl.text,
                                descCtrl.text, techniqueCtrl.text,
                                videoCtrl.text, selectedCatId, hasDistance,
                                selectedImage, selectedImageBytes, selectedImageName,
                                selectedLoopVideo, selectedLoopVideoBytes, selectedLoopVideoName,
                              ),
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

  // ── Video Dialog ──────────────────────────────────────────────────────────
  void _showVideoDialog(String videoUrl) {
    final embedUrl = _getYouTubeEmbedUrl(videoUrl);
    if (embedUrl == null) {
      _showSnackBar('ลิงก์วิดีโอไม่ถูกต้อง');
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
              child: Row(children: [
                const Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('วิดีโอประกอบ',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
              child: SizedBox(
                height: 240,
                child: InAppWebView(
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

  // ── Activity Card ─────────────────────────────────────────────────────────
  Widget _buildActivityCard(Map<String, dynamic> item) {
    final String? imgPath    = item['cdo_image'];
    final bool hasVideo      = item['cdo_video'] != null && item['cdo_video'].toString().isNotEmpty;
    final String technique   = item['cdo_technique'] ?? '';
    final bool hasDistance   = (item['cdo_has_distance'] ?? 0) == 1;
    final cat = categories.firstWhere(
        (c) => c['cdc_id'] == item['cdc_id'], orElse: () => null);
    final String catName = cat?['cdc_name'] ?? '';

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
            // Avatar — ใช้ _buildImageUrl แก้ double slash
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: (imgPath != null && imgPath.isNotEmpty)
                  ? Image.network(
                      _buildImageUrl(imgPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.directions_run, color: _green, size: 22),
                    )
                  : const Icon(Icons.directions_run, color: _green, size: 22),
            ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (catName.isNotEmpty)
                    Text(catName,
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item['cdo_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _badge('METs: ${item['cdo_mets']}', Colors.orange),
                      if (hasDistance)
                        _badge('มีระยะทาง', Colors.blue),
                      if (hasVideo)
                        GestureDetector(
                          onTap: () => _showVideoDialog(item['cdo_video']),
                          child: const Icon(Icons.play_circle_fill,
                              size: 18, color: Colors.redAccent),
                        ),
                    ],
                  ),
                  if (technique.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'เทคนิค: $technique',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.teal.shade700),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Edit
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

            // Delete
            GestureDetector(
              onTap: () => _handleDelete(item['cdo_id'], item['cdo_name']),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.3), width: 0.5),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 9, color: color, fontWeight: FontWeight.w600)),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredActivities;
    final hasActiveFilter = _selectedCatId != null;

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
          Text('Cardio Activities',
              style: AppTextStyles.pageTitle),
          Text('จัดการกิจกรรมและค่าพลังงาน (METs)',
              style: AppTextStyles.pageSubtitle),
        ]),
        centerTitle: true,
        actions: [
          // Search icon
          Builder(builder: (context) => IconButton(
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
          )),
          // Sort icon
          IconButton(
            icon: Icon(Icons.tune_rounded,
                color: Colors.grey.shade600, size: 22),
            onPressed: _showSortSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Spacer แทน header เดิม
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

          // Inline Search Bar
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _searchVisible
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาชื่อกิจกรรม...',
                  hintStyle: const TextStyle(color: Color(0xFFA0A1A5), fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: _green, size: 18),
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
                      borderSide: const BorderSide(color: Color(0xFFD9D9D9), width: 1)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD9D9D9), width: 1)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _green, width: 1.5),
                  ),
                ),
              ),
            ),
            secondChild: const SizedBox(height: 0),
          ),

          // Category Tabs
          _buildCategoryTabs(),
          const SizedBox(height: 2),

          // Count + clear filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('พบ ${filtered.length} รายการ',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Spacer(),
              if (hasActiveFilter)
                GestureDetector(
                  onTap: () => setState(() => _selectedCatId = null),
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
                              fontSize: 11, color: Colors.orange.shade700)),
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
            child: isLoading
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
                            _searchQuery.isNotEmpty || _selectedCatId != null
                                ? 'ไม่พบกิจกรรมที่ค้นหา'
                                : 'ยังไม่มีข้อมูลกิจกรรมคาร์ดิโอ',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ]))
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _fetchData();
                        },
                        color: _green,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _buildActivityCard(filtered[i]),
                        ),
                      ),
          ),
        ],
      ),

      floatingActionButton: AppFab(onPressed: _showForm, color: _green),
    );
  }
}
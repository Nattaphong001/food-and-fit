// หน้า: Admin - Manage Muscle Groups (จัดการกลุ่มกล้ามเนื้อ)
// ทำหน้าที่: Admin เพิ่ม/แก้ไข/ลบกลุ่มกล้ามเนื้อที่ใช้ในการจัดหมวดท่าฝึกเวทเทรนนิ่ง

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';
import 'package:myapp/services/exercise_service.dart';

const Color kGreen = Color(0xFF1A9A90);

class ManageMuscleGroupView extends StatefulWidget {
  const ManageMuscleGroupView({super.key});

  @override
  State<ManageMuscleGroupView> createState() => _ManageMuscleGroupViewState();
}

class _ManageMuscleGroupViewState extends State<ManageMuscleGroupView> {
  String get baseUrl => '${ApiClient.serverUrl}/api/exercises/muscle-groups';
  String get serverUrl => '${ApiClient.serverUrl}/';
  String get exerciseMusclesUrl => '${ApiClient.serverUrl}/api/exercise-muscles';

  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  List<dynamic> items = [];
  List<dynamic> _filteredItems = [];
  bool _isLoadingData = true;
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMuscleGroups();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(items);
      } else {
        _filteredItems = items.where((item) {
          final name =
              (item['mug_name'] ?? item['MugName'] ?? '').toLowerCase();
          final zone =
              (item['mug_zone'] ?? item['MugZone'])?.toString() ?? '';
          return name.contains(query) || zone.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _fetchMuscleGroups() async {
    try {
      final response =
          await http.get(Uri.parse(baseUrl), headers: _authHeaders);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ??
              decoded['items'] ??
              decoded['result'] ??
              []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        setState(() {
          items = list;
          _filteredItems = List.from(list);
          _isLoadingData = false;
        });
      } else {
        setState(() => _isLoadingData = false);
        _showSnackBar('โหลดข้อมูลไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showSnackBar('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  /// ✅ เช็คจาก /api/exercise-muscles ที่มีอยู่แล้ว
  /// นับจำนวน record ที่ mug_id ตรงกับที่จะลบ
  Future<int> _getLinkedCount(int mugId) async {
    try {
      final response = await http.get(
        Uri.parse(exerciseMusclesUrl),
        headers: _authHeaders,
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ??
              decoded['items'] ??
              decoded['result'] ??
              []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        // นับเฉพาะที่ mug_id ตรงกับที่จะลบ
        final count = list.where((f) {
          final fMugId = f['mug_id'] ?? f['MugID'] ?? f['mugId'];
          return fMugId != null && fMugId.toString() == mugId.toString();
        }).length;
        return count;
      }
      return 0;
    } catch (e) {
      debugPrint('_getLinkedCount error: $e');
      return 0;
    }
  }

  Future<void> _handleDelete(int id, String name) async {
    _showLoading();
    final linkedCount = await _getLinkedCount(id);
    Navigator.pop(context); // ปิด loading

    if (linkedCount > 0) {
      // ── มีข้อมูลเชื่อม → แสดง "ไม่สามารถลบได้" ──
      showAppNoticeDialog(
        context,
        icon: Icons.error_outline_rounded,
        title: 'ไม่สามารถลบได้',
        content: 'กลุ่มกล้ามเนื้อ "$name" ยังมีท่าออกกำลังกายอยู่ $linkedCount รายการ\n\nกรุณาลบหรือย้ายท่าออกกำลังกายออกก่อน',
      );
      return;
    }

    // ── ไม่มีข้อมูลเชื่อม → ยืนยันการลบ ──
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
        final response = await http.delete(Uri.parse('$baseUrl/$id'),
            headers: _authHeaders);
        Navigator.pop(context);
        if (response.statusCode == 200) {
          ExerciseService.to.clearExerciseCache();
          _fetchMuscleGroups();
          showAdminTopToast(context, 'ลบกลุ่มกล้ามเนื้อเรียบร้อยแล้ว');
        } else {
          _showSnackBar('ลบไม่สำเร็จ: ${response.statusCode}');
        }
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('ลบไม่สำเร็จ: $e');
      }
    }
  }

  Future<void> _handleSave(
    Map<String, dynamic>? oldItem,
    String name,
    String zone,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageFileName,
  ) async {
    if (name.trim().isEmpty) return;
    _showLoading();

    try {
      final uri = oldItem == null
          ? Uri.parse(baseUrl)
          : Uri.parse('$baseUrl/${oldItem['mug_id'] ?? oldItem['MugID']}');

      var request =
          http.MultipartRequest(oldItem == null ? 'POST' : 'PUT', uri);
      request.headers.addAll(_authHeaders);
      request.fields['mug_name'] = name;
      request.fields['mug_zone'] = zone.isEmpty ? '1' : zone;

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'mug_image',
            imageBytes,
            filename: imageFileName,
          ));
        }
      } else {
        if (imageFile != null) {
          request.files.add(await http.MultipartFile.fromPath(
              'mug_image', imageFile.path));
        }
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        ExerciseService.to.clearExerciseCache();
        _fetchMuscleGroups();
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มสำเร็จ' : 'อัปเดตสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(
        text: item?['mug_name'] ?? item?['MugName'] ?? '');
    String selectedZone =
        (item?['mug_zone'] ?? item?['MugZone'])?.toString() ?? '1';

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    final ImagePicker picker = ImagePicker();

    InputDecoration fieldDecoration() => const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        );

    Widget _labeled(String label, Widget field) => Column(
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
        builder: (BuildContext context, StateSetter setModalState) {
          Future<void> pickImage() async {
            final pickedFile =
                await picker.pickImage(source: ImageSource.gallery);
            if (pickedFile != null) {
              final bytes = await pickedFile.readAsBytes();
              setModalState(() {
                selectedImageBytes = bytes;
                selectedImageName = pickedFile.name;
                if (!kIsWeb) selectedImage = File(pickedFile.path);
              });
            }
          }

          Widget imagePreview;
          if (selectedImageBytes != null) {
            imagePreview =
                Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['mug_image'] ?? item?['MugImage']) != null &&
              (item?['mug_image'] ?? item?['MugImage']) != '') {
            final imgVal = item!['mug_image'] ?? item['MugImage'];
            final imgUrl = ApiClient.prefixPath(imgVal);
            imagePreview = imgUrl != null
                ? Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        const Icon(Icons.add_a_photo, size: 40),
                  )
                : const Icon(Icons.add_a_photo, size: 40);
          } else {
            imagePreview = const Icon(Icons.add_a_photo,
                size: 40, color: Colors.grey);
          }

          return Dialog(
            backgroundColor: const Color(0xFFF2F2F7),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item == null
                            ? 'เพิ่มกลุ่มกล้ามเนื้อ'
                            : 'แก้ไขกลุ่มกล้ามเนื้อ',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: pickImage,
                          child: Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                              border: Border.all(color: kGreen, width: 2.5),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: imagePreview,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'แตะวงกลมเพื่อเปลี่ยนรูปภาพ',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _labeled('ชื่อกลุ่มกล้ามเนื้อ *',
                    TextField(
                      controller: nameCtrl,
                      decoration: fieldDecoration().copyWith(
                        hintText: 'เช่น หน้าอก, หลัง, ต้นขา',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFFA0A1A5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _labeled('โซน',
                  DropdownButtonFormField<String>(
                    value: selectedZone,
                    decoration: fieldDecoration(),
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    items: const [
                      DropdownMenuItem(
                          value: '1', child: Text('โซน 1 — ส่วนบน')),
                      DropdownMenuItem(
                          value: '2', child: Text('โซน 2 — ส่วนกลาง')),
                      DropdownMenuItem(
                          value: '3', child: Text('โซน 3 — ส่วนล่าง')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedZone = val);
                      }
                    },
                  )),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => _handleSave(
                        item,
                        nameCtrl.text,
                        selectedZone,
                        selectedImage,
                        selectedImageBytes,
                        selectedImageName,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGreen,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'บันทึกข้อมูล',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
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

  Widget _placeholderImage() {
    return Container(
      width: double.infinity,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.fitness_center, color: Colors.grey, size: 36),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                              'Muscle Groups',
                              style: AppTextStyles.pageTitle,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'จัดการกลุ่มกล้ามเนื้อ',
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
                              _filteredItems = List.from(items);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isSearching
                        ? Padding(
                            key: const ValueKey('searchbar'),
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: TextField(
                              controller: _searchCtrl,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'ค้นหากลุ่มกล้ามเนื้อ...',
                                prefixIcon:
                                    const Icon(Icons.search, color: kGreen),
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
                ],
              ),
            ),
          ),

          // ── Grid ──
          Expanded(
            child: _isLoadingData
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryGreen))
                : _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 60, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'ไม่พบกลุ่มกล้ามเนื้อ',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ApiClient.clearCache();
                          await _fetchMuscleGroups();
                        },
                        child: GridView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, i) {
                            final item = _filteredItems[i];
                            final String? imgPath =
                                item['mug_image'] ?? item['MugImage'];
                            final String name = item['mug_name'] ??
                                item['MugName'] ??
                                'ไม่มีชื่อ';
                            final String zone =
                                (item['mug_zone'] ?? item['MugZone'])
                                        ?.toString() ??
                                    '';

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10, 10, 10, 6),
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        child: (imgPath != null &&
                                                imgPath.isNotEmpty &&
                                                ApiClient.prefixPath(imgPath) != null)
                                            ? Image.network(
                                                ApiClient.prefixPath(imgPath)!,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err,
                                                        stack) =>
                                                    _placeholderImage(),
                                              )
                                            : _placeholderImage(),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (zone.isNotEmpty)
                                          Text(
                                            'โซน $zone',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        8, 2, 8, 10),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        IconButton(
                                          iconSize: 22,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 40, minHeight: 36),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: kGreen,
                                          ),
                                          onPressed: () =>
                                              _showForm(item: item),
                                        ),
                                        IconButton(
                                          iconSize: 22,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 40, minHeight: 36),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () => _handleDelete(
                                            item['mug_id'] ?? item['MugID'],
                                            name,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppFab(onPressed: _showForm, color: kGreen),
    );
  }
}
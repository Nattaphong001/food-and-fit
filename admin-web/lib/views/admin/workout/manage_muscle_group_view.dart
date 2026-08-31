// ignore_for_file: use_build_context_synchronously

// [PAGE] ADMIN_MUSCLE_GROUPS : จัดการกลุ่มกล้ามเนื้อ (เว็บ)
// [PAGE_PURPOSE] Admin เพิ่ม/แก้ไข/ลบกลุ่มกล้ามเนื้อที่ใช้ในการจัดหมวดท่าฝึกเวทเทรนนิ่ง
// [PAGE_ROUTE] /admin > เวทเทรนนิ่ง > กลุ่มกล้ามเนื้อ
// [USES_FEATURES] WEIGHT_TRAINING
//
// ย้ายจากแอปมือถือ (lib/views/admin/workout/manage_muscle_group_view.dart)
// Logic CRUD + upload รูปเหมือนเดิมทุกจุด (COPY) — คงเป็น Grid การ์ดรูปภาพเหมือนมือถือ
// (ไม่บังคับ DataTable เพราะเนื้อหาเป็นรูปภาพเป็นหลัก) แค่เพิ่มจำนวนคอลัมน์ให้เหมาะจอกว้าง
// header/filter/pagination ใช้ AdminPageHeader + AdminFilterBar + AdminPaginationBar
// (client-side pagination ตาม pattern เดียวกับหน้า manage อื่น — backend ยังไม่รองรับ page/limit)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/admin_data_bus.dart';
import '../../../core/widgets/admin_filter_bar.dart';
import '../../../core/widgets/admin_list_state.dart';
import '../../../core/widgets/admin_network_image.dart';
import '../../../core/widgets/admin_page_header.dart';
import '../../../core/widgets/admin_pagination_bar.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/api_client.dart';
import 'manage_weight_exercises_view.dart';

class ManageMuscleGroupView extends StatefulWidget {
  const ManageMuscleGroupView({super.key});

  @override
  State<ManageMuscleGroupView> createState() => _ManageMuscleGroupViewState();
}

class _ManageMuscleGroupViewState extends State<ManageMuscleGroupView> {
  String get baseUrl => '${ApiClient.serverUrl}/api/exercises/muscle-groups';
  String get exerciseMusclesUrl => '${ApiClient.serverUrl}/api/exercise-muscles';

  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};
  final ApiClient _api = ApiClient();

  List<dynamic> items = [];
  Map<int, int> _linkedCounts = {};
  bool _isLoadingData = true;
  bool _hasError = false;
  String _searchQuery = '';
  String? _filterZone;
  int _pageSize = kAdminPageSizeOptions[1];
  int _currentPage = 1;
  // ไม่ว่างเมื่อคลิกการ์ดดูท่าฝึกในกลุ่ม — สลับแสดงเนื้อหาแทนที่ในสล็อตเดิมของ sidebar shell
  // (ไม่ใช้ Get.to() แล้ว เพราะ push จะปิดทับ sidebar ทั้งจอ)
  int? _drillMugId;

  @override
  void initState() {
    super.initState();
    _fetchMuscleGroups();
    _fetchLinkedCounts();
  }

  List<dynamic> get _filteredItems {
    var result = items;
    if (_filterZone != null) {
      result = result.where((item) => (item['mug_zone'] ?? item['MugZone'])?.toString() == _filterZone).toList();
    }
    final q = _searchQuery.toLowerCase().trim();
    if (q.isNotEmpty) {
      result = result.where((item) {
        final name = (item['mug_name'] ?? item['MugName'] ?? '').toLowerCase();
        final zone = (item['mug_zone'] ?? item['MugZone'])?.toString() ?? '';
        return name.contains(q) || zone.contains(q);
      }).toList();
    }
    return result;
  }

  // นับจำนวนท่าฝึกที่ผูกกับแต่ละกลุ่มกล้ามเนื้อ (badge "N ท่าฝึก" บรีฟ P2 ข้อ 1) — ดึงครั้งเดียว
  // ทั้งตาราง exercise-muscles มานับรวมในเครื่อง แทนยิง API แยกทีละกลุ่ม (endpoint เดิมอยู่แล้ว)
  Future<void> _fetchLinkedCounts() async {
    try {
      final response = await http.get(Uri.parse(exerciseMusclesUrl), headers: _authHeaders);
      if (response.statusCode != 200) return;
      final decoded = json.decode(response.body);
      List<dynamic> list = [];
      if (decoded is Map) {
        list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
      } else if (decoded is List) {
        list = decoded;
      }
      final counts = <int, int>{};
      for (final f in list) {
        final mugId = f['mug_id'] ?? f['MugID'] ?? f['mugId'];
        final id = mugId is int ? mugId : int.tryParse(mugId?.toString() ?? '');
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      if (mounted) setState(() => _linkedCounts = counts);
    } catch (e) {
      debugPrint('_fetchLinkedCounts error: $e');
    }
  }

  Future<void> _fetchMuscleGroups() async {
    setState(() => _hasError = false);
    try {
      final response = await _api.get('/exercises/muscle-groups');
      if (response.statusCode == 200) {
        final decoded = response.data;
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
        setState(() {
          items = list;
          _isLoadingData = false;
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _hasError = true;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingData = false;
        _hasError = true;
      });
    }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
    );
  }

  void _showSnackBar(String msg, {AppAlertType type = AppAlertType.error}) {
    showAppAlert(context, msg, type: type);
  }

  Future<int> _getLinkedCount(int mugId) async {
    try {
      final response = await http.get(Uri.parse(exerciseMusclesUrl), headers: _authHeaders);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> list = [];
        if (decoded is Map) {
          list = (decoded['data'] ?? decoded['items'] ?? decoded['result'] ?? []) as List;
        } else if (decoded is List) {
          list = decoded;
        }
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
    Navigator.pop(context);

    if (linkedCount > 0) {
      showAppNoticeDialog(
        context,
        icon: Icons.error_outline_rounded,
        title: 'ไม่สามารถลบได้',
        content: 'กลุ่มกล้ามเนื้อ "$name" ยังมีท่าออกกำลังกายอยู่ $linkedCount รายการ\n\nกรุณาลบหรือย้ายท่าออกกำลังกายออกก่อน',
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
      _showLoading();
      try {
        final response = await http.delete(Uri.parse('$baseUrl/$id'), headers: _authHeaders);
        Navigator.pop(context);
        if (response.statusCode == 200) {
          ApiClient.clearCache();
          _fetchMuscleGroups();
          AdminDataBus.bumpMuscleGroups();
          showAdminTopToast(context, 'ลบ "$name" เรียบร้อย');
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
      final uri = oldItem == null ? Uri.parse(baseUrl) : Uri.parse('$baseUrl/${oldItem['mug_id'] ?? oldItem['MugID']}');

      var request = http.MultipartRequest(oldItem == null ? 'POST' : 'PUT', uri);
      request.headers.addAll(_authHeaders);
      request.fields['mug_name'] = name;
      request.fields['mug_zone'] = zone.isEmpty ? '1' : zone;

      if (kIsWeb) {
        if (imageBytes != null && imageFileName != null) {
          request.files.add(http.MultipartFile.fromBytes('mug_image', imageBytes, filename: imageFileName));
        }
      } else {
        if (imageFile != null) {
          request.files.add(await http.MultipartFile.fromPath('mug_image', imageFile.path));
        }
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        ApiClient.clearCache();
        _fetchMuscleGroups();
        AdminDataBus.bumpMuscleGroups();
        Navigator.pop(context);
        _showSnackBar(oldItem == null ? 'เพิ่มสำเร็จ' : 'แก้ไขสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('บันทึกไม่สำเร็จ: ${response.statusCode}');
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  void _showForm({Map<String, dynamic>? item}) {
    final nameCtrl = TextEditingController(text: item?['mug_name'] ?? item?['MugName'] ?? '');
    String selectedZone = (item?['mug_zone'] ?? item?['MugZone'])?.toString() ?? '1';

    File? selectedImage;
    Uint8List? selectedImageBytes;
    String? selectedImageName;
    final ImagePicker picker = ImagePicker();

    InputDecoration fieldDecoration() => const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );

    Widget labeled(String label, Widget field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
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
            final pickedFile = await picker.pickImage(source: ImageSource.gallery);
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
            imagePreview = Image.memory(selectedImageBytes!, fit: BoxFit.cover);
          } else if ((item?['mug_image'] ?? item?['MugImage']) != null && (item?['mug_image'] ?? item?['MugImage']) != '') {
            final imgVal = item!['mug_image'] ?? item['MugImage'];
            final imgUrl = ApiClient.prefixPath(imgVal);
            imagePreview = imgUrl != null
                ? AdminNetworkImage(imgUrl, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.add_a_photo, size: 40))
                : const Icon(Icons.add_a_photo, size: 40);
          } else {
            imagePreview = const Icon(Icons.add_a_photo, size: 40, color: Colors.grey);
          }

          return Dialog(
            backgroundColor: AppColors.dialogBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item == null ? 'เพิ่มกลุ่มกล้ามเนื้อ' : 'แก้ไขกลุ่มกล้ามเนื้อ',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
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
                              ),
                              clipBehavior: Clip.hardEdge,
                              // ไฟล์รูปต้นฉบับส่วนใหญ่มีขอบขาวในตัวรอบภาพประกอบอยู่แล้ว ซูมเข้า
                              // เล็กน้อยชดเชยให้ภาพชนขอบวงกลมพอดี ไม่เหลือขอบขาวให้เห็น
                              child: Transform.scale(scale: 1.15, child: imagePreview),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('แตะวงกลมเพื่อเปลี่ยนรูปภาพ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    labeled(
                      'ชื่อกลุ่มกล้ามเนื้อ *',
                      TextField(
                        controller: nameCtrl,
                        decoration: fieldDecoration().copyWith(
                          hintText: 'เช่น หน้าอก, หลัง, ต้นขา',
                          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    labeled(
                      'โซน',
                      DropdownButtonFormField<String>(
                        initialValue: selectedZone,
                        decoration: fieldDecoration(),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        items: const [
                          DropdownMenuItem(value: '1', child: Text('โซน 1 — บน')),
                          DropdownMenuItem(value: '2', child: Text('โซน 2 — ล่าง')),
                          DropdownMenuItem(value: '3', child: Text('โซน 3 — แกนกลาง')),
                        ],
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedZone = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _handleSave(item, nameCtrl.text, selectedZone, selectedImage, selectedImageBytes, selectedImageName),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
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

  static const Map<String, String> _zoneNames = {'1': 'บน', '2': 'ล่าง', '3': 'แกนกลาง'};
  static const Map<String, Color> _zoneColors = {'1': Color(0xFF1976D2), '2': Color(0xFFEF6C00), '3': Color(0xFF8E24AA)};

  @override
  Widget build(BuildContext context) {
    if (_drillMugId != null) {
      return ManageWeightExercisesView(
        initialMugId: _drillMugId,
        onBack: () => setState(() => _drillMugId = null),
      );
    }
    final allRows = _filteredItems;
    final totalPages = allRows.isEmpty ? 1 : ((allRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage > totalPages ? totalPages : _currentPage;
    final rows = allRows.skip((safePage - 1) * _pageSize).take(_pageSize).toList();

    final AdminListState? stateOverride = _isLoadingData
        ? AdminListState.loading
        : _hasError
            ? AdminListState.error
            : allRows.isEmpty
                ? (_searchQuery.isNotEmpty ? AdminListState.noResult : AdminListState.empty)
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPageHeader(
          breadcrumb: const ['เวทเทรนนิ่ง', 'กลุ่มกล้ามเนื้อ'],
          onAdd: () => _showForm(),
          addLabel: 'เพิ่มกลุ่มกล้ามเนื้อ',
        ),
        AdminFilterBar(
          searchHint: 'ค้นหาชื่อกลุ่มกล้ามเนื้อ...',
          onSearchChanged: (v) => setState(() {
            _searchQuery = v;
            _currentPage = 1;
          }),
          trailing: [
            for (final z in const [null, '1', '2', '3'])
              Builder(builder: (context) {
                // สีตัวกรองตรงกับสี badge โซนบนการ์ด (_zoneColors) แทนเขียวเดียวทั้งหมด — ให้กด
                // ตัวกรองแล้วจำสีจับคู่กับการ์ดที่จะเห็นได้ทันที (ก่อนหน้านี้ตัวกรองใช้เขียวคงที่
                // ไม่ตรงกับสีบนการ์ดที่เป็นฟ้า/ส้ม/ม่วงตามโซน)
                final Color chipColor = z == null ? AppColors.primaryGreen : (_zoneColors[z] ?? AppColors.primaryGreen);
                return GestureDetector(
                  onTap: () => setState(() {
                    _filterZone = z;
                    _currentPage = 1;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _filterZone == z ? chipColor : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: chipColor),
                    ),
                    child: Text(
                      z == null ? 'ทั้งหมด' : 'โซน${_zoneNames[z]}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _filterZone == z ? Colors.white : chipColor),
                    ),
                  ),
                );
              }),
          ],
          resultCount: allRows.length,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: stateOverride != null
              ? AdminListStateView(
                  state: stateOverride,
                  skeletonVariant: AdminSkeletonVariant.cards,
                  onAdd: () => _showForm(),
                  onRetry: _fetchMuscleGroups,
                  onClearFilter: () => setState(() {
                    _searchQuery = '';
                    _filterZone = null;
                    _currentPage = 1;
                  }),
                )
              // fixed 4 คอลัมน์ (ตายตัวไม่ปรับตามความกว้างจอ) การ์ดขยายเต็มพื้นที่แต่ละคอลัมน์เอง
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final item = rows[i];
                    final String? imgPath = item['mug_image'] ?? item['MugImage'];
                    final String name = item['mug_name'] ?? item['MugName'] ?? 'ไม่มีชื่อ';
                    final String zone = (item['mug_zone'] ?? item['MugZone'])?.toString() ?? '';
                    final String? imageUrl = (imgPath != null && imgPath.isNotEmpty) ? ApiClient.prefixPath(imgPath) : null;
                    final int mugId = item['mug_id'] ?? item['MugID'];

                    return _MuscleGroupCard(
                      imageUrl: imageUrl,
                      name: name,
                      zoneLabel: zone.isEmpty ? null : 'โซน${_zoneNames[zone] ?? zone}',
                      zoneColor: _zoneColors[zone] ?? AppColors.textBody,
                      exerciseCount: _linkedCounts[mugId] ?? 0,
                      onTap: () => setState(() => _drillMugId = mugId),
                      onEdit: () => _showForm(item: item),
                      onDelete: () => _handleDelete(mugId, name),
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

// การ์ดกลุ่มกล้ามเนื้อในกริด — ปุ่มแก้ไข/ลบเป็น overlay มุมขวาบนของรูป โผล่เมื่อ hover เท่านั้น
// (ทัชสกรีนไม่มี hover จึงโชว์ปุ่มค้างไว้เสมอ กันปุ่มหายบนมือถือ/แท็บเล็ต)
class _MuscleGroupCard extends StatefulWidget {
  final String? imageUrl;
  final String name;
  final String? zoneLabel;
  final Color zoneColor;
  final int exerciseCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MuscleGroupCard({
    required this.imageUrl,
    required this.name,
    required this.zoneLabel,
    required this.zoneColor,
    required this.exerciseCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_MuscleGroupCard> createState() => _MuscleGroupCardState();
}

class _MuscleGroupCardState extends State<_MuscleGroupCard> {
  bool _hovering = false;

  Widget _placeholderImage() {
    return Container(
      width: double.infinity,
      color: Colors.grey[200],
      child: const Center(child: Icon(Icons.fitness_center, color: Colors.grey, size: 36)),
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
          // ปิด tooltip ค้างก่อนเปิด dialog — ไม่งั้น hover ปุ่มแล้วเด้ง dialog ทับ
          // pointer-exit ไม่ยิง ทำให้ tooltip ค้างอยู่หลังปิด dialog (Flutter web hover bug)
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
                    // badge จำนวนท่าฝึก มุมซ้ายบนของรูป — ตำแหน่ง/สไตล์เดียวกับ badge
                    // จำนวนกิจกรรมในหน้าหมวดหมู่คาร์ดิโอ (มาตรฐานเดียวกันทั้งเว็บ)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                        child: Text('${widget.exerciseCount} ท่าฝึก', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
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
                  const SizedBox(height: 4),
                  if (widget.zoneLabel != null)
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: widget.zoneColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(widget.zoneLabel!, style: TextStyle(fontSize: 11, color: widget.zoneColor, fontWeight: FontWeight.w600)),
                      ),
                    ]),
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

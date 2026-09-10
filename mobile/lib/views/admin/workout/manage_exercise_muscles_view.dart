// หน้า: Admin - Manage Exercise Muscles (จัดการความสัมพันธ์ท่าฝึก-กล้ามเนื้อ)
// ทำหน้าที่: Admin กำหนดกล้ามเนื้อหลักและรองให้กับแต่ละท่าฝึก ใช้เป็นข้อมูลแสดงในหน้ารายละเอียดท่าฝึก

import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_fab.dart';
import '../../../../core/widgets/top_flash.dart';
import 'package:myapp/services/api_client.dart';

const Color _kTeal = Color(0xFF1A9A90);

class ManageExerciseMusclesView extends StatefulWidget {
  const ManageExerciseMusclesView({super.key});

  @override
  State<ManageExerciseMusclesView> createState() => _ManageExerciseMusclesViewState();
}

class _ManageExerciseMusclesViewState extends State<ManageExerciseMusclesView> {
  List<Map<String, dynamic>> mappings = [];
  
  // ตัวแปรสำหรับเก็บข้อมูล Dropdown
  List<Map<String, dynamic>> exercisesList = [];
  List<Map<String, dynamic>> musclesList = [];
  
  bool isLoading = true;

  String get baseUrl => ApiClient.serverUrl;
  String get apiUrl => "$baseUrl/api/exercise-muscles";
  String get _token => GetStorage().read('auth_token') ?? '';
  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    _fetchMappings();
    _fetchDropdownData(); // ดึงข้อมูลท่าฝึกและกล้ามเนื้อรอไว้เลย
  }

  // 1. ดึงข้อมูลรายการที่เชื่อมโยงแล้ว
  Future<void> _fetchMappings() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: _authHeaders);
      debugPrint('=== EXERCISE MUSCLES ${response.statusCode} ===');
      debugPrint(response.body.length > 500 ? response.body.substring(0, 500) : response.body);
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
        setState(() => isLoading = false);
        debugPrint("fetchMappings error: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      debugPrint("Error fetching mappings: $e");
      setState(() => isLoading = false);
    }
  }

  // 2. ดึงข้อมูล Dropdown ท่าฝึก และ กลุ่มกล้ามเนื้อ
  Future<void> _fetchDropdownData() async {
    try {
      final resWe = await http.get(Uri.parse("$baseUrl/api/exercises/weights"), headers: _authHeaders);
      if (resWe.statusCode == 200) {
        final decoded = json.decode(resWe.body);
        List<dynamic> list = decoded is Map
            ? (decoded['data'] ?? decoded['items'] ?? []) as List
            : decoded is List ? decoded : [];
        setState(() => exercisesList = List<Map<String, dynamic>>.from(list));
      }
      final resMu = await http.get(Uri.parse("$baseUrl/api/exercises/muscle-groups"), headers: _authHeaders);
      if (resMu.statusCode == 200) {
        final decoded = json.decode(resMu.body);
        List<dynamic> list = decoded is Map
            ? (decoded['data'] ?? decoded['items'] ?? []) as List
            : decoded is List ? decoded : [];
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

  // 3. ฟังก์ชันบันทึกข้อมูล (รองรับทั้ง เพิ่มใหม่ และ แก้ไข)
  Future<void> _handleSave(int wetId, int mugId, int typeInt, {int? editId}) async {
    _showLoading();
    try {
      http.Response response;
      final body = json.encode({
        "exm_type": typeInt,
        "wet_id": wetId, 
        "mug_id": mugId
      });

      final headers = {"Content-Type": "application/json", "Authorization": "Bearer $_token"};
      if (editId == null) {
        response = await http.post(Uri.parse(apiUrl), headers: headers, body: body);
      } else {
        response = await http.put(Uri.parse('$apiUrl/$editId'), headers: headers, body: body);
      }
      
      Navigator.pop(context); // ปิด Loading
      Navigator.pop(context); // ปิด Form BottomSheet
      
      if (response.statusCode == 200) {
        _fetchMappings(); // โหลดข้อมูลใหม่
        _showSnackBar(editId == null ? 'เพิ่มการเชื่อมโยงสำเร็จ' : 'แก้ไขข้อมูลสำเร็จ', type: AppAlertType.success);
      } else {
        _showSnackBar('เกิดข้อผิดพลาดในการบันทึก');
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // 4. ฟังก์ชันลบข้อมูล
  Future<void> _handleDelete(int id, String ex, String mu) async {
    bool confirm = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'ยืนยันการลบ?',
      content: 'ต้องการลบ "$mu" ใช่หรือไม่?',
      confirmLabel: 'ลบข้อมูล',
    );

    if (confirm) {
      _showLoading();
      try {
        final response = await http.delete(Uri.parse('$apiUrl/$id'), headers: _authHeaders);
        Navigator.pop(context); // ปิด Loading
        
        if (response.statusCode == 200) {
          _fetchMappings();
          showAdminTopToast(context, 'ลบข้อมูลเรียบร้อย');
        } else {
          _showSnackBar('ลบไม่สำเร็จ');
        }
      } catch (e) {
        Navigator.pop(context);
        _showSnackBar('Error: $e');
      }
    }
  }

  // 5. ฟังก์ชันแสดงฟอร์ม (รองรับทั้ง กดเพิ่ม(+) และ กดแก้ไข(คลิกการ์ด))
  void _showForm({Map<String, dynamic>? item}) {
    // ถ้ามี item ส่งมา ให้ดึงค่าเก่ามาแสดงใน Dropdown
    int? selectedWetId = item?['wet_id'];
    int? selectedMugId = item?['mug_id'];
    String selectedType = item?['type'] ?? 'หลัก';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item == null ? 'เพิ่มการเชื่อมโยง' : 'แก้ไขการเชื่อมโยง', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                
                // Dropdown ท่าฝึก
                const Text('เลือกท่าฝึก',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: selectedWetId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  items: exercisesList.map((e) => DropdownMenuItem<int>(
                    value: e['wet_id'],
                    child: Text(e['wet_name']),
                  )).toList(),
                  onChanged: (val) => setModalState(() => selectedWetId = val),
                ),
                const SizedBox(height: 15),

                // Dropdown กล้ามเนื้อ
                const Text('เลือกกล้ามเนื้อ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: selectedMugId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  items: musclesList.map((e) => DropdownMenuItem<int>(
                    value: e['mug_id'],
                    child: Text(e['mug_name']),
                  )).toList(),
                  onChanged: (val) => setModalState(() => selectedMugId = val),
                ),
                const SizedBox(height: 15),

                // ประเภทกล้ามเนื้อ (หลัก/รอง)
                const Text('ประเภทกล้ามเนื้อ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
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
                        // ส่ง item?['id'] ไปด้วย ถ้าเป็นการกดแก้ไข
                        _handleSave(selectedWetId!, selectedMugId!, typeInt, editId: item?['id']);
                      } else {
                        _showSnackBar("กรุณาเลือกท่าฝึกและกล้ามเนื้อให้ครบถ้วน");
                      }
                    },
                    child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, bottom: 25, left: 20, right: 20),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_kTeal, Color(0xFF0D7870)]), borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
            child: Row(
              children: [
                AppBackButton(),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Exercise Focus', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('กำหนดกล้ามเนื้อหลัก/รอง ให้กับท่าฝึก', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
              : RefreshIndicator(
                  onRefresh: () async {
                    ApiClient.clearCache();
                    await _fetchMappings();
                  },
                  child: mappings.isEmpty 
                    ? const Center(child: Text("ไม่มีข้อมูลการเชื่อมโยง"))
                    : ListView.builder(
                        itemCount: mappings.length,
                        itemBuilder: (context, i) => _buildItemCard(mappings[i]),
                      ),
                ),
          ),
        ],
      ),
      floatingActionButton: AppFab(onPressed: _showForm),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(item['exercise'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
        subtitle: Text("กล้ามเนื้อ: ${item['muscle']}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: item['type'] == "หลัก" ? Colors.green[50] : Colors.grey[50], 
                borderRadius: BorderRadius.circular(8), 
                border: Border.all(color: item['type'] == "หลัก" ? Colors.green[100]! : Colors.grey[200]!)
              ),
              child: Text(item['type'], style: TextStyle(fontSize: 12, color: item['type'] == "หลัก" ? Colors.green[700] : Colors.grey[600], fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent), 
              onPressed: () => _handleDelete(item['id'], item['exercise'], item['muscle'])
            ),
          ],
        ),
        // 🟢 เพิ่ม onTap ตรงนี้ เพื่อให้จิ้มที่ตัวการ์ดแล้วเด้งหน้าต่างแก้ไขขึ้นมาได้
        onTap: () => _showForm(item: item),
      ),
    );
  }
}
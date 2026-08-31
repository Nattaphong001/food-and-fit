import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/workout_model.dart';
import 'api_client.dart';

class WorkoutService extends GetxService {
  static WorkoutService get to => Get.find();

  final ApiClient _api = ApiClient();
  final GetStorage _storage = GetStorage();
  final isLoading = false.obs;

  // ฟังก์ชันช่วยจัดการข้อมูล Dynamic List จาก API
  List<dynamic> _parseList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      const keys = ['data', 'items', 'result', 'results', 'details',
                    'workout_results', 'cardio_results', 'records'];
      for (final k in keys) {
        if (raw[k] is List) return raw[k] as List;
      }
    }
    return [];
  }

  // ==========================================
  // 0. WORKOUT DAY MAP (แหล่งเดียว ห้ามก็อปไปไฟล์อื่น)
  // ==========================================

  // จำนวนวันฝึก/สัปดาห์ (แผนระบบ) → index วันในสัปดาห์ที่ต้องฝึก (0=จันทร์ … 6=อาทิตย์)
  // ⚠️ ก็อปมาคู่กับ planDayWeekday ใน workout_controller.go (1=จันทร์…7=อาทิตย์ — index ต่างกัน 1)
  // แก้ฝั่งใดฝั่งหนึ่งแล้วไม่แก้อีกฝั่ง → วันพัก/วันฝึกจะเพี้ยนแบบไม่มี error ให้เห็น ต้องแก้คู่กันเสมอ
  static const Map<int, List<int>> workoutDayMap = {
    2: [0, 3],
    3: [0, 2, 4],
    4: [0, 1, 3, 4],
    5: [0, 1, 2, 3, 4],
    6: [0, 1, 2, 3, 4, 5],
  };

  // map วันในสัปดาห์ของ date → dayNumber ในแผน (1-N), 0 = วันพัก
  // ใช้กับแผนระบบเท่านั้น (isWeekdayBased == false) — แผนส่วนตัวใช้ date.weekday ตรงๆ
  static int dayNumberForWeekday(DateTime date, int planDays) {
    final days = workoutDayMap[planDays] ?? [0, 2, 4];
    final weekdayIdx = date.weekday - 1; // Mon=0 … Sun=6
    final idx = days.indexOf(weekdayIdx);
    return idx + 1; // idx == -1 → 0 (วันพัก)
  }

  // ==========================================
  // 1. LOCAL STORAGE & ACTIVE PLAN (จัดการสถานะในเครื่อง)
  // ==========================================

  int? get activePlanId => _storage.read<int>('active_plan_id');
  int get activePlanDays => _storage.read<int>('active_plan_days') ?? 3;
  String get activePlanName => _storage.read<String>('active_plan_name') ?? '';
  String get activePlanType => _storage.read<String>('active_plan_type') ?? 'system';
  bool get activePlanIsWeekdayBased => _storage.read<bool>('active_plan_weekday_based') ?? false;
  bool get hasActivePlan => _storage.hasData('active_plan_id');

  int? getUserPlanId(int days) => _storage.read<int>('user_plan_$days');
  String getUserPlanName(int days) => _storage.read<String>('user_plan_name_$days') ?? '$days วัน/สัปดาห์';

  void _saveUserPlan(int days, int planId, String name) {
    _storage.write('user_plan_$days', planId);
    _storage.write('user_plan_name_$days', name);
  }

  void _clearUserPlan(int days) {
    _storage.remove('user_plan_$days');
    _storage.remove('user_plan_name_$days');
  }

  Future<void> saveActivePlan(int planId, int days, String name, {String type = 'system', bool weekdayBased = false}) async {
    _storage.write('active_plan_id', planId);
    _storage.write('active_plan_days', days);
    _storage.write('active_plan_name', name);
    _storage.write('active_plan_type', type);
    _storage.write('active_plan_weekday_based', weekdayBased);
    _saveUserPlan(days, planId, name);
  }

  void clearActivePlan() {
    _storage.remove('active_plan_id');
    _storage.remove('active_plan_days');
    _storage.remove('active_plan_name');
    _storage.remove('active_plan_type');
    _storage.remove('active_plan_weekday_based');
  }

  void clearAllPlanStorage() {
    clearActivePlan();
    // ล้าง user_plan ทุก slot (2-7 วัน)
    for (int d = 2; d <= 7; d++) {
      _clearUserPlan(d);
    }
  }

  // ==========================================
  // 2. SYSTEM PLAN API (แผนแม่แบบจากระบบ)
  // ==========================================

  Future<Map<String, dynamic>> getPlans() async {
    try {
      isLoading.value = true;
      final response = await _api.get('/workouts/plans');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final plans = list.map((e) => WorkoutPlan.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': plans};
      }
      return {'success': false, 'message': 'โหลดแผนออกกำลังกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getPlanDetails({int? planId}) async {
    try {
      isLoading.value = true;
      final query = planId != null ? '?plan_id=$planId' : '';
      final response = await _api.get('/workouts/details$query');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final details = list.map((e) => PlanDetail.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': details};
      }
      return {'success': false, 'message': 'โหลดรายละเอียดแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<List<dynamic>> getPlanTemplates() async {
    try {
      final response = await _api.get('/workouts/templates');
      if (response.statusCode == 200) {
        return _parseList(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('Error: $e');
      return [];
    }
  }

  // ==========================================
  // 3. MEMBER PLAN API (แผนที่ผู้ใช้เลือก/สร้าง)
  // ==========================================

  // เลือกแผนระบบด้วย wpt_id ตรงๆ (ผู้เรียกส่งมาจากการ์ดที่กดใน WorkoutDaysSelectionView) → copy
  // ท่าทั้งหมดลง workout_schedules ไม่ต้องค้นหา template เอง กัน bug เวลามีแผนจำนวนวันซ้ำกัน
  Future<Map<String, dynamic>> selectPlan(int wptId) async {
    try {
      isLoading.value = true;
      final response = await _api.post('/member/workout-plans/select', {'plan_id': wptId});
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'เลือกแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    } finally {
      isLoading.value = false;
    }
  }

  // ดึงท่าออกกำลังกายจาก workout_schedules สำหรับวันที่ X ของแผน
  Future<Map<String, dynamic>> getSchedulesForDay(int planId, int dayNumber, {bool isCustom = false}) async {
    try {
      final planParam = isCustom ? 'mwp_id=$planId' : 'plan_id=$planId';
      final response = await _api.get('/member/workout-schedules?$planParam&day_number=$dayNumber');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final schedules = list.map((e) => UserWorkoutSchedule.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': schedules};
      }
      if (response.statusCode == 404) {
        final raw = response.data;
        if (raw is Map && raw['plan_not_found'] == true) {
          _clearStalePlan(planId);
          return {'success': false, 'plan_not_found': true, 'message': raw['message'] ?? 'ไม่พบแผน'};
        }
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ดึงท่าทั้งหมดของแผน (ทุก day_number)
  Future<Map<String, dynamic>> getAllSchedulesForPlan(int planId, {bool isCustom = false}) async {
    try {
      final planParam = isCustom ? 'mwp_id=$planId' : 'plan_id=$planId';
      final response = await _api.get('/member/workout-schedules?$planParam');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final schedules = list.map((e) => UserWorkoutSchedule.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': schedules};
      }
      if (response.statusCode == 404) {
        final raw = response.data;
        if (raw is Map && raw['plan_not_found'] == true) {
          _clearStalePlan(planId);
          return {'success': false, 'plan_not_found': true};
        }
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // เพิ่มท่าออกกำลังกายเข้าแผน (workout_schedules)
  Future<Map<String, dynamic>> addExerciseToSchedule({
    required int planId,
    required int dayNumber,
    required int wetId,
    int sets = 3,
    String reps = '10',
    bool isCustom = false,
  }) async {
    try {
      final response = await _api.post('/member/workout-schedules', {
        if (isCustom) 'mwp_id': planId else 'plan_id': planId,
        'day_number': dayNumber,
        'wet_id': wetId,
        'sets': sets,
        'reps': reps,
      });
      if (response.statusCode == 200) {
        final raw = response.data as Map<String, dynamic>?;
        final data = raw?['data'] as Map<String, dynamic>?;
        final wschId = data?['wsch_id'] as int?;
        return {'success': true, 'wsch_id': wschId};
      }
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'เพิ่มท่าไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // ลบท่าออกจากแผน (workout_schedules)
  Future<Map<String, dynamic>> removeExerciseFromSchedule(int wschId) async {
    try {
      final response = await _api.delete('/member/workout-schedules/$wschId');
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'ลบท่าไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // ==========================================
  // 3a. "แผนของฉัน" — รองรับหลายแผนส่วนตัว + แผนระบบที่เคยเลือก, เลือกแผน active ได้ชัดเจน
  // ==========================================

  // รวมทุกแผนของ user: [{plan_type, wpt_id, mwp_id, name, days_per_week, is_active}, ...]
  Future<Map<String, dynamic>> getMyPlans() async {
    try {
      final response = await _api.get('/member/workout-plans/mine');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        return {'success': true, 'data': list.cast<Map<String, dynamic>>()};
      }
      return {'success': false, 'message': 'โหลดแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> createPersonalPlan(String name) async {
    try {
      final response = await _api.post('/member/workout-plans/mine', {'name': name});
      if (response.statusCode == 200) {
        final raw = response.data as Map<String, dynamic>;
        return {'success': true, 'mwp_id': raw['mwp_id'] as int, 'name': raw['name'] as String? ?? name};
      }
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'สร้างแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  Future<Map<String, dynamic>> renamePersonalPlan(int mwpId, String name) async {
    try {
      final response = await _api.patch('/member/workout-plans/mine/$mwpId', {'name': name});
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'แก้ชื่อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  Future<Map<String, dynamic>> deletePersonalPlan(int mwpId) async {
    try {
      final response = await _api.delete('/member/workout-plans/mine/$mwpId');
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'ลบแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // ลบสำเนาแผนระบบที่ copy มาไว้ (ลบแค่ของ user เอง ไม่แตะแผนต้นฉบับที่แชร์กับคนอื่น)
  Future<Map<String, dynamic>> deleteSystemPlanCopy(int wptId) async {
    try {
      final response = await _api.delete('/member/workout-plans/system/$wptId');
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'ลบแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // คัดลอกแผนระบบ (wptId) → แผนส่วนตัวใหม่ (mwp_id) แก้ไขได้อิสระ ไม่แตะ/ไม่ลบสำเนา wptId เดิม
  // (อยู่คู่กันได้ในลิสต์ "แผนของฉัน") ไม่ auto-activate ให้เอง
  Future<Map<String, dynamic>> forkPlan(int wptId) async {
    try {
      final response = await _api.post('/member/workout-plans/fork', {'wpt_id': wptId});
      if (response.statusCode == 200) {
        final raw = response.data as Map<String, dynamic>;
        return {
          'success': true,
          'mwp_id': raw['mwp_id'] as int,
          'name': raw['name'] as String? ?? 'แผนของฉัน',
        };
      }
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'คัดลอกแผนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ตั้งแผนที่ใช้งานอยู่ — ระบุ wptId (แผนระบบ) หรือ mwpId (แผนส่วนตัว) อย่างใดอย่างหนึ่ง
  Future<Map<String, dynamic>> activatePlan({int? wptId, int? mwpId}) async {
    try {
      final response = await _api.post('/member/workout-plans/activate', {
        if (wptId != null) 'wpt_id': wptId,
        if (mwpId != null) 'mwp_id': mwpId,
      });
      if (response.statusCode == 200) {
        return {'success': true, 'is_custom': (response.data as Map)['is_custom'] as bool? ?? mwpId != null};
      }
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'ตั้งแผนที่ใช้งานไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // แก้ sets/reps ของท่าที่มีอยู่แล้วในแผน — ค่าระบบตั้งมาเป็นแค่ default เริ่มต้น ผู้ใช้ปรับเองได้
  Future<Map<String, dynamic>> updateSchedule(int wschId, {int? sets, String? reps}) async {
    try {
      final response = await _api.patch('/member/workout-schedules/$wschId', {
        if (sets != null) 'sets': sets,
        if (reps != null) 'reps': reps,
      });
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'แก้ไขไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // รีเซ็ตแผนใดก็ได้กลับเป็นค่าเริ่มต้น — ระบบ=คัดลอกท่าจากแม่แบบใหม่ทับของเดิม, ส่วนตัว=ล้างท่าออกให้ว่างเปล่า
  // ใช้ทั้งจากหน้าตารางฝึกของแผนนั้นตรงๆ และจากหน้า "แผนของฉัน" (ไม่ต้องเป็นแผน active ก็รีเซ็ตได้)
  Future<Map<String, dynamic>> resetPlan({int? wptId, int? mwpId}) async {
    try {
      final response = await _api.post('/member/workout-plans/reset',
          mwpId != null ? {'mwp_id': mwpId} : {'plan_id': wptId});
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': (response.data as Map?)?['error'] ?? 'รีเซ็ตไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เชื่อมต่อเครือข่ายไม่สำเร็จ กรุณาลองใหม่', 'network_error': true};
    }
  }

  // ดึงแผนที่ใช้งานอยู่จาก server ทุกครั้ง (ไม่ใช่แค่ตอน storage ว่าง) — กันชื่อ/จำนวนวันฝึกค้าง
  // จากแคชเก่าเมื่อแอดมินแก้ไขแผนระบบภายหลัง (เปลี่ยนชื่อ/เพิ่มลดวัน) ผู้ใช้ต้องเห็นค่าล่าสุดเสมอ
  // คืน {'success': true, 'has_plan': true/false}
  Future<Map<String, dynamic>> refreshActivePlanFromServer() async {
    try {
      // ดึงแผนที่ใช้งานอยู่จริง (จาก member_profile.mb_active_wpt_id/mb_active_mwp_id ฝั่ง backend)
      final response = await _api.get('/member/workout-plans/active');
      if (response.statusCode == 200) {
        final body = response.data as Map<String, dynamic>? ?? {};
        if (body['has_plan'] == true) {
          final d = body['data'] as Map<String, dynamic>;
          final planId   = d['plan_id'] as int;
          final days     = d['days_per_week'] as int;
          final name     = (d['plan_name'] as String?) ?? '$days วัน/สัปดาห์';
          final isCustom = d['is_custom'] as bool? ?? false;
          await saveActivePlan(planId, days, name,
              type: isCustom ? 'custom' : 'system',
              weekdayBased: isCustom);
          return {'success': true, 'has_plan': true};
        }
        // server บอกว่าไม่มีแผนแล้ว (เช่น ถูกลบจากเครื่องอื่น) → เคลียร์แคชเก่าทิ้งด้วย
        clearActivePlan();
      }
      return {'success': true, 'has_plan': false};
    } catch (e) {
      return {'success': false, 'has_plan': false};
    }
  }

  Future<Map<String, dynamic>> getMemberPlans() async {
    try {
      final response = await _api.get('/member/workout-plans');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final plans = list.map((e) => WorkoutPlan.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': plans};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> addMemberPlanDetail(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/member/workout-plans/details', data);
      return {'success': response.statusCode == 200 || response.statusCode == 201};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> getMemberPlanDetails({int? planId}) async {
    try {
      final query = planId != null ? '?plan_id=$planId' : '';
      final response = await _api.get('/member/workout-plans/details$query');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final details = list.map((e) => PlanDetail.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': details};
      }
      // แผนหายไป (เช่น หลัง seed DB) → ล้าง storage อัตโนมัติ
      if (response.statusCode == 404) {
        final raw = response.data;
        if (raw is Map && raw['plan_not_found'] == true) {
          _clearStalePlan(planId);
          return {'success': false, 'plan_not_found': true, 'message': raw['message'] ?? 'ไม่พบแผน'};
        }
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  void _clearStalePlan(int? planId) {
    if (planId == null) return;
    if (activePlanId == planId) {
      final days = activePlanDays;
      clearActivePlan();
      _clearUserPlan(days);
    }
  }

  Future<Map<String, dynamic>> deleteMemberPlan(int id) async {
    try {
      final response = await _api.delete('/member/workout-plans/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> deleteMemberPlanDetail(int id) async {
    try {
      final response = await _api.delete('/member/workout-plans/details/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  // ==========================================
  // 4. WORKOUT RESULTS & SCHEDULES (ตารางฝึกและบันทึกผล)
  // ==========================================

  Future<Map<String, dynamic>> createSchedule(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/member/workout-schedules', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final raw = response.data;
        int? id;
        if (raw is Map) {
          final d = raw['data'] is Map ? raw['data'] as Map : raw;
          id = int.tryParse((d['wsch_id'] ?? d['schedule_id'] ?? d['id'])?.toString() ?? '');
        }
        return {'success': true, 'wsch_id': id};
      }
      final msg = (response.data is Map)
          ? (response.data['error'] ?? response.data['message'] ?? 'HTTP ${response.statusCode}')
          : 'HTTP ${response.statusCode}';
      return {'success': false, 'message': msg.toString()};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getSchedules() async {
    try {
      final response = await _api.get('/member/workout-schedules');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final schedules = list.map((e) => UserWorkoutSchedule.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': schedules};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> saveWorkoutResult(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/member/workout-results', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final estimated1rm = (response.data is Map)
            ? (response.data['estimated_1rm'] as num?)?.toDouble() ?? 0.0
            : 0.0;
        return {'success': true, 'estimated_1rm': estimated1rm};
      }
      final msg = (response.data is Map)
          ? (response.data['error'] ?? response.data['message'] ?? 'HTTP ${response.statusCode}')
          : 'HTTP ${response.statusCode}';
      return {'success': false, 'message': msg.toString()};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getBest1RM(int wetId) async {
    try {
      final response = await _api.get('/member/exercises/$wetId/best-1rm');
      if (response.statusCode == 200 && response.data is Map) {
        return {
          'success': true,
          'best_1rm': (response.data['best_1rm'] as num?)?.toDouble() ?? 0.0,
          'best_weight': (response.data['best_weight'] as num?)?.toDouble() ?? 0.0,
          'best_reps': (response.data['best_reps'] as num?)?.toInt() ?? 0,
          'date': response.data['date'] ?? '',
          'has_data': response.data['has_data'] ?? false,
        };
      }
      return {'success': false, 'best_1rm': 0.0, 'has_data': false};
    } catch (e) {
      return {'success': false, 'best_1rm': 0.0, 'has_data': false};
    }
  }

  Future<Map<String, dynamic>> getWorkoutResults({DateTime? date}) async {
    try {
      final query = date != null ? '?date=${date.toIso8601String().split('T').first}' : '';
      final response = await _api.get('/member/workout-results$query');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final results = list.map((e) => WorkoutResult.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': results};
      }
      return {'success': false, 'message': 'status ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getExerciseHistory(int exerciseId) async {
    try {
      final response = await _api.get('/member/workout-results?wet_id=$exerciseId');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final results = list.map((e) => WorkoutResult.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': results};
      }
      return {'success': false, 'message': 'status ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> saveCardioResult(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/member/cardio-results', data);
      return {'success': response.statusCode == 200 || response.statusCode == 201};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> getCardioResults({DateTime? date}) async {
    try {
      final query = date != null ? '?date=${date.toIso8601String().split('T').first}' : '';
      final response = await _api.get('/member/cardio-results$query');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final results = list.map((e) => CardioResult.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': results};
      }
      return {'success': false, 'message': 'status ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteWorkoutResult(int id) async {
    try {
      final response = await _api.delete('/member/workout-results/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteCardioResult(int id) async {
    try {
      final response = await _api.delete('/member/cardio-results/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ==========================================
  // 5. ADMIN API (จัดการแผนพื้นฐานของระบบ)
  // ==========================================

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/workouts/plans', data);
      return {'success': response.statusCode == 200 || response.statusCode == 201};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> updatePlan(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/workouts/plans/$id', data);
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> deletePlan(int id) async {
    try {
      final response = await _api.delete('/workouts/plans/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> addPlanDetail(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/workouts/details', data);
      return {'success': response.statusCode == 200 || response.statusCode == 201};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> updatePlanDetail(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/workouts/details/$id', data);
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> deletePlanDetail(int id) async {
    try {
      final response = await _api.delete('/workouts/details/$id');
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }
}
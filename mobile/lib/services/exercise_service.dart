import 'package:get/get.dart';
import '../models/exercise_model.dart';
import 'api_client.dart';

class ExerciseService extends GetxService {
  static ExerciseService get to => Get.find();

  final ApiClient _api = ApiClient();
  final isLoading = false.obs;

  List<MuscleGroup>? _cachedMuscleGroups;
  List<Exercise>? _cachedWeightExercises;
  List<CardioType>? _cachedCardioActivities;
  List<CardioCategory>? _cachedCardioCategories;

  void clearExerciseCache() {
    _cachedWeightExercises = null;
    _cachedMuscleGroups = null;
  }

  void clearCardioCache() {
    _cachedCardioActivities = null;
    _cachedCardioCategories = null;
  }

  List<dynamic> _parseList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) return (raw['data'] ?? []) as List;
    return [];
  }

  // ==========================================
  // Member endpoints
  // ==========================================

  Future<Map<String, dynamic>> getMuscleGroups() async {
    if (_cachedMuscleGroups != null) {
      return {'success': true, 'data': _cachedMuscleGroups!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/exercises/muscle-groups');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final groups = list.map((e) => MuscleGroup.fromJson(e as Map<String, dynamic>)).toList();
        _cachedMuscleGroups = groups;
        return {'success': true, 'data': groups};
      }
      return {'success': false, 'message': 'โหลดกลุ่มกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getWeightExercises() async {
    if (_cachedWeightExercises != null) {
      return {'success': true, 'data': _cachedWeightExercises!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/exercises/weights');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final exercises = list.map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
        _cachedWeightExercises = exercises;
        return {'success': true, 'data': exercises};
      }
      return {'success': false, 'message': 'โหลดท่าออกกำลังกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getExerciseMuscles({int? exerciseId}) async {
    try {
      isLoading.value = true;
      final query = exerciseId != null ? '?wet_id=$exerciseId' : '';
      final response = await _api.get('/exercise-muscles$query');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final muscles = list
            .map((e) => ExerciseMuscle.fromJson(e as Map<String, dynamic>))
            .where((m) => exerciseId == null || m.exerciseId == exerciseId)
            .toList();
        return {'success': true, 'data': muscles};
      }
      return {'success': false, 'message': 'โหลดข้อมูลกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getCardioActivities() async {
    if (_cachedCardioActivities != null) {
      return {'success': true, 'data': _cachedCardioActivities!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/exercises/cardio');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final cardios = list.map((e) => CardioType.fromJson(e as Map<String, dynamic>)).toList();
        _cachedCardioActivities = cardios;
        return {'success': true, 'data': cardios};
      }
      return {'success': false, 'message': 'โหลดกิจกรรมคาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  // ==========================================
  // Admin endpoints
  // ==========================================

  Future<Map<String, dynamic>> createMuscleGroup(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/exercises/muscle-groups', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedMuscleGroups = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มกลุ่มกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มกลุ่มกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateMuscleGroup(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/exercises/muscle-groups/$id', data);
      if (response.statusCode == 200) {
        _cachedMuscleGroups = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขกลุ่มกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'แก้ไขกลุ่มกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteMuscleGroup(int id) async {
    try {
      final response = await _api.delete('/exercises/muscle-groups/$id');
      if (response.statusCode == 200) {
        _cachedMuscleGroups = null;
        return {'success': true, 'message': 'ลบกลุ่มกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบกลุ่มกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> createWeightExercise(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/exercises/weights', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedWeightExercises = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มท่าออกกำลังกายสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มท่าออกกำลังกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateWeightExercise(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/exercises/weights/$id', data);
      if (response.statusCode == 200) {
        _cachedWeightExercises = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขท่าออกกำลังกายสำเร็จ'};
      }
      return {'success': false, 'message': 'แก้ไขท่าออกกำลังกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteWeightExercise(int id) async {
    try {
      final response = await _api.delete('/exercises/weights/$id');
      if (response.statusCode == 200) {
        _cachedWeightExercises = null;
        return {'success': true, 'message': 'ลบท่าออกกำลังกายสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบท่าออกกำลังกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  // ─── Cardio Categories ───

  Future<Map<String, dynamic>> getCardioCategories() async {
    if (_cachedCardioCategories != null) {
      return {'success': true, 'data': _cachedCardioCategories!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/exercises/cardio-categories');
      if (response.statusCode == 200) {
        final list = _parseList(response.data);
        final categories = list.map((e) => CardioCategory.fromJson(e as Map<String, dynamic>)).toList();
        _cachedCardioCategories = categories;
        return {'success': true, 'data': categories};
      }
      return {'success': false, 'message': 'โหลดหมวดหมู่คาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> createCardioCategory(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/exercises/cardio-categories', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedCardioCategories = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มหมวดหมู่คาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มหมวดหมู่คาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateCardioCategory(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/exercises/cardio-categories/$id', data);
      if (response.statusCode == 200) {
        _cachedCardioCategories = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขหมวดหมู่คาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'แก้ไขหมวดหมู่คาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteCardioCategory(int id) async {
    try {
      final response = await _api.delete('/exercises/cardio-categories/$id');
      if (response.statusCode == 200) {
        _cachedCardioCategories = null;
        return {'success': true, 'message': 'ลบหมวดหมู่คาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบหมวดหมู่คาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  // ─── Cardio Exercises ───

  Future<Map<String, dynamic>> createCardioExercise(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/exercises/cardio', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedCardioActivities = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มกิจกรรมคาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มกิจกรรมคาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateCardioExercise(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/exercises/cardio/$id', data);
      if (response.statusCode == 200) {
        _cachedCardioActivities = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขกิจกรรมคาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': 'แก้ไขกิจกรรมคาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteCardioExercise(int id) async {
    try {
      final response = await _api.delete('/exercises/cardio/$id');
      if (response.statusCode == 200) {
        _cachedCardioActivities = null;
        return {'success': true, 'message': 'ลบกิจกรรมคาร์ดิโอสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบกิจกรรมคาร์ดิโอไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  // ─── Exercise ↔ Muscle Mapping ───

  Future<Map<String, dynamic>> createExerciseMuscleDetail(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/exercise-muscles', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มข้อมูลกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มข้อมูลกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateExerciseMuscleDetail(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/exercise-muscles/$id', data);
      if (response.statusCode == 200) {
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขข้อมูลกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': 'แก้ไขข้อมูลกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteExerciseMuscleDetail(int id) async {
    try {
      final response = await _api.delete('/exercise-muscles/$id');
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'ลบข้อมูลกล้ามเนื้อสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบข้อมูลกล้ามเนื้อไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }
}

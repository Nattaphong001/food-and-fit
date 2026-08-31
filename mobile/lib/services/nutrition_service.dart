import 'package:get/get.dart';
import '../models/nutrition_model.dart';
import 'api_client.dart';

class NutritionService extends GetxService {
  static NutritionService get to => Get.find();

  final ApiClient _api = ApiClient();
  final isLoading = false.obs;

  List<NutritionCategory>? _cachedCategories;
  List<Food>? _cachedFoods;

  void clearFoodsCache() => _cachedFoods = null;
  void clearCategoriesCache() => _cachedCategories = null;

  // ==========================================
  // Member endpoints
  // ==========================================

  Future<Map<String, dynamic>> getCategories() async {
    if (_cachedCategories != null) {
      return {'success': true, 'data': _cachedCategories!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/nutrition/categories');
      if (response.statusCode == 200) {
        final raw = response.data;
        final list = (raw['data'] ?? raw) as List? ?? [];
        final categories = list.map((e) => NutritionCategory.fromJson(e as Map<String, dynamic>)).toList();
        _cachedCategories = categories;
        return {'success': true, 'data': categories};
      }
      return {'success': false, 'message': 'โหลดหมวดหมู่ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getAllFoods() async {
    if (_cachedFoods != null) {
      return {'success': true, 'data': _cachedFoods!};
    }
    try {
      isLoading.value = true;
      final response = await _api.get('/nutrition/foods');
      if (response.statusCode == 200) {
        final raw = response.data;
        final list = (raw['data'] ?? raw) as List? ?? [];
        final foods = list.map((e) => Food.fromJson(e as Map<String, dynamic>)).toList();
        _cachedFoods = foods;
        return {'success': true, 'data': foods};
      }
      return {'success': false, 'message': 'โหลดรายการอาหารไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> searchFoods(String query) async {
    try {
      isLoading.value = true;
      final response = await _api.get('/nutrition/foods/search?q=${Uri.encodeComponent(query)}');
      if (response.statusCode == 200) {
        final raw = response.data;
        final list = (raw['data'] ?? raw) as List? ?? [];
        final foods = list.map((e) => Food.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': foods};
      }
      return {'success': false, 'message': 'ค้นหาไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> addDailyNutrition({
    required int foodId,
    required double quantity,
    required DateTime date,
    required Food food,
    required int mealType,
  }) async {
    try {
      isLoading.value = true;
      final dateStr = date.toIso8601String().split('T').first;
      // ใช้เวลาปัจจุบันจริงตอนกดบันทึก ไม่ใช้เวลาจาก date (มาจากปฏิทินเลือกวัน ไม่มีส่วนเวลา จะได้ 00:00:00 เสมอ)
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';
      final response = await _api.post('/member/nutrition/daily', {
        'ntt_id': foodId,
        'dntt_date': dateStr,
        'dntt_time': timeStr,
        'dntt_meal_type': mealType,
        'dntt_quantity': quantity,
        'dntt_unit': food.unit.isNotEmpty ? food.unit : 'กรัม',
        'dntt_total_calories': food.calories * quantity,
        'dntt_total_protein': food.protein * quantity,
        'dntt_total_carb': food.carbs * quantity,
        'dntt_total_fat': food.fat * quantity,
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'message': response.data['message'] ?? 'บันทึกอาหารสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'บันทึกอาหารไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getDailyNutrition({DateTime? date}) async {
    try {
      isLoading.value = true;
      final dateStr = (date ?? DateTime.now()).toIso8601String().split('T').first;
      final response = await _api.get('/member/nutrition/daily?date=$dateStr');
      if (response.statusCode == 200) {
        final raw = response.data;
        final list = (raw['data'] ?? raw) as List? ?? [];
        final items = list.map((e) => DailyNutrition.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': items};
      }
      return {'success': false, 'message': 'โหลดข้อมูลโภชนาการไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> updateDailyNutrition({
    required int id,
    required int mealType,
    required double quantity,
  }) async {
    try {
      final response = await _api.put('/member/nutrition/$id', {
        'dntt_meal_type': mealType,
        'dntt_quantity': quantity,
      });
      if (response.statusCode == 200) {
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขรายการสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'แก้ไขรายการไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteDailyNutrition(int id) async {
    try {
      final response = await _api.delete('/member/nutrition/$id');
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'ลบรายการสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบรายการไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  // ==========================================
  // Admin endpoints
  // ==========================================

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/nutrition/categories', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedCategories = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มหมวดหมู่สำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มหมวดหมู่ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateCategory(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/nutrition/categories/$id', data);
      if (response.statusCode == 200) {
        _cachedCategories = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขหมวดหมู่สำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'แก้ไขหมวดหมู่ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteCategory(int id) async {
    try {
      final response = await _api.delete('/nutrition/categories/$id');
      if (response.statusCode == 200) {
        _cachedCategories = null;
        return {'success': true, 'message': 'ลบหมวดหมู่สำเร็จ'};
      }
      return {'success': false, 'message': 'ลบหมวดหมู่ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> createFood(Map<String, dynamic> data) async {
    try {
      final response = await _api.post('/nutrition/foods', data);
      if (response.statusCode == 200 || response.statusCode == 201) {
        _cachedFoods = null;
        return {'success': true, 'message': response.data['message'] ?? 'เพิ่มอาหารสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'เพิ่มอาหารไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> updateFood(int id, Map<String, dynamic> data) async {
    try {
      final response = await _api.put('/nutrition/foods/$id', data);
      if (response.statusCode == 200) {
        _cachedFoods = null;
        return {'success': true, 'message': response.data['message'] ?? 'แก้ไขอาหารสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'แก้ไขอาหารไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteFood(int id) async {
    try {
      final response = await _api.delete('/nutrition/foods/$id');
      if (response.statusCode == 200) {
        _cachedFoods = null;
        return {'success': true, 'message': 'ลบอาหารสำเร็จ'};
      }
      return {'success': false, 'message': 'ลบอาหารไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }
}

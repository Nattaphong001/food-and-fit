import 'package:get/get.dart';
import '../models/analytics_model.dart';
import 'api_client.dart';

class AnalyticsService extends GetxService {
  static AnalyticsService get to => Get.find();

  final ApiClient _api = ApiClient();
  final isLoading = false.obs;

  Future<Map<String, dynamic>> getDailyAnalytics({DateTime? date}) async {
    try {
      isLoading.value = true;
      final query = date != null
          ? '?date=${date.toIso8601String().split('T').first}'
          : '';
      final response = await _api.get('/member/analytics/daily$query');
      if (response.statusCode == 200) {
        final analytics =
            DailyAnalytics.fromJson(response.data as Map<String, dynamic>);
        return {'success': true, 'data': analytics};
      }
      return {'success': false, 'message': 'โหลดข้อมูลรายวันไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getDailyMealBreakdown({DateTime? date}) async {
    try {
      final query = date != null
          ? '?date=${date.toIso8601String().split('T').first}'
          : '';
      final response = await _api.get('/member/analytics/daily-meals$query');
      if (response.statusCode == 200 && response.data is Map) {
        final raw = response.data as Map<String, dynamic>;
        final meals = (raw['meals'] as List<dynamic>? ?? [])
            .map((e) => MealBreakdown.fromJson(e as Map<String, dynamic>))
            .toList();
        return {'success': true, 'data': meals};
      }
      return {'success': false, 'data': <MealBreakdown>[]};
    } catch (e) {
      return {'success': false, 'data': <MealBreakdown>[]};
    }
  }

  Future<Map<String, dynamic>> getWeeklyAnalytics({DateTime? date}) async {
    try {
      isLoading.value = true;
      final query = date != null
          ? '?date=${date.toIso8601String().split('T').first}'
          : '';
      final response = await _api.get('/member/analytics/weekly$query');
      if (response.statusCode == 200) {
        final analytics =
            WeeklyAnalytics.fromJson(response.data as Map<String, dynamic>);
        return {'success': true, 'data': analytics};
      }
      return {'success': false, 'message': 'โหลดข้อมูลรายสัปดาห์ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getMonthlyAnalytics({String? month}) async {
    try {
      isLoading.value = true;
      final query = month != null ? '?month=$month' : '';
      final response = await _api.get('/member/analytics/monthly$query');
      if (response.statusCode == 200) {
        final analytics =
            MonthlyAnalytics.fromJson(response.data as Map<String, dynamic>);
        return {'success': true, 'data': analytics};
      }
      return {'success': false, 'message': 'โหลดข้อมูลรายเดือนไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getMonthlyComparison({String? month}) async {
    try {
      final query = month != null ? '?month=$month' : '';
      final response = await _api.get('/member/analytics/monthly-comparison$query');
      if (response.statusCode == 200 && response.data is Map) {
        final c = MonthlyComparison.fromJson(response.data as Map<String, dynamic>);
        return {'success': true, 'data': c};
      }
      return {'success': false, 'data': null};
    } catch (e) {
      return {'success': false, 'data': null};
    }
  }

  Future<Map<String, dynamic>> getMuscleGroupCoverage({int days = 7}) async {
    try {
      final response = await _api.get('/member/analytics/muscle-coverage?days=$days');
      if (response.statusCode == 200 && response.data is Map) {
        final raw = response.data as Map<String, dynamic>;
        final list = (raw['data'] as List<dynamic>? ?? [])
            .map((e) => MuscleGroupCoverage.fromJson(e as Map<String, dynamic>))
            .toList();
        return {'success': true, 'data': list};
      }
      return {'success': false, 'data': <MuscleGroupCoverage>[]};
    } catch (e) {
      return {'success': false, 'data': <MuscleGroupCoverage>[]};
    }
  }

  Future<Map<String, dynamic>> get1RMHistory(int wetId, {int days = 30}) async {
    try {
      final response =
          await _api.get('/member/exercises/$wetId/1rm-history?days=$days');
      if (response.statusCode == 200 && response.data is Map) {
        final raw = response.data as Map<String, dynamic>;
        final list = (raw['data'] as List<dynamic>? ?? [])
            .map((e) => OneRMPoint.fromJson(e as Map<String, dynamic>))
            .toList();
        return {'success': true, 'data': list};
      }
      return {'success': false, 'data': <OneRMPoint>[]};
    } catch (e) {
      return {'success': false, 'data': <OneRMPoint>[]};
    }
  }

  Future<Map<String, dynamic>> getProgressReport({int days = 30}) async {
    try {
      isLoading.value = true;
      final response =
          await _api.get('/member/analytics/progress?days=$days');
      if (response.statusCode == 200) {
        final report =
            ProgressReport.fromJson(response.data as Map<String, dynamic>);
        return {'success': true, 'data': report};
      }
      return {'success': false, 'message': 'โหลดรายงานความก้าวหน้าไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }
}

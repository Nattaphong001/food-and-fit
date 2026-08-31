import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import '../models/user_model.dart';
import '../models/body_stats_model.dart';
import 'api_client.dart';

class MemberService extends GetxService {
  static MemberService get to => Get.find();

  final ApiClient _api = ApiClient();
  final isLoading = false.obs;
  final Rx<User?> currentUser = Rx<User?>(null);

  Future<Map<String, dynamic>> getProfile() async {
    try {
      isLoading.value = true;
      final response = await _api.get('/member/profile');
      if (response.statusCode == 200) {
        final raw = response.data as Map<String, dynamic>;
        // backend ส่ง {"profile": {...}, "body_stats": {...}, "goals": {...}}
        final profileData = raw['profile'] as Map<String, dynamic>? ?? raw;
        currentUser.value = User.fromJson(profileData);
        return {
          'success': true,
          'data': currentUser.value,
          'body_stats': raw['body_stats'],
          'goals': raw['goals'],
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'โหลดโปรไฟล์ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  // ใช้ตอน Onboarding — ส่งข้อมูลร่างกายและเป้าหมายครั้งแรก
  Future<Map<String, dynamic>> setupProfile(Map<String, dynamic> data) async {
    try {
      isLoading.value = true;
      final response = await _api.post('/member/update-profile', data);
      if (response.statusCode == 200) {
        return {'success': true, 'message': response.data['message'] ?? 'บันทึกข้อมูลสำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? 'บันทึกข้อมูลไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    try {
      isLoading.value = true;
      final response = await _api.put('/member/profile', data);
      if (response.statusCode == 200) {
        await getProfile(); // refresh currentUser ทั่วทั้งแอพ
        return {'success': true, 'message': response.data['message'] ?? 'อัพเดทโปรไฟล์สำเร็จ'};
      }
      return {'success': false, 'message': response.data['error'] ?? response.data['message'] ?? 'อัพเดทโปรไฟล์ไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> updateBodyStats(Map<String, dynamic> data) async {
    try {
      isLoading.value = true;
      final response = await _api.put('/member/body-stats', data);
      if (response.statusCode == 200) {
        final raw = response.data;
        final statsData = raw['data'] ?? raw;
        final stats = statsData is Map<String, dynamic> ? BodyStats.fromJson(statsData) : null;
        return {'success': true, 'message': raw['message'] ?? 'อัพเดทข้อมูลร่างกายสำเร็จ', 'data': stats};
      }
      return {'success': false, 'message': response.data['error'] ?? 'อัพเดทข้อมูลร่างกายไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> getStatsHistory() async {
    try {
      isLoading.value = true;
      final response = await _api.get('/member/stats-history');
      if (response.statusCode == 200) {
        final raw = response.data;
        final list = (raw['data'] ?? raw) as List? ?? [];
        final stats = list.map((e) => BodyStats.fromJson(e as Map<String, dynamic>)).toList();
        return {'success': true, 'data': stats};
      }
      return {'success': false, 'message': 'โหลดประวัติไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> uploadProfileImage(String filePath) async {
    try {
      isLoading.value = true;
      final formData = dio.FormData.fromMap({
        'image': await dio.MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
        ),
      });
      final response = await _api.dio.post('/member/profile/image', data: formData);
      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>?;
        final picPath = data?['profile_pic'] ?? '';
        // อัปเดต currentUser.profilePicUrl ทันที
        if (currentUser.value != null && picPath.isNotEmpty) {
          await getProfile(); // refresh ทั่วแอพ
        }
        return {
          'success': true,
          'profile_pic': picPath,
          'message': response.data['message'] ?? 'อัปโหลดรูปสำเร็จ',
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'อัปโหลดรูปไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }
}

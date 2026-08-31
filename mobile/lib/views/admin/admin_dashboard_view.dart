// หน้า: Admin Dashboard (หน้าหลัก Admin)
// ทำหน้าที่: หน้า shell หลักฝั่ง Admin ครอบ Bottom Navigation สลับระหว่าง Dashboard ภาพรวม, รายงาน, และโปรไฟล์

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'food/manage_nutrition_categories_view.dart';
import 'food/manage_food_items_view.dart';
import 'plan/manage_system_workout_plans_view.dart';
import 'workout/manage_muscle_group_view.dart';
import 'workout/manage_weight_exercises_view.dart';
import 'workout/manage_exercise_muscles_view.dart';
import 'workout/manage_cardio_types_view.dart';
import 'workout/manage_cardio_activities_view.dart';
import 'admin_profile_view.dart';
import 'admin_report_view.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../services/auth_service.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  static const Color _primary = Color(0xFF1BB874);

  Widget _buildMenuItem(
    String title,
    IconData icon,
    Widget Function() builder, {
    Color iconBg   = const Color(0xFFE0F7EE),
    Color iconColor = const Color(0xFF1BB874),
  }) {
    return GestureDetector(
      onTap: () => Get.to(builder),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0xFF686868),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String title, List<Widget> menuItems) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFA0A1A5),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(3, (index) {
              if (index < menuItems.length) {
                return Expanded(child: menuItems[index]);
              }
              return const Expanded(child: SizedBox());
            }),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 160,
        95,
        16,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      items: [
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: const [
              Icon(Icons.person_outline, color: _primary, size: 20),
              SizedBox(width: 10),
              Text(
                'โปรไฟล์',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: const [
              Icon(Icons.logout, color: Colors.red, size: 20),
              SizedBox(width: 10),
              Text(
                'ล็อกเอ้าท์',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Color.fromRGBO(244, 67, 54, 1),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (result == 'profile') {
      Get.to(() => const AdminProfileView(
            name: "Admin",
            email: "admin@example.com",
            organization: "Admin Center",
          ));
    } else if (result == 'logout') {
      final confirm = await showAppConfirmDialog(
        context,
        icon: Icons.logout_rounded,
        title: 'ออกจากระบบ?',
        content: 'คุณต้องการออกจากระบบใช่หรือไม่?',
        confirmLabel: 'ออกจากระบบ',
        // ไม่ใช่ action ทำลายข้อมูล — แค่สลับโหมด/ออกจาก session ใช้ฟ้า (info) แทนแดง
        color: AppColors.alertInfo,
      );
      if (confirm) {
        Get.find<AuthService>().logout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1BB874), Color(0xFF159C60)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Data Management',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'จัดการฐานข้อมูลพื้นฐาน',
                                style: TextStyle(
                                  color: Color(0xFFE0F7EE),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showProfileMenu(context),
                          child: const Icon(
                            Icons.account_circle,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                children: [
                  // หมวดที่ 1: เวทเทรนนิ่ง — teal
                  _buildCategorySection('เวทเทรนนิ่ง', [
                    _buildMenuItem(
                      'กลุ่มกล้ามเนื้อ',
                      Icons.accessibility_new,
                      () => const ManageMuscleGroupView(),
                      iconBg:    const Color(0xFFCCEEEB),
                      iconColor: const Color(0xFF1A9A90),
                    ),
                    _buildMenuItem(
                      'ท่าฝึกเวท',
                      Icons.fitness_center,
                      () => const ManageWeightExercisesView(),
                      iconBg:    const Color(0xFFCCEEEB),
                      iconColor: const Color(0xFF1A9A90),
                    ),
                    _buildMenuItem(
                      'เชื่อมโยงท่าฝึกกับกล้ามเนื้อ',
                      Icons.link,
                      () => const ManageExerciseMusclesView(),
                      iconBg:    const Color(0xFFCCEEEB),
                      iconColor: const Color(0xFF1A9A90),
                    ),
                  ]),

                  // หมวดที่ 2: คาร์ดิโอ — lime green
                  _buildCategorySection('คาร์ดิโอ', [
                    _buildMenuItem(
                      'ประเภทคาร์ดิโอ',
                      Icons.directions_run,
                      () => const ManageCardioTypesView(),
                      iconBg:    const Color(0xFFE5F5CC),
                      iconColor: const Color(0xFF5EA61A),
                    ),
                    _buildMenuItem(
                      'กิจกรรมคาร์ดิโอ & METs',
                      Icons.bolt,
                      () => const ManageCardioActivitiesView(),
                      iconBg:    const Color(0xFFE5F5CC),
                      iconColor: const Color(0xFF5EA61A),
                    ),
                  ]),

                  // หมวดที่ 3: แผนการฝึก — forest green
                  _buildCategorySection('แผนการฝึก', [
                    _buildMenuItem(
                      'รายการแผน',
                      Icons.assignment_outlined,
                      () => const ManageSystemWorkoutPlansView(),
                      iconBg:    const Color(0xFFCEEDD8),
                      iconColor: const Color(0xFF1A7A4E),
                    ),
                  ]),

                  // หมวดที่ 4: โภชนาการ — primary green
                  _buildCategorySection('โภชนาการ', [
                    _buildMenuItem(
                      'ประเภทโภชนาการ',
                      Icons.inventory_2_outlined,
                      () => const ManageNutritionCategoriesView(),
                      iconBg:    const Color(0xFFD4F5E9),
                      iconColor: const Color(0xFF1BB874),
                    ),
                    _buildMenuItem(
                      'ฐานข้อมูลโภชนาการ',
                      Icons.fastfood,
                      () => const ManageFoodItemsView(),
                      iconBg:    const Color(0xFFD4F5E9),
                      iconColor: const Color(0xFF1BB874),
                    ),
                  ]),

                  // หมวดที่ 5: รายงาน — cyan-teal
                  _buildCategorySection('รายงาน', [
                    _buildMenuItem(
                      'รายงานข้อมูล',
                      Icons.insert_drive_file_outlined,
                      () => const AdminReportView(),
                      iconBg:    const Color(0xFFCCE8F2),
                      iconColor: const Color(0xFF1884A8),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
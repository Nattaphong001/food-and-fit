// [PAGE] ADMIN_SHELL : โครง Layout กลางฝั่ง Admin (เว็บ)
// [PAGE_PURPOSE] Sidebar เมนูซ้าย + พื้นที่เนื้อหาขวา ครอบทุกหน้าจัดการข้อมูล Admin
//                แทนที่ Bottom Navigation ของแอปมือถือ (admin_dashboard_view.dart) เพราะจอกว้าง
// [PAGE_ROUTE] /admin (myapp_admin, Flutter Web)
// [USES_FEATURES] AUTH, WORKOUT_PLAN, WEIGHT_TRAINING, CARDIO, FOOD_LOG, REPORT

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/theme/theme.dart';
import '../core/constants/layout_breakpoints.dart';
import '../core/widgets/app_confirm_dialog.dart';
import '../services/admin_auth_service.dart';
import 'login_view.dart';
import 'admin/admin_dashboard_view.dart';
import 'admin/admin_profile_view.dart';
import 'admin/admin_report_view.dart';
import 'admin/workout/manage_muscle_group_view.dart';
import 'admin/workout/manage_weight_exercises_view.dart';
import 'admin/workout/manage_exercise_muscles_view.dart';
import 'admin/workout/manage_cardio_types_view.dart';
import 'admin/workout/manage_cardio_activities_view.dart';
import 'admin/plan/manage_system_workout_plans_view.dart';
import 'admin/food/manage_nutrition_categories_view.dart';
import 'admin/food/manage_food_items_view.dart';
import 'admin/member/manage_members_view.dart';
import 'admin/system/manage_admins_view.dart';

class _MenuEntry {
  final String label;
  final IconData icon;
  final Widget Function() builder;
  // true เฉพาะหน้าที่ไม่มี AdminPageHeader ของตัวเอง (เช่นข้อมูลระบบ/รายงาน) — ต้องพึ่ง TopBar
  // แสดงชื่อหน้าแทน หน้าที่มี AdminPageHeader อยู่แล้วให้ false กันชื่อหน้าซ้ำ 2 ที่ (A3 ในบรีฟ UX)
  final bool showTopBarTitle;
  const _MenuEntry(
    this.label,
    this.icon,
    this.builder, {
    this.showTopBarTitle = false,
  });
}

class _MenuSection {
  final String title;
  final List<_MenuEntry> items;
  const _MenuSection(this.title, this.items);
}

// กลุ่มบนสุด (เช่น "จัดการข้อมูลพื้นฐาน", "รายงาน") — มีได้ทั้ง item ตรงใต้กลุ่มเลย (items)
// และ sub-section ซ้อนอีกชั้น (subSections) ในกลุ่มเดียวกัน
class _MenuGroup {
  final String title;
  final List<_MenuEntry> items;
  final List<_MenuSection> subSections;
  const _MenuGroup(
    this.title, {
    this.items = const [],
    this.subSections = const [],
  });
}

class AdminShellView extends StatefulWidget {
  const AdminShellView({super.key});

  @override
  State<AdminShellView> createState() => _AdminShellViewState();
}

class _AdminShellViewState extends State<AdminShellView> {
  // index 0 = ภาพรวม (dashboard home) เสมอ ต่อจากนั้นคือ flatten รายการเมนูตามลำดับ group
  int _selectedIndex = 0;

  static final List<_MenuGroup> _groups = [
    _MenuGroup(
      'จัดการข้อมูลพื้นฐาน',
      subSections: [
        _MenuSection('เวทเทรนนิ่ง', [
          _MenuEntry(
            'กลุ่มกล้ามเนื้อ',
            Icons.accessibility_new,
            () => const ManageMuscleGroupView(),
          ),
          _MenuEntry(
            'ท่าฝึกเวทเทรนนิ่ง',
            Icons.fitness_center,
            () => const ManageWeightExercisesView(),
          ),
          _MenuEntry(
            'เชื่อมโยงท่าฝึกกับกล้ามเนื้อ',
            Icons.link,
            () => const ManageExerciseMusclesView(),
          ),
        ]),
        _MenuSection('คาร์ดิโอ', [
          _MenuEntry(
            'ประเภทคาร์ดิโอ',
            Icons.directions_run,
            () => const ManageCardioTypesView(),
          ),
          _MenuEntry(
            'กิจกรรมคาร์ดิโอ',
            Icons.bolt,
            () => const ManageCardioActivitiesView(),
          ),
        ]),
        _MenuSection('แผนการฝึก', [
          _MenuEntry(
            'รายการแผนฝึก',
            Icons.assignment_outlined,
            () => const ManageSystemWorkoutPlansView(),
          ),
        ]),
        _MenuSection('โภชนาการ', [
          _MenuEntry(
            'ประเภทโภชนาการ',
            Icons.inventory_2_outlined,
            () => const ManageNutritionCategoriesView(),
          ),
          _MenuEntry(
            'โภชนาการ',
            Icons.fastfood,
            () => const ManageFoodItemsView(),
          ),
        ]),
        _MenuSection('ผู้ใช้งาน', [
          _MenuEntry(
            'รายชื่อสมาชิก',
            Icons.people_outline,
            () => const ManageMembersView(),
          ),
        ]),
        _MenuSection('ผู้ดูแลระบบ', [
          _MenuEntry(
            'รายชื่อผู้ดูแลระบบ',
            Icons.admin_panel_settings_outlined,
            () => const ManageAdminsView(),
          ),
        ]),
      ],
    ),
    _MenuGroup(
      'รายงาน',
      items: [
        _MenuEntry(
          'รายงานระบบ',
          Icons.assessment_outlined,
          () => const AdminReportView(),
          showTopBarTitle: true,
        ),
      ],
    ),
  ];

  // flatten (group -> items ตรง + sub-section -> items) -> ลำดับ index ต่อจาก 0 (ภาพรวม)
  late final List<_MenuEntry> _flatItems = _groups
      .expand((g) => [...g.items, ...g.subSections.expand((s) => s.items)])
      .toList();

  // "ข้อมูลระบบ" ไม่ได้อยู่ใน sidebar แล้ว (เข้าถึงผ่านคลิก avatar/ชื่อที่ topbar เท่านั้น) —
  // จองสล็อต index ท้ายสุดถัดจาก _flatItems ไว้ให้หน้านี้โดยเฉพาะ ไม่ปนกับลำดับเมนูจริง
  static const _profileEntry = _MenuEntry(
    'ข้อมูลระบบ',
    Icons.info_outline,
    _buildProfilePage,
    showTopBarTitle: true,
  );
  static Widget _buildProfilePage() => const AdminProfileView();
  late final int _profileIndex = _flatItems.length + 1;

  // index ของ "รายชื่อสมาชิก" — ใช้พาไปจากลิงก์ "ดูทั้งหมด" ในตารางสมาชิกล่าสุดของ Dashboard
  late final int _membersIndex =
      _flatItems.indexWhere((e) => e.label == 'รายชื่อสมาชิก') + 1;

  // index 0 (ภาพรวม) = AdminDashboardView เบาๆ ไม่มีตัวกรอง ส่วนรายงานละเอียด (มี tab
  // สัปดาห์/เดือน/กำหนดเอง) แยกเป็นเมนู "รายงาน > รายงานระบบ" ต่างหาก
  Widget _buildPage(int index) {
    if (index == 0) {
      return AdminDashboardView(
        onViewAllMembers: () => setState(() => _selectedIndex = _membersIndex),
      );
    }
    if (index == _profileIndex) return _profileEntry.builder();
    return _flatItems[index - 1].builder();
  }

  // cache widget ที่เคย build แล้ว กัน initState รันซ้ำทุกครั้งที่คลิกเปลี่ยนเมนู (เหมือน IndexedStack เดิม)
  // ต่างจากเดิมตรงที่ build "เฉพาะหน้าที่เคยเปิดจริง" ไม่ build ทุกหน้าตั้งแต่แรก
  // (เดิม build ทุกหน้าพร้อมกันตอนเปิด shell ครั้งแรก ทำให้ initState ของทุกหน้ายิง API พร้อมกันหมด
  // แย่ง connection กับ 3 requests ของหน้ารายงาน ทำให้หน้าแรกโหลดช้า)
  // +2 = index 0 (ภาพรวม) ... _flatItems.length (เมนูจริง) แล้วอีก 1 สล็อตท้ายสุดให้ _profileIndex
  late final List<Widget?> _pageCache = List<Widget?>.filled(
    _flatItems.length + 2,
    null,
    growable: false,
  );

  Widget _pageAt(int index) => _pageCache[index] ??= _buildPage(index);

  // หน้าที่เลือกอยู่: build จริง (หรือดึงจาก cache) ส่วนหน้าที่ยังไม่เคยเปิด: placeholder เฉยๆ ยังไม่ build
  List<Widget> _stackChildren() => List.generate(
    _pageCache.length,
    (i) => i == _selectedIndex
        ? _pageAt(i)
        : (_pageCache[i] ?? const SizedBox.shrink()),
  );

  String _currentTitle() {
    if (_selectedIndex == 0) return 'ภาพรวม';
    if (_selectedIndex == _profileIndex) return _profileEntry.label;
    return _flatItems[_selectedIndex - 1].label;
  }

  // index 0 (ภาพรวม) และหน้าโปรไฟล์ ไม่มี AdminPageHeader ของตัวเอง ต้องพึ่ง TopBar เสมอ —
  // หน้าอื่นดูจาก showTopBarTitle ของ _MenuEntry (false = มี AdminPageHeader ของตัวเองอยู่แล้ว กันชื่อซ้ำ)
  bool get _shouldShowTopBarTitle =>
      _selectedIndex == 0 ||
      _selectedIndex == _profileIndex ||
      _flatItems[_selectedIndex - 1].showTopBarTitle;

  void _openProfile() => setState(() => _selectedIndex = _profileIndex);

  Future<void> _confirmLogout() async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'ออกจากระบบ?',
      content: 'คุณต้องการออกจากระบบใช่หรือไม่?',
      confirmLabel: 'ออกจากระบบ',
      color: AppColors.infoText,
    );
    if (confirm) {
      await AdminAuthService.to.logout();
      if (mounted) Get.offAll(() => const LoginView());
    }
  }

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tier = AppBreakpoints.of(constraints.maxWidth);

        final content = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                title: _shouldShowTopBarTitle ? _currentTitle() : null,
                onLogout: _confirmLogout,
                onProfileTap: _openProfile,
                onMenuTap: tier == LayoutTier.compact
                    ? () => _scaffoldKey.currentState?.openDrawer()
                    : null,
              ),
              Expanded(
                child: Container(
                  color: AppColors.background,
                  child: tier == LayoutTier.wide
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppBreakpoints.maxContentWidth,
                            ),
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: _stackChildren(),
                            ),
                          ),
                        )
                      : IndexedStack(
                          index: _selectedIndex,
                          children: _stackChildren(),
                        ),
                ),
              ),
            ],
          ),
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: tier == LayoutTier.compact
              ? Drawer(
                  width: 260,
                  child: _Sidebar(
                    groups: _groups,
                    selectedIndex: _selectedIndex,
                    onSelect: (i) {
                      setState(() => _selectedIndex = i);
                      Navigator.of(context).pop();
                    },
                  ),
                )
              : null,
          body: Row(
            children: [
              if (tier != LayoutTier.compact)
                _Sidebar(
                  groups: _groups,
                  selectedIndex: _selectedIndex,
                  onSelect: (i) => setState(() => _selectedIndex = i),
                  iconOnly: tier == LayoutTier.medium,
                ),
              content,
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_MenuGroup> groups;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool iconOnly;

  const _Sidebar({
    required this.groups,
    required this.selectedIndex,
    required this.onSelect,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    var runningIndex = 0;
    return Container(
      width: iconOnly ? 72 : 260,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: iconOnly
                ? const EdgeInsets.symmetric(vertical: 20)
                : const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: iconOnly
                ? const Center(
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.admin_panel_settings_rounded,
                        color: AppColors.primary,
                        size: 32,
                      ),
                      SizedBox(height: 10),
                      Text('Data Management', style: AppTextStyles.pageTitle),
                      SizedBox(height: 2),
                      Text(
                        'จัดการฐานข้อมูลพื้นฐาน',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _NavTile(
                    icon: Icons.dashboard_outlined,
                    label: 'ภาพรวม',
                    selected: selectedIndex == 0,
                    onTap: () => onSelect(0),
                    iconOnly: iconOnly,
                  ),
                  for (final group in groups) ...[
                    if (!iconOnly)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                        child: Text(
                          group.title,
                          style: AppTextStyles.sidebarSection,
                        ),
                      )
                    else
                      const SizedBox(height: 10),
                    for (final item in group.items) ...[
                      Builder(
                        builder: (_) {
                          runningIndex++;
                          final idx = runningIndex;
                          return _NavTile(
                            icon: item.icon,
                            label: item.label,
                            selected: selectedIndex == idx,
                            onTap: () => onSelect(idx),
                            iconOnly: iconOnly,
                            indentLevel: 1,
                          );
                        },
                      ),
                    ],
                    for (final sub in group.subSections) ...[
                      if (!iconOnly)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 12, 20, 6),
                          child: Text(
                            sub.title,
                            style: AppTextStyles.sidebarSection,
                          ),
                        )
                      else
                        const SizedBox(height: 6),
                      for (final item in sub.items) ...[
                        Builder(
                          builder: (_) {
                            runningIndex++;
                            final idx = runningIndex;
                            return _NavTile(
                              icon: item.icon,
                              label: item.label,
                              selected: selectedIndex == idx,
                              onTap: () => onSelect(idx),
                              iconOnly: iconOnly,
                              indentLevel: 2,
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;
  final int indentLevel;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconOnly = false,
    this.indentLevel = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryDark : AppColors.textSecondary;
    final labelStyle = selected
        ? AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.primaryDark,
          )
        : AppTextStyles.body.copyWith(color: AppColors.textSecondary);
    // เมนูย่อยเยื้องเข้า 8px ต่อชั้น (DESIGN_SYSTEM.md 12.1) — งดเยื้องตอน iconOnly เพราะพื้นที่แคบ
    final leftInset = iconOnly ? 12.0 : 12.0 + indentLevel * 8.0;
    final tile = Padding(
      padding: EdgeInsets.only(left: leftInset, right: 12, top: 2, bottom: 2),
      child: Stack(
        children: [
          Material(
            color: selected ? AppColors.primarySurface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: iconOnly ? 0 : 12,
                  vertical: 11,
                ),
                child: iconOnly
                    ? Icon(icon, size: 20, color: color)
                    : Row(
                        children: [
                          Icon(icon, size: 20, color: color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: labelStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 4,
              bottom: 4,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );

    return iconOnly ? Tooltip(message: label, child: tile) : tile;
  }
}

class _TopBar extends StatelessWidget {
  final String? title;
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onMenuTap;

  const _TopBar({
    required this.title,
    required this.onLogout,
    required this.onProfileTap,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            IconButton(
              tooltip: 'เปิดเมนู',
              icon: const Icon(Icons.menu, color: AppColors.textPrimary),
              onPressed: onMenuTap,
            ),
            const SizedBox(width: 8),
          ],
          if (title != null) Text(title!, style: AppTextStyles.pageTitle),
          const Spacer(),
          Obx(
            () => Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onProfileTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AdminAuthService.to.adminName.value.isNotEmpty
                              ? AdminAuthService.to.adminName.value
                              : 'Admin',
                          style: AppTextStyles.tableHeader.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'ออกจากระบบ',
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

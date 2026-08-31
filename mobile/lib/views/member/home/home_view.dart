// หน้า: Home (Bottom Navigation Shell)
// ทำหน้าที่: หน้า shell หลักของสมาชิก ครอบ Bottom Navigation Bar และสลับระหว่าง Dashboard, โภชนาการ, ออกกำลังกาย

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../models/user_model.dart';
import '../../../models/body_stats_model.dart';
import '../../../services/api_client.dart';
import '../../../services/member_service.dart';
import '../../../services/notification_service.dart';
import '../../../core/utils/health_calculations.dart' as calc;
import 'profile_edit_view.dart';
import 'profile_edit_body_view.dart';
import 'notifications_view.dart';

class HomeView extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  // bump เมื่อแก้ข้อมูลร่างกาย/เป้าหมายสำเร็จ ให้แท็บ Nutrition/Dashboard รู้ว่าต้องโหลด
  // target ใหม่ (เดิมไม่มีใครแจ้ง ทำให้แท็บอื่นแสดงเป้าหมายค้างจนกว่าจะ pull-to-refresh เอง)
  final ValueNotifier<int>? profileRefreshNotifier;
  const HomeView({super.key, this.refreshNotifier, this.profileRefreshNotifier});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  User? _user;
  BodyStats? _stats;
  int _target = 3;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final result = await MemberService.to.getProfile();
      if (!mounted) return;
      setState(() {
        if (result['success'] == true) {
          _user = result['data'] as User?;
          final rawStats = result['body_stats'] as Map<String, dynamic>?;
          final rawGoals = result['goals'] as Map<String, dynamic>?;
          if (rawStats != null) {
            _stats = BodyStats.fromJson({...rawStats, ...?rawGoals});
            _target = int.tryParse(rawStats['target']?.toString() ?? '') ?? 3;
          }
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Computed ────────────────────────────────────────────────────────────────
  String get _userName => _user?.fullName.split(' ').first ?? 'ผู้ใช้';

  String get _genderDisplay {
    final g = _user?.gender ?? '';
    if (g == 'male' || g == '1') return 'ชาย';
    if (g == 'female' || g == '2') return 'หญิง';
    return g.isEmpty ? '-' : g;
  }

  int get _age {
    if (_user == null) return 0;
    final now = DateTime.now();
    final b = _user!.birthDate;
    int age = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) age--;
    return age;
  }

  double get _bmi {
    if (_stats == null) return 0;
    final api = _stats!.bmi;
    if (api >= 10 && api <= 70) return api;
    final h = _stats!.height / 100;
    return h > 0 ? _stats!.weight / (h * h) : 0;
  }

  String get _bmiLabel => calc.bmiLabel(_bmi);

  Color get _bmiColor {
    if (_bmi < 18.5) return const Color(0xFFAB7FE8);
    if (_bmi < 23) return const Color(0xFF3CC446);
    if (_bmi < 25) return const Color(0xFFE67A40);
    return const Color(0xFFDE3E3E);
  }

  double get _bmiProgress => calc.bmiProgress(_bmi);

  double get _bmr {
    if (_stats != null && _stats!.bmr > 0) return _stats!.bmr;
    if (_stats == null || _user == null || _age == 0) return 0;
    final g = _user!.gender;
    return calc.calcBmr(
      weightKg: _stats!.weight,
      heightCm: _stats!.height,
      age: _age.toDouble(),
      isMale: g == 'male' || g == '1',
    );
  }

  double get _tdee {
    if (_stats != null && _stats!.tdee > 0) return _stats!.tdee;
    return calc.calcTdee(bmr: _bmr, activityLevel: _stats?.activityLevel ?? 0);
  }

  String get _targetLabel {
    if (_target == 1) return 'ลดน้ำหนัก';
    if (_target == 2) return 'เพิ่มน้ำหนัก';
    return 'รักษาน้ำหนัก';
  }

  double get _calorieGoal {
    if ((_stats?.targetCal ?? 0) > 0) return _stats!.targetCal;
    return calc.calcTargetCalories(tdee: _tdee, bmr: _bmr, target: _target);
  }

  String _fmtKcal(double v) => v > 0
      ? v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')
      : '-';

  void _goToProfileEdit() {
    final user = _user ?? MemberService.to.currentUser.value;
    if (user == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditView(user: user)))
        .then((_) => _loadData());
  }

  void _goToBodyEdit() {
    Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(builder: (_) => ProfileEditBodyView(
          currentStats: _stats, user: _user, currentTarget: _target)),
    ).then((data) {
      if (data != null) {
        setState(() {
          _stats = data['stats'] as BodyStats;
          _target = data['target'] as int? ?? _target;
        });
        widget.profileRefreshNotifier?.value++;
      }
      _loadData();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }
    return Scaffold(
      // โปร่งใส — ให้พื้นหลังร่วมของ MainShell (รวม glow ท้ายจอ) โชว์ผ่านตลอด ไม่ถูกทับด้วยพื้น
      // ทึบของหน้านี้เอง ไม่งั้น BackdropFilter ของ navbar จะเห็นแต่สีพื้นเรียบๆ เหมือนทึบตลอด
      backgroundColor: Colors.transparent,
      // bottom: false — extendBody อัด MediaQuery.padding.bottom เท่าความสูง navbar มาให้ SafeArea
      // กิน ถ้าไม่ปิด content จะหดขึ้นไปหยุดเหนือ navbar เสมอ (extendBody เลยไม่มีผลอะไรเลย)
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          onRefresh: () async {
            ApiClient.clearCache();
            await _loadData();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildBodyInfoSection(),
                _buildBmiCard(),
                const SizedBox(height: 16),
                _buildBmrTdeeRow(),
                const SizedBox(height: 16),
                _buildCalorieGoalCard(),
                const SizedBox(height: 104), // เผื่อพ้น navbar ลอย (barHeight 64 + ระยะ 40)
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 1. Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Obx(() {
            final liveUser = MemberService.to.currentUser.value;
            final name = liveUser?.fullName.isNotEmpty == true ? liveUser!.fullName : (_userName);
            final pic = liveUser?.profilePic;
            final picUrl = (pic != null && pic.isNotEmpty) ? ApiClient.prefixPath(pic) : null;
            return GestureDetector(
              onTap: _goToProfileEdit,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.15),
                    child: picUrl != null
                        ? ClipOval(
                            child: cachedImage(picUrl, width: 52, height: 52, fit: BoxFit.cover),
                          )
                        : Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                          ),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.background, width: 1.5),
                      ),
                      child: const Icon(Icons.edit_rounded, size: 9, color: Colors.black),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() {
              final liveUser = MemberService.to.currentUser.value;
              final name = liveUser?.fullName ?? _user?.fullName ?? 'ผู้ใช้';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ข้อมูลผู้ใช้งาน',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                  Text(name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              );
            }),
          ),
          Obx(() {
            final count = NotificationService.to.unreadCount.value;
            return GestureDetector(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsView()));
                NotificationService.to.refreshCount();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: const Icon(Icons.notifications_none_rounded, color: AppColors.textDark, size: 22),
                  ),
                  if (count > 0)
                    Positioned(
                      top: -2, right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.alertError,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 2. Body Info 4 cards ────────────────────────────────────────────────────
  Widget _buildBodyInfoSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ข้อมูลร่างกาย',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              GestureDetector(
                onTap: _goToBodyEdit,
                child: Row(children: const [
                  Icon(Icons.edit_rounded, size: 13, color: AppColors.primaryGreen),
                  SizedBox(width: 4),
                  Text('แก้ไข', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _buildInfoCard(
              label: 'เพศ', value: _genderDisplay, unit: '',
              icon: Icons.transgender_rounded,
              iconBg: const Color(0xFFD4F5E9), iconColor: const Color(0xFF2BB673),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildInfoCard(
              label: 'ส่วนสูง',
              value: _stats != null ? _stats!.height.toStringAsFixed(0) : '-',
              unit: 'ซม.',
              icon: Icons.height_rounded,
              iconBg: const Color(0xFFFFF3E0), iconColor: const Color(0xFFE69A3A),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildInfoCard(
              label: 'อายุ', value: _age > 0 ? '$_age' : '-', unit: 'ปี',
              icon: Icons.cake_rounded,
              iconBg: const Color(0xFFE8EEFF), iconColor: const Color(0xFF5B72E8),
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildInfoCard(
              label: 'น้ำหนัก',
              value: _stats != null ? _stats!.weight.toStringAsFixed(1) : '-',
              unit: 'กก.',
              icon: Icons.monitor_weight_outlined,
              iconBg: const Color(0xFFF3E8FF), iconColor: const Color(0xFFAA5FE8),
            )),
          ]),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Text(unit, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. BMI Card ─────────────────────────────────────────────────────────────
  Widget _buildBmiCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BMI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const Text('ดัชนีมวลกาย', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _bmiColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _bmiColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _bmi > 0 ? _bmi.toStringAsFixed(2) : '-',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _bmiColor),
                    ),
                    const SizedBox(width: 6),
                    Text(_bmiLabel,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _bmiColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Gradient bar + indicator
          LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final frac = _bmiProgress;
            final pos = (frac * w - 13).clamp(0.0, w - 26.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Row(children: [
                    Expanded(child: Container(height: 14, color: const Color(0xFFAB7FE8))),
                    const SizedBox(width: 2),
                    Expanded(child: Container(height: 14, color: const Color(0xFF3CC446))),
                    const SizedBox(width: 2),
                    Expanded(child: Container(height: 14, color: const Color(0xFFE67A40))),
                    const SizedBox(width: 2),
                    Expanded(child: Container(height: 14, color: const Color(0xFFDE3E3E))),
                  ]),
                ),
                if (frac >= 0)
                  Positioned(
                    left: pos, top: -7,
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _bmiColor, width: 3),
                        boxShadow: [BoxShadow(color: _bmiColor.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _BmiLegend(color: Color(0xFFAB7FE8), label: 'ผอม'),
              _BmiLegend(color: Color(0xFF3CC446), label: 'ปกติ'),
              _BmiLegend(color: Color(0xFFE67A40), label: 'น้ำหนักเกิน'),
              _BmiLegend(color: Color(0xFFDE3E3E), label: 'โรคอ้วน'),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. BMR / TDEE ───────────────────────────────────────────────────────────
  Widget _buildBmrTdeeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildEnergyCard(
            title: 'BMR',
            subtitle: 'อัตราการเผาผลาญพื้นฐาน',
            value: _fmtKcal(_bmr),
            icon: Icons.self_improvement_rounded,
            iconColor: const Color(0xFF29B6F6),
            iconBg: const Color(0xFFE1F5FE),
          )),
          const SizedBox(width: 12),
          Expanded(child: _buildEnergyCard(
            title: 'TDEE',
            subtitle: 'พลังงานที่ใช้ทั้งวัน',
            value: _fmtKcal(_tdee),
            icon: Icons.bolt_rounded,
            iconColor: const Color(0xFFF85B07),
            iconBg: const Color(0xFFFFEDD6),
          )),
        ],
      ),
    );
  }

  Widget _buildEnergyCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(width: 4),
              const Text('kcal', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // ── 5. Calorie Goal ─────────────────────────────────────────────────────────
  Widget _buildCalorieGoalCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('แคลอรี่ที่เหมาะสมต่อวัน',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(height: 4),
                Row(children: [
                  const Text('เป้าหมาย: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  Text(_targetLabel,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                ]),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_fmtKcal(_calorieGoal),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                const SizedBox(width: 4),
                const Text('kcal', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── BMI Legend chip ──────────────────────────────────────────────────────────
class _BmiLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _BmiLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textBody)),
    ]);
  }
}

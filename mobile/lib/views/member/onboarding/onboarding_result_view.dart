// หน้า: Onboarding Result
// ทำหน้าที่: แสดงสรุปข้อมูลโปรไฟล์และเป้าหมายที่ตั้งไว้หลังการ setup ครั้งแรก ก่อนเข้าใช้งานแอพ

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../models/body_stats_model.dart';
import '../../../services/member_service.dart';
import '../../../services/local_notification_service.dart';
import '../../../core/utils/health_calculations.dart' as calc;

class OnboardingResultView extends StatefulWidget {
  const OnboardingResultView({super.key});

  @override
  State<OnboardingResultView> createState() => _OnboardingResultViewState();
}

class _OnboardingResultViewState extends State<OnboardingResultView> {
  BodyStats? _stats;
  int _target = 1;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final result = await MemberService.to.getProfile();
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) {
        final rawStats = result['body_stats'] as Map<String, dynamic>?;
        final rawGoals = result['goals'] as Map<String, dynamic>?;
        if (rawStats != null) {
          _stats = BodyStats.fromJson({...rawStats, ...?rawGoals});
        }
        _target = (rawStats?['target'] as int?) ?? 1;
      }
      _isLoading = false;
    });
  }

  double get _bmi => _stats?.bmi ?? 0;

  double get _bmiProgress => calc.bmiProgress(_bmi);

  Color get _bmiColor {
    if (_bmi < 18.5) return const Color(0xFFAB7FE8);
    if (_bmi < 23.0) return const Color(0xFF3CC446);
    if (_bmi < 25.0) return const Color(0xFFE67A40);
    return const Color(0xFFDE3E3E);
  }

  String get _bmiLabel => calc.bmiLabel(_bmi);

  double get _targetCalories {
    if ((_stats?.targetCal ?? 0) > 0) return _stats!.targetCal;
    final tdee = _stats?.tdee ?? 0;
    final bmr = _stats?.bmr ?? 0;
    return calc.calcTargetCalories(tdee: tdee, bmr: bmr, target: _target);
  }

  String get _targetLabel {
    if (_target == 1) return 'ลดน้ำหนัก';
    if (_target == 2) return 'เพิ่มน้ำหนัก';
    return 'รักษาน้ำหนัก';
  }

  String _fmtKcal(double v) => v > 0
      ? v.round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')
      : '-';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildBodyInfoRow(),
                          const SizedBox(height: 16),
                          _buildBmiCard(),
                          const SizedBox(height: 16),
                          _buildBmrTdeeRow(),
                          const SizedBox(height: 16),
                          _buildCalorieGoalCard(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomButton(),
                ],
              ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackButton(onTap: () => Get.back()),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ขั้นตอนที่ 3 จาก 3',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('ผลการวิเคราะห์ของคุณ',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textDark, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        const Text('ระบบได้คำนวณข้อมูลสุขภาพเบื้องต้นให้แล้ว',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
      ],
    );
  }

  // ── Body Info Row (weight + height) ─────────────────────────────────────────
  Widget _buildBodyInfoRow() {
    return Row(
      children: [
        Expanded(child: _buildInfoCard(
          label: 'น้ำหนัก',
          value: _stats != null ? _stats!.weight.toStringAsFixed(1) : '-',
          unit: 'กก.',
          icon: Icons.monitor_weight_outlined,
          iconBg: const Color(0xFFF3E8FF),
          iconColor: const Color(0xFFAA5FE8),
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildInfoCard(
          label: 'ส่วนสูง',
          value: _stats != null ? _stats!.height.toStringAsFixed(0) : '-',
          unit: 'ซม.',
          icon: Icons.height_rounded,
          iconBg: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFE69A3A),
        )),
      ],
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
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  const SizedBox(width: 3),
                  Text(unit, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BMI Card (identical to home_view) ───────────────────────────────────────
  Widget _buildBmiCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BMI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  Text('ดัชนีมวลกาย', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
                    Text(_bmiLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _bmiColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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

  // ── BMR / TDEE (identical layout to home_view) ───────────────────────────────
  Widget _buildBmrTdeeRow() {
    return Row(
      children: [
        Expanded(child: _buildEnergyCard(
          title: 'BMR',
          subtitle: 'อัตราการเผาผลาญพื้นฐาน',
          value: _fmtKcal(_stats?.bmr ?? 0),
          icon: Icons.self_improvement_rounded,
          iconColor: const Color(0xFF29B6F6),
          iconBg: const Color(0xFFE1F5FE),
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildEnergyCard(
          title: 'TDEE',
          subtitle: 'พลังงานที่ใช้ทั้งวัน',
          value: _fmtKcal(_stats?.tdee ?? 0),
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFFF85B07),
          iconBg: const Color(0xFFFFEDD6),
        )),
      ],
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

  // ── Calorie Goal (identical to home_view) ────────────────────────────────────
  Widget _buildCalorieGoalCard() {
    return Container(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                    Text(_fmtKcal(_targetCalories),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                    const SizedBox(width: 4),
                    const Text('kcal', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom Button ────────────────────────────────────────────────────────────
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: () {
            final name = MemberService.to.currentUser.value?.fullName.split(' ').first ?? '';
            LocalNotificationService.to.showWelcome(name);
            Get.offAllNamed('/home');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('เริ่มกันเลย', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

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

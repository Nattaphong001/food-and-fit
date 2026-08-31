// หน้า: Edit Body Stats
// ทำหน้าที่: หน้าบันทึกข้อมูลร่างกาย อัปเดตน้ำหนัก ส่วนสูง และเปอร์เซ็นต์ไขมันเพื่อติดตามสถิติร่างกาย

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../models/body_stats_model.dart';
import '../../../models/user_model.dart';
import '../../../services/member_service.dart';

class ProfileEditBodyView extends StatefulWidget {
  final BodyStats? currentStats;
  final User? user;
  final int currentTarget;
  const ProfileEditBodyView({super.key, this.currentStats, this.user, this.currentTarget = 3});

  @override
  State<ProfileEditBodyView> createState() => _ProfileEditBodyViewState();
}

class _ProfileEditBodyViewState extends State<ProfileEditBodyView> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  bool _isLoading = false;
  String _activityLevel = 'ปานกลาง 3-5 วัน/สัปดาห์';
  String _fitnessGoal = 'ลดน้ำหนัก';
  late DateTime _birthDate;
  late String _gender;
  String? _heightError;
  String? _weightError;

  static const int _minAge = 13; // อายุขั้นต่ำ ต้องตรงกับ backend
  // ต้องตรงกับ backend helpers.ValidateHeight/ValidateWeight (validation.go)
  static const double _minHeight = 50, _maxHeight = 250;
  static const double _minWeight = 20, _maxWeight = 300;

  String? _validateHeight(double? h) {
    if (h == null) return 'กรุณากรอกส่วนสูง';
    if (h < _minHeight) return 'ส่วนสูงต้องไม่น้อยกว่า $_minHeight ซม.';
    if (h > _maxHeight) return 'ส่วนสูงไม่ถูกต้อง (สูงสุด $_maxHeight ซม.)';
    return null;
  }

  String? _validateWeight(double? w) {
    if (w == null) return 'กรุณากรอกน้ำหนัก';
    if (w < _minWeight) return 'น้ำหนักต้องไม่น้อยกว่า $_minWeight กก.';
    if (w > _maxWeight) return 'น้ำหนักไม่ถูกต้อง (สูงสุด $_maxWeight กก.)';
    return null;
  }

  // ── mappings ────────────────────────────────────────────────────────────────
  int _mapGender(String g) => g == 'ชาย' ? 1 : 2;

  String _initGender() {
    final g = widget.user?.gender ?? '';
    if (g == 'male' || g == '1') return 'ชาย';
    if (g == 'female' || g == '2') return 'หญิง';
    return 'ชาย';
  }

  // D1: DB เก็บ mbs_activity_level เป็น DECIMAL(3,2) ปัดเศษ (1.375→1.38, 1.725→1.73)
  // ค่าที่ backend ส่งกลับมาจึงไม่ตรงค่าคงที่สูตรเป๊ะ — ใช้จุดกึ่งกลางระหว่างค่าที่ถูกปัดแล้ว
  // เทียบแทน (ไม่ใช่ค่าคงที่ดิบ) เพื่อ map กลับเป็นระดับที่ถูกต้อง ไม่งั้นจะเลื่อนระดับผิดหมวด
  String _reverseActivity(double level) {
    if (level <= 1.29)  return 'ไม่ออกกำลังกาย/นั่งโต๊ะ';
    if (level <= 1.465) return 'เบา 1-3 วัน/สัปดาห์';
    if (level <= 1.64)  return 'ปานกลาง 3-5 วัน/สัปดาห์';
    if (level <= 1.815) return 'หนัก 6-7 วัน/สัปดาห์';
    return 'หนักมาก/นักกีฬา';
  }

  String _reverseGoal(int t) {
    if (t == 1) return 'ลดน้ำหนัก';
    if (t == 2) return 'เพิ่มน้ำหนัก';
    return 'รักษาน้ำหนัก';
  }

  double _mapActivity(String a) {
    switch (a) {
      case 'ไม่ออกกำลังกาย/นั่งโต๊ะ':   return 1.2;
      case 'เบา 1-3 วัน/สัปดาห์':       return 1.375;
      case 'ปานกลาง 3-5 วัน/สัปดาห์':  return 1.55;
      case 'หนัก 6-7 วัน/สัปดาห์':     return 1.725;
      case 'หนักมาก/นักกีฬา':           return 1.9;
      default:                           return 1.55;
    }
  }

  int _mapGoal(String g) {
    switch (g) {
      case 'ลดน้ำหนัก':   return 1;
      case 'เพิ่มน้ำหนัก': return 2;
      case 'รักษาน้ำหนัก': return 3;
      default:             return 3;
    }
  }

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController(
      text: widget.currentStats?.height.toStringAsFixed(0) ?? '172',
    );
    _weightController = TextEditingController(
      text: widget.currentStats?.weight.toStringAsFixed(1) ?? '70.0',
    );
    final al = widget.currentStats?.activityLevel ?? 0;
    if (al > 0) _activityLevel = _reverseActivity(al);
    _fitnessGoal = _reverseGoal(widget.currentTarget);
    _birthDate = widget.user?.birthDate ?? DateTime(2000, 1, 1);
    _gender = _initGender();
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showAppCalendarPicker(
      context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - _minAge, now.month, now.day),
      title: 'เลือกวันเกิด',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _saveBodyStats() async {
    final h = double.tryParse(_heightController.text);
    final w = double.tryParse(_weightController.text);
    final heightErr = _validateHeight(h);
    final weightErr = _validateWeight(w);
    if (heightErr != null || weightErr != null) {
      setState(() {
        _heightError = heightErr;
        _weightError = weightErr;
      });
      return;
    }
    setState(() {
      _heightError = null;
      _weightError = null;
      _isLoading = true;
    });

    final profileResult = await MemberService.to.updateProfile({
      'full_name': widget.user?.fullName ?? '',
      'gender': _mapGender(_gender),
      'birth_date':
          '${_birthDate.year}-${_birthDate.month.toString().padLeft(2, '0')}-${_birthDate.day.toString().padLeft(2, '0')}',
    });
    if (profileResult['success'] != true) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppAlert(context, profileResult['message'] ?? 'อัปเดตข้อมูลส่วนตัวไม่สำเร็จ', type: AppAlertType.error);
      return;
    }

    final result = await MemberService.to.updateBodyStats({
      'height': h,
      'weight': w,
      'activity_level': _mapActivity(_activityLevel),
      'target': _mapGoal(_fitnessGoal),
    });
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] != true) {
      showAppAlert(context, result['message'] ?? '', type: AppAlertType.error);
      return;
    }
    final apiStats = result['data'] as BodyStats?;
    final fullStats = BodyStats(
      weight: w!,
      height: h!,
      bmi: apiStats?.bmi ?? 0,
      bmr: apiStats?.bmr ?? 0,
      tdee: apiStats?.tdee ?? 0,
      targetCal: apiStats?.targetCal ?? 0,
      activityLevel: _mapActivity(_activityLevel),
    );
    // โชว์ค่า BMR/TDEE/เป้าหมายใหม่ที่คำนวณจริงให้ผู้ใช้เห็น — เดิมโชว์แค่ข้อความสำเร็จทั่วไป
    // ไม่บอกตัวเลข ผู้ใช้ไม่รู้ว่าค่าที่คำนวณใหม่คือเท่าไร
    showAppAlert(
      context,
      'บันทึกสำเร็จ — BMR ${fullStats.bmr.round()} kcal · TDEE ${fullStats.tdee.round()} kcal · เป้าหมาย ${fullStats.targetCal.round()} kcal/วัน',
      type: AppAlertType.success,
    );
    Navigator.pop<Map<String, dynamic>?>(context, {
      'stats': fullStats,
      'target': _mapGoal(_fitnessGoal),
    });
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(child: AppBackButton()),
        ),
        actions: const [SizedBox(width: 64)],
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('แก้ไขข้อมูลร่างกาย',
                style: AppTextStyles.pageTitle),
            SizedBox(height: 2),
            Text('อัปเดตข้อมูลส่วนตัวและเป้าหมายสุขภาพของคุณ',
                style: AppTextStyles.pageSubtitle),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── ส่วนที่ 1: ข้อมูลส่วนตัว ──
                    _buildSectionHeader("ข้อมูลส่วนตัว", Icons.person_outline),
                    const SizedBox(height: 20),

                    _buildLabel("วันเกิด"),
                    const SizedBox(height: 8),
                    _buildDatePicker(),
                    const SizedBox(height: 24),

                    _buildLabel("เพศ"),
                    const SizedBox(height: 8),
                    _buildGenderSelector(),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(child: _buildManualInput("ส่วนสูง", _heightController, "ซม.", errorText: _heightError)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildManualInput("น้ำหนัก", _weightController, "กก.", errorText: _weightError)),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Divider(color: AppColors.divider, thickness: 0.8),
                    ),

                    // ── ส่วนที่ 2: ไลฟ์สไตล์และเป้าหมาย ──
                    _buildSectionHeader("ไลฟ์สไตล์และเป้าหมาย", Icons.auto_awesome_outlined),
                    const SizedBox(height: 24),

                    _buildLabel("คุณออกกำลังกายบ่อยแค่ไหน?"),
                    const SizedBox(height: 16),
                    _buildActivityGrid(),

                    const SizedBox(height: 32),
                    _buildLabel("เป้าหมายหลักของคุณ"),
                    const SizedBox(height: 16),
                    _buildGoalCapsule(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildBottomAction(),
          ],
        ),
      ),
    );
  }

  // ── widgets ─────────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: 22),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      ],
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark),
      );

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_birthDate.day} / ${_birthDate.month} / ${_birthDate.year + 543}',
              style: const TextStyle(fontSize: 16, color: AppColors.textDark),
            ),
            const Icon(Icons.calendar_today_rounded, color: AppColors.primaryGreen, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Row(
      children: [
        Expanded(child: _buildGenderBtn('ชาย', Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _buildGenderBtn('หญิง', Colors.pink)),
      ],
    );
  }

  Widget _buildGenderBtn(String label, Color activeColor) {
    final isSel = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSel ? activeColor.withValues(alpha: 0.5) : AppColors.divider, width: 1.5),
          boxShadow: [
            if (isSel)
              BoxShadow(color: activeColor.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: isSel ? activeColor : AppColors.textMuted,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildManualInput(String label, TextEditingController ctr, String unit, {String? errorText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: ctr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceLight,
            suffixText: unit,
            errorText: errorText,
            errorMaxLines: 2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityGrid() {
    final List<Map<String, dynamic>> activities = [
      {'title': 'ไม่ออกกำลังกาย/นั่งโต๊ะ', 'desc': 'นั่งทำงานหรือพักผ่อนเป็นหลัก', 'icon': Icons.chair_outlined},
      {'title': 'เบา 1-3 วัน/สัปดาห์',      'desc': 'เดินเบาหรือออกกำลังกายเบาๆ',  'icon': Icons.directions_walk},
      {'title': 'ปานกลาง 3-5 วัน/สัปดาห์', 'desc': 'ออกกำลังกายเป็นประจำ',         'icon': Icons.fitness_center},
      {'title': 'หนัก 6-7 วัน/สัปดาห์',    'desc': 'สายสปอร์ตตัวจริง',             'icon': Icons.bolt},
      {'title': 'หนักมาก/นักกีฬา',          'desc': 'ฝึกซ้อมระดับมืออาชีพ',         'icon': Icons.workspace_premium},
    ];
    return Column(
      children: activities.map((item) {
        final isSel = _activityLevel == item['title'];
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _activityLevel = item['title'] as String);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSel ? Colors.white : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isSel ? AppColors.primaryGreen : Colors.transparent, width: 2),
              boxShadow: [
                if (isSel)
                  BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryGreen.withValues(alpha: 0.1)
                        : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item['icon'] as IconData,
                      color: isSel ? AppColors.primaryGreen : AppColors.textMuted, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel ? AppColors.textDark : AppColors.textBody)),
                      Text(item['desc'] as String,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                if (isSel) const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGoalCapsule() {
    final goals = ['ลดน้ำหนัก', 'รักษาน้ำหนัก', 'เพิ่มน้ำหนัก'];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration:
          BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: goals.map((goal) {
          final isSel = _fitnessGoal == goal;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _fitnessGoal = goal);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSel ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    if (isSel)
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Text(goal,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          color: isSel ? AppColors.textDark : AppColors.textMuted)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _saveBodyStats,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Text("บันทึกการเปลี่ยนแปลง",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }
}

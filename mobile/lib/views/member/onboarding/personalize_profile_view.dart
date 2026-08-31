// หน้า: Personalize Profile (Onboarding)
// ทำหน้าที่: หน้าตั้งค่าโปรไฟล์ครั้งแรก ให้สมาชิกใหม่กรอกน้ำหนัก ส่วนสูง เพศ อายุ และเป้าหมายสุขภาพ

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_date_picker_sheet.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../services/auth_service.dart';
import '../../../services/member_service.dart';

class PersonalizeProfileView extends StatefulWidget {
  const PersonalizeProfileView({super.key});

  @override
  State<PersonalizeProfileView> createState() => _PersonalizeProfileViewState();
}

class _PersonalizeProfileViewState extends State<PersonalizeProfileView> {
  DateTime _birthDate = DateTime(2004, 10, 25);
  bool _birthDateSelected = false; 
  String _gender = 'ชาย';
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  String _activityLevel = 'ไม่ออกกำลังกาย/นั่งโต๊ะ';
  String _fitnessGoal = 'รักษาน้ำหนัก';
  bool _isLoading = false;
  String? _heightError;
  String? _weightError;

  static const int _minAge = 13; // อายุขั้นต่ำที่สมัคร/กรอกโปรไฟล์ได้
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

  int get _age {
    final now = DateTime.now();
    int age = now.year - _birthDate.year;
    final birthdayPassedThisYear =
        now.month > _birthDate.month || (now.month == _birthDate.month && now.day >= _birthDate.day);
    if (!birthdayPassedThisYear) age--;
    return age;
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // gender: 1=ชาย, 2=หญิง (ตรงกับ backend int)
  int _mapGender(String g) => g == 'ชาย' ? 1 : 2;

  // activity_level เป็น float ตามมาตรฐาน Harris–Benedict
  double _mapActivity(String a) {
    switch (a) {
      case 'ไม่ออกกำลังกาย/นั่งโต๊ะ':   return 1.2;
      case 'เบา 1-3 วัน/สัปดาห์':       return 1.375;
      case 'ปานกลาง 3-5 วัน/สัปดาห์':  return 1.55;
      case 'หนัก 6-7 วัน/สัปดาห์':     return 1.725;
      case 'หนักมาก/นักกีฬา':           return 1.9;
      default:                           return 1.2;
    }
  }

  // target: 1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ(เพิ่มน้ำหนัก), 3=รักษาน้ำหนัก (ตรงกับ backend int)
  int _mapGoal(String g) {
    switch (g) {
      case 'ลดน้ำหนัก':   return 1;
      case 'เพิ่มน้ำหนัก': return 2;
      case 'รักษาน้ำหนัก': return 3;
      default:             return 3;
    }
  }

  Future<void> _handleSave() async {
    if (_age < _minAge) {
      showAppAlert(context, 'ต้องมีอายุอย่างน้อย $_minAge ปีจึงจะสมัครได้', type: AppAlertType.error);
      return;
    }

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

    final birthStr =
        '${_birthDate.year}-${_birthDate.month.toString().padLeft(2, '0')}-${_birthDate.day.toString().padLeft(2, '0')}';

    // ใช้ endpoint รวม POST /member/update-profile (UpdateProfileRequest)
    final result = await MemberService.to.setupProfile({
      'gender':         _mapGender(_gender),
      'birth_date':     birthStr,
      'height':         h,
      'weight':         w,
      'activity_level': _mapActivity(_activityLevel),
      'target':         _mapGoal(_fitnessGoal),
    });

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      AuthService.to.updateProfileStatus(true);
      Get.toNamed('/onboarding-result');
    } else {
      showAppAlert(context, result['message'] ?? 'บันทึกไม่สำเร็จ', type: AppAlertType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
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
                        Expanded(child: _buildManualInput("ส่วนสูง", _heightController, "ซม.", hint: "170.0", errorText: _heightError)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildManualInput("น้ำหนัก", _weightController, "กก.", hint: "70.0", errorText: _weightError)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Divider(color: AppColors.divider, thickness: 0.8),
                    ),
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

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackButton(onTap: () => Get.offAllNamed('/login')),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ขั้นตอนที่ 2 จาก 3',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text("ปรับแต่งโปรไฟล์", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text("เพื่อให้แผนการออกกำลังกายแม่นยำที่สุดสำหรับคุณ", style: TextStyle(color: AppColors.textBody, fontSize: 15)),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: 22),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
      ],
    );
  }

  Widget _buildLabel(String text) => Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark));

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "${_birthDate.day} / ${_birthDate.month} / ${_birthDate.year + 543}",
              style: TextStyle(fontSize: 16, color: _birthDateSelected ? AppColors.textDark : AppColors.textMuted),
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
        Expanded(child: _buildGenderBtn("ชาย", Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _buildGenderBtn("หญิง", Colors.pink)),
      ],
    );
  }

  Widget _buildGenderBtn(String label, Color activeColor) {
    bool isSel = _gender == label;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSel ? activeColor.withValues(alpha: 0.5) : AppColors.divider, width: 1.5),
          boxShadow: [if (isSel) BoxShadow(color: activeColor.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: isSel ? activeColor : AppColors.textMuted, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildManualInput(String label, TextEditingController ctr, String unit, {String? hint, String? errorText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: ctr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          onTap: () => ctr.selection = TextSelection(
            baseOffset: 0, extentOffset: ctr.text.length),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceLight,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMuted),
            errorText: errorText,
            errorMaxLines: 2,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 1.0,
                child: Text(unit, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityGrid() {
    final List<Map<String, dynamic>> activities = [
      {'title': 'ไม่ออกกำลังกาย/นั่งโต๊ะ',  'desc': 'นั่งทำงานหรือพักผ่อนเป็นหลัก',  'icon': Icons.chair_outlined},
      {'title': 'เบา 1-3 วัน/สัปดาห์',       'desc': 'เดินเบาหรือออกกำลังกายเบาๆ',   'icon': Icons.directions_walk},
      {'title': 'ปานกลาง 3-5 วัน/สัปดาห์',  'desc': 'ออกกำลังกายเป็นประจำ',          'icon': Icons.fitness_center},
      {'title': 'หนัก 6-7 วัน/สัปดาห์',     'desc': 'สายสปอร์ตตัวจริง',              'icon': Icons.bolt},
      {'title': 'หนักมาก/นักกีฬา',           'desc': 'ฝึกซ้อมระดับมืออาชีพ',          'icon': Icons.workspace_premium},
    ];
    return Column(
      children: activities.map((item) {
        bool isSel = _activityLevel == item['title'];
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
              border: Border.all(color: isSel ? AppColors.primaryGreen : Colors.transparent, width: 2),
              boxShadow: [if (isSel) BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.15), blurRadius: 15, offset: const Offset(0, 8))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.primaryGreen.withValues(alpha: 0.1) : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item['icon'] as IconData, color: isSel ? AppColors.primaryGreen : AppColors.textMuted, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['title'] as String, style: TextStyle(fontSize: 15, fontWeight: isSel ? FontWeight.bold : FontWeight.w500, color: isSel ? AppColors.textDark : AppColors.textBody)),
                      Text(item['desc'] as String, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: goals.map((goal) {
          bool isSel = _fitnessGoal == goal;
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
                  boxShadow: [if (isSel) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2))],
                ),
                child: Center(child: Text(goal, style: TextStyle(fontSize: 14, fontWeight: isSel ? FontWeight.bold : FontWeight.w500, color: isSel ? AppColors.textDark : AppColors.textMuted))),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
              : const Text("บันทึกและดำเนินการต่อ", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showAppCalendarPicker(
      context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - _minAge, now.month, now.day), // กันเลือกวันเกิดที่ทำให้อายุต่ำกว่าเกณฑ์
      title: 'เลือกวันเกิด',
    );
    if (picked != null) setState(() { _birthDate = picked; _birthDateSelected = true; });
  }
}

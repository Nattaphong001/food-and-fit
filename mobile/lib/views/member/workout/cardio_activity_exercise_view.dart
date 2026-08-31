// หน้า: Cardio Activity Exercise (บันทึกคาร์ดิโอ)
// ทำหน้าที่: หน้าออกกำลังกายคาร์ดิโอจริง จับเวลา บันทึกระยะทาง และคำนวณแคลอรี่เผาผลาญ

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/cached_image.dart';
import '../../../core/widgets/expandable_session_sheet.dart';
import '../../../core/widgets/top_flash.dart';
import '../../../core/widgets/workout_timer.dart';
import '../../../services/member_service.dart';
import '../../../services/workout_service.dart';

class CardioActivityExerciseView extends StatefulWidget {
  final int cardioTypeId;
  final String activityName;
  final String exerciseName;
  final String imageUrl;
  final String loopVideoUrl;
  final double mets;
  final bool hasDistance;

  const CardioActivityExerciseView({
    super.key,
    required this.cardioTypeId,
    this.activityName = 'Cardio Workout',
    this.exerciseName = 'Cardio Workout',
    this.imageUrl = '',
    this.loopVideoUrl = '',
    this.mets = 6.0,
    this.hasDistance = false,
  });

  @override
  State<CardioActivityExerciseView> createState() => _CardioActivityExerciseViewState();
}

class _CardioActivityExerciseViewState extends State<CardioActivityExerciseView>
    with SingleTickerProviderStateMixin {

  // วนซ้ำตลอดเบาๆ ขับแสง glow รอบ banner แจ้งเตือนพักให้เด่นเป็นระยะ (ดู
  // _buildRestAlertBanner) — เบาพอไม่ต้อง start/stop ตามการมองเห็นของ banner
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  late final Animation<double> _glowAnim =
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut);

  // ── Expandable session sheet (YouTube Music style) ──────────────────────────
  // Footer เป็นแถวเดียวกะทัดรัด (นาฬิกา + ปุ่มวงกลม) เหมือน weight-training exercise
  // จึงพอดีกับ 0.2 ของจอโดยไม่ overflow — ไม่ต้องกันพื้นที่พิเศษเหมือนตอนใช้ปุ่มมีป้ายข้อความ
  // expanded เตี้ยกว่าเวทมาก (0.38 ไม่ใช่ 0.9) เพราะเนื้อหาคาร์ดิโอมีแค่หัวการ์ด + สถิติ
  // เวลา/แคลสด 2 กล่อง ไม่มีตารางเซตหรือฟอร์มกรอกที่ต้องการพื้นที่เยอะแบบเวท
  static const _collapsedSheetSize = 0.2;
  static const _expandedSheetSize = 0.38;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _sheetExtent = _collapsedSheetSize;

  void _onSheetExtentChanged() {
    if (!_sheetController.isAttached) return;
    setState(() => _sheetExtent = _sheetController.size);
  }

  // 0 ตอน sheet หด (collapsed) → 1 ตอนยืดเต็ม (expanded) — ใช้ขับ morph ของนาฬิกา
  // (พื้นหลังไม่ใช้ตัวนี้แล้ว — เต็มจอเสมอ ไม่งั้นจะเกิดช่องว่างเทาระหว่างภาพกับ sheet)
  double get _sheetT =>
      ((_sheetExtent - _collapsedSheetSize) / (_expandedSheetSize - _collapsedSheetSize)).clamp(0.0, 1.0);

  // ── Loop Video ────────────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;

  // ── Timer States ──────────────────────────────────────────────────────────────
  bool _isCountingDown = true;
  bool _isResting = false;
  bool _showSummary = false;

  int _countdownSeconds = 5;
  int _globalSeconds = 0;
  int _restSeconds = 0;

  Timer? _countdownTimer;
  Timer? _globalTimer;
  Timer? _restTimer;

  // เวลาที่ session เริ่มจริง (หลัง countdown จบ) ใช้ตอนบันทึกแทน DateTime.now()
  // ตอนกดปุ่มบันทึก กัน session ที่คาบเที่ยงคืนถูกลงวันที่ผิด
  DateTime? _sessionStartTime;

  String? _alertMessage;
  bool _isTimerHighlighted = false;

  // ── Data Controllers ──────────────────────────────────────────────────────────
  final _distanceController = TextEditingController();

  // น้ำหนักจริงของสมาชิก ใช้คำนวณแคลอรี่สดระหว่างเล่น ให้ตรงกับที่ backend
  // ใช้คำนวณตอนบันทึกจริง (SaveCardioResult ใช้ mbs_weight ล่าสุดของสมาชิก ไม่ใช่ค่าคงที่)
  double _memberWeightKg = 65.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ล็อกแนวตั้งระหว่างฝึก — การ์ดสถิติ/ปุ่มหยุด-จบ ใช้ความสูงคงที่ที่ออกแบบมาสำหรับจอแนวตั้ง
    // เท่านั้น หมุนเป็นแนวนอนแล้วพื้นที่ collapsed sheet เหลือน้อยกว่าความสูงเนื้อหาจริงมาก
    // ทำให้ overflow และปุ่มหยุด/จบการฝึกหลุดจากขอบจอกดไม่ได้ (พบจากทดสอบจริงบนเครื่อง 2026-08-21)
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _distanceController.addListener(() => setState(() {}));
    _sheetController.addListener(_onSheetExtentChanged);
    _startPreCountdown();
    _loadMemberWeight();
    if (widget.loopVideoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.loopVideoUrl))
        ..initialize().then((_) {
          if (mounted) {
            _videoController!.setLooping(true);
            _videoController!.setVolume(0);
            // ไม่ play() ที่นี่ — ปล่อยให้คลิปหยุดที่เฟรมแรกจนกว่านับถอยหลังจะจบ
            // (กัน flicker สลับภาพเดิม/วิดีโอกลางที่นับเลข) ไป play() ต่อใน _startPreCountdown()
            if (!_isCountingDown) _videoController!.play();
            setState(() {});
          }
        });
    }
  }

  Future<void> _loadMemberWeight() async {
    final result = await MemberService.to.getProfile();
    if (!mounted || result['success'] != true) return;
    final rawStats = result['body_stats'] as Map<String, dynamic>?;
    final w = double.tryParse(rawStats?['weight']?.toString() ?? '');
    if (w != null && w > 0) setState(() => _memberWeightKg = w);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _sheetController.removeListener(_onSheetExtentChanged);
    _sheetController.dispose();
    _glowController.dispose();
    _countdownTimer?.cancel();
    _globalTimer?.cancel();
    _restTimer?.cancel();
    _distanceController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Timer Logic
  // ─────────────────────────────────────────────────────────────────────────────

  void _startPreCountdown() {
    HapticFeedback.heavyImpact();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_countdownSeconds > 1) {
        HapticFeedback.selectionClick();
        setState(() => _countdownSeconds--);
      } else {
        HapticFeedback.vibrate();
        timer.cancel();
        _sessionStartTime = DateTime.now();
        setState(() => _isCountingDown = false);
        _videoController?.play();
        _startGlobalTimer();
      }
    });
  }

  void _startGlobalTimer() {
    _globalTimer?.cancel();
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _globalSeconds++);
    });
  }

  void _startRest() {
    HapticFeedback.lightImpact();
    _globalTimer?.cancel();
    setState(() {
      _isResting = true;
      _restSeconds = 0;
      _alertMessage = null;
      _isTimerHighlighted = false;
    });
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _restSeconds++;
        _checkRestAlerts(_restSeconds);
      });
    });
  }

  // เริ่มพัก + กางแผ่นชีทขึ้นเป็น expanded อัตโนมัติ ให้เห็นสถิติสะสม/ช่องกรอกระยะทาง
  // ชัดเจนระหว่างพัก (pattern เดียวกับ weight_training_exercise_view._beginRest)
  void _beginRest() {
    _startRest();
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _expandedSheetSize,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  // คาร์ดิโอไม่มีข้อมูลต้องกรอกครบก่อนถึงจะกลับมาฝึกต่อได้แบบเวท (ไม่มี concept
  // "เซต" ให้บันทึก) กดปุ่มนี้แล้วกลับมาฝึกต่อได้ทันทีเสมอ
  void _endRest() {
    HapticFeedback.lightImpact();
    _restTimer?.cancel();
    setState(() {
      _isResting = false;
      _restSeconds = 0;
      _alertMessage = null;
      _isTimerHighlighted = false;
    });
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _collapsedSheetSize,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    _startGlobalTimer();
  }

  void _checkRestAlerts(int seconds) {
    String? msg;
    bool highlight = false;
    if (seconds == 30) {
      msg = '30 วิ · หายใจช้าลง ฟื้นตัวดี';
      HapticFeedback.mediumImpact();
    } else if (seconds == 60) {
      msg = '60 วิ · พร้อมลุยต่อหรือยัง?';
      HapticFeedback.heavyImpact();
      highlight = true;
    } else if (seconds == 90) {
      msg = '90 วิ · ร่างกายพร้อมเต็มที่';
      HapticFeedback.heavyImpact();
    } else if (seconds == 120) {
      msg = '2 นาที · พักนานคุมคุณภาพการฝึก';
      HapticFeedback.vibrate();
    }
    if (msg != null) {
      _isTimerHighlighted = highlight;
      setState(() => _alertMessage = msg);
    }
  }

  void _endWorkout() {
    HapticFeedback.mediumImpact();
    _globalTimer?.cancel();
    setState(() => _showSummary = true);
  }

  // ยืนยันตอนกดบันทึกจริงจากหน้าสรุปผล (ไม่ใช่ตอนกดปุ่มหยุดสีแดงอีกต่อไป) — กันกดพลาด
  // ตรงจุดที่ข้อมูลจะถูกเขียนลงจริง แทนที่จะถามตั้งแต่กลางเซสชัน
  Future<void> _confirmSaveWorkout() async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.flag_rounded,
      title: 'บันทึกการฝึก?',
      content: 'ยืนยันบันทึกข้อมูลการฝึกครั้งนี้',
      confirmLabel: 'บันทึก',
      cancelLabel: 'ยกเลิก',
      color: AppColors.primaryGreen,
    );
    if (confirm) await _submitWorkoutData();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Calculated Values
  // ─────────────────────────────────────────────────────────────────────────────

  int _getCalculatedMinutes() {
    int minutes = _globalSeconds ~/ 60;
    return (minutes == 0 && _globalSeconds > 0) ? 1 : minutes;
  }

  double _getCalculatedCalories() {
    final double effectiveMets = widget.mets > 0 ? widget.mets : 6.0;
    // ใช้วินาทีจริงต่อเนื่อง (ไม่ปัดเป็นนาที) ให้ตัวเลขไหลทุกวินาทีตาม _globalTimer
    // ต่างจาก _getCalculatedMinutes() ที่ปัดเป็นนาทีไว้ใช้ตอนบันทึกผลเท่านั้น
    return effectiveMets * _memberWeightKg * (_globalSeconds / 3600.0);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Save Logic
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _submitWorkoutData() async {
    final int durationMinutes = _getCalculatedMinutes();
    if (durationMinutes <= 0) {
      showAppAlert(context, 'เวลาฝึกน้อยเกินไป กรุณาฝึกอย่างน้อย 1 นาที', type: AppAlertType.warning);
      return;
    }

    final sessionDate = (_sessionStartTime ?? DateTime.now()).toIso8601String().split('T').first;
    final Map<String, dynamic> payload = {
      'date': sessionDate,
      'cdo_id': widget.cardioTypeId,
      'cdors_duration': durationMinutes,
    };

    if (widget.hasDistance) {
      final dist = double.tryParse(_distanceController.text.trim()) ?? 0.0;
      payload['cdors_distance'] = dist;
    }

    final result = await WorkoutService.to.saveCardioResult(payload);

    if (!mounted) return;
    final bool success = result['success'] == true;

    showAppAlert(context, success ? 'บันทึกสำเร็จ เยี่ยมมาก!' : 'เกิดข้อผิดพลาดในการบันทึก',
        type: success ? AppAlertType.success : AppAlertType.error);
    if (success) Navigator.pop(context);
  }

  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _formatTimeSummary(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _confirmExit() async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.exit_to_app_rounded,
      title: 'ออกจากการฝึก?',
      content: 'ข้อมูลการฝึกในครั้งนี้จะไม่ถูกบันทึก',
      confirmLabel: 'ออก',
      cancelLabel: 'ฝึกต่อ',
    );
    if (confirm && mounted) Navigator.pop(context);
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // UI BUILD
  // ═════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmExit(); },
      child: Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildImageHeader(),
          _buildDimOverlay(),
          ExpandableSessionSheet(
            controller: _sheetController,
            collapsedSize: _collapsedSheetSize,
            expandedSize: _expandedSheetSize,
            header: _buildExerciseHeaderRow(),
            bodyBuilder: (context, scrollController) => _buildWorkoutContent(scrollController),
            footer: _buildBottomControls(),
          ),
          Positioned(
            left: 20,
            top: MediaQuery.of(context).padding.top + 15,
            child: AppBackButton(onTap: _confirmExit),
          ),
          _buildCornerTimer(),
          _buildRestAlertBanner(),
          if (_showSummary) _buildSummaryOverlay(),
          if (_isCountingDown) _buildPreCountdownOverlay(),
        ],
      ),
    ),
    );
  }

  // ── Image Header ──────────────────────────────────────────────────────────────

  Widget _buildImageHeader() {
    final bool showVideo = _videoController != null && _videoController!.value.isInitialized;

    // crop-to-fill (BoxFit.cover) แทน AspectRatio+Center เดิม — กันแถบดำ letterbox
    // บน-ล่าง/ซ้าย-ขวา, Transform.scale overscan เล็กน้อยกันขอบเบลอ (pattern เดียวกับ
    // weight_training_exercise_view / core/widgets/loop_video_header.dart)
    final Widget content = showVideo
        ? ClipRect(
            child: Transform.scale(
              scale: 1.1,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
          )
        : (widget.imageUrl.isNotEmpty
            ? cachedImage(widget.imageUrl, fit: BoxFit.cover)
            : Container(
                color: Colors.grey.shade900,
                child: const Center(child: Icon(Icons.directions_run, size: 80, color: Colors.white24)),
              ));

    return Positioned.fill(
      child: Container(
        color: const Color(0xFF111111),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            // เกรเดียนต์บนสุด — กันปุ่มย้อนกลับ/นาฬิกามุมขวาจมกับพื้นหลังสว่าง
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dim Overlay ───────────────────────────────────────────────────────────────
  // ชั้นสีดำโปร่งใสระหว่างคลิปพื้นหลังกับการ์ด — opacity ผูกกับ _sheetT ตรงๆ (การ์ดยิ่ง
  // ปัดขึ้นเปิดกว้าง คลิปยิ่งมืดลง) ให้เห็นความต่างชัดตอนเปิด/ปิดการ์ด (pattern เดียวกับ
  // weight_training_exercise_view._buildDimOverlay) — IgnorePointer กันบังการแตะ
  Widget _buildDimOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('cardioBgDimOverlay'),
          color: Colors.black.withValues(alpha: _sheetT * 0.6),
        ),
      ),
    );
  }

  // ── Exercise Header Row ───────────────────────────────────────────────────────
  // ย้ายมาเป็น header ของ ExpandableSessionSheet แทนที่จะฝังใน bodyBuilder — โซนนี้อยู่ใน
  // GestureDetector ลากรีไซส์เฉพาะของ handle เสมอ (ดู expandable_session_sheet.dart) ทำให้
  // ปัดจากบล็อกชื่อกิจกรรมได้ลื่นไหลแบบเดียวกับหน้าฝึกเวท (weight_training_exercise_view
  // ._buildExerciseHeaderRow) ไม่ต้องพึ่งพา scroll-physics fallback ของ body เพียงอย่างเดียว
  Widget _buildExerciseHeaderRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(color: Color(0xFF00F28A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.exerciseName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.black87),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F28A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.activityName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF00C070)),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }

  // ── Workout Content ───────────────────────────────────────────────────────────
  // คาร์ดิโอไม่มี "เซต" ให้บันทึกทีละรายการแบบเวท จึงโชว์สถิติสะสมแบบเรียลไทม์แทน
  // (เวลาออกกำลังกายจริง + แคลที่เผาผลาญ อัปเดตทุกวินาที) เท่านั้น — ไม่มีช่องกรอกระยะทาง
  // ตรงนี้ ระยะทางกรอกได้ที่เดียวตอนกดจบการฝึกแล้ว (ดู _buildSummaryOverlay) การ์ดจึงสั้น
  // กระชับ ไม่ต้องยืดสูงเหมือนเวทที่มีตารางเซตยาวๆ
  Widget _buildWorkoutContent(ScrollController scrollController) {
    return SingleChildScrollView(
      controller: scrollController,
      // เผื่อกรณีเนื้อหาไม่พอดีเป๊ะ (เช่นจอเล็กมาก) ยังปัดต่อจากพื้นที่สถิติได้เหมือนกัน
      // แม้ตอนนี้จุดลากหลักย้ายไปที่ header แล้ว (ดูด้านบน)
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _buildLiveStatsRow(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLiveStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        children: [
          _liveStatBox(
            icon: Icons.timer_outlined,
            label: 'เวลาออกกำลังกาย',
            value: _formatTimeSummary(_globalSeconds),
            color: const Color(0xFF2BEE8C),
          ),
          const SizedBox(width: 12),
          _liveStatBox(
            icon: Icons.local_fire_department_rounded,
            label: 'เผาผลาญ',
            value: '${_getCalculatedCalories().round()} cal',
            color: const Color(0xFFFFB74D),
          ),
        ],
      ),
    );
  }

  Widget _liveStatBox({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.black45, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── Bottom Controls ───────────────────────────────────────────────────────────

  Color get _restTimerColor =>
      _isTimerHighlighted ? const Color(0xFF00FF6E) : const Color(0xFF2BEE8C);

  // แถวเดียว: ปกติ = นาฬิกา + ปุ่มหยุดพัก/จบการฝึก, ตอนพัก = morph เป็นนาฬิกาพัก + ปุ่ม
  // กลับมาฝึกต่อ — ย้ายจาก full-screen overlay เดิมมาอยู่ในชีทเดียวกับเวท (pattern เดียวกับ
  // weight_training_exercise_view) ให้ผู้ใช้ยังเห็นวิดีโอ/สถิติสะสมระหว่างพัก ไม่ต้องปิดจอทึบ
  // ทั้งใบ — ต่างจากเวทตรงที่ไม่มีเงื่อนไข "กรอกครบก่อนถึงจะบันทึกได้" เพราะคาร์ดิโอไม่มีเซต
  // ให้บันทึกทีละรายการ ปุ่มจึงเป็นสไตล์เดียวเสมอ กดกลับมาฝึกต่อได้ทันที
  Widget _buildBottomControls() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: _isResting ? _buildRestingRow() : _buildActiveRow(),
        ),
      ),
    );
  }

  // ── Rest Alert Banner (Samsung One UI style) ──────────────────────────────────
  // แจ้งเตือนพักลอยกลางบนสุดของจอ (ไม่ผูกกับ footer/การ์ดอีกต่อไป) สไลด์ลง+เฟดเข้า
  // เหมือน heads-up notification ของ One UI ข้อความสั้นแถวเดียวอ่านง่าย (maxLines:1
  // กันล้น) — ใช้ pattern เดียวกันทั้งหน้าฝึกเวทและคาร์ดิโอ มีแสง glow สีเดียวกับนาฬิกาพัก
  // เต้นรอบการ์ดเป็นจังหวะ (ขับด้วย _glowController ที่วนซ้ำตลอด) ให้เด่นสะดุดตาเป็นระยะ
  Widget _buildRestAlertBanner() {
    final bool visible = _isResting && _alertMessage != null;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            offset: visible ? Offset.zero : const Offset(0, -1.5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: visible ? 1 : 0,
              child: AnimatedBuilder(
                animation: _glowAnim,
                builder: (context, child) {
                  final double glow = _glowAnim.value;
                  return Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xF01C1C1E),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: _restTimerColor.withValues(alpha: 0.25 + glow * 0.25)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                        BoxShadow(
                          color: _restTimerColor.withValues(alpha: 0.18 + glow * 0.3),
                          blurRadius: 14 + glow * 16,
                          spreadRadius: 0.5 + glow * 2.5,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.self_improvement_rounded, color: _restTimerColor, size: 17),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        _alertMessage ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: 1 - _sheetT,
          child: Text(
            _formatTime(_globalSeconds),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              fontFamily: 'Inter',
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 24),
        _buildControlButton(Icons.pause_rounded, Colors.grey.shade600, _beginRest),
        const SizedBox(width: 12),
        _buildControlButton(Icons.stop_rounded, const Color(0xFFFF4C4C), _endWorkout),
      ],
    );
  }

  Widget _buildRestingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.self_improvement_rounded, color: _restTimerColor, size: 22),
        const SizedBox(width: 10),
        WorkoutTimer(seconds: _restSeconds, fontSize: 24, color: _restTimerColor, fontWeight: FontWeight.w800),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _endRest,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: _restTimerColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: _restTimerColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                SizedBox(width: 6),
                Text('กลับมาฝึกต่อ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  // ── Corner Timer (Expanded/Logging mode) ─────────────────────────────────────
  // Crossfade กับนาฬิกาที่ footer ตาม _sheetT แบบเรียลไทม์ — เหมือนกับ weight-training view
  Widget _buildCornerTimer() {
    final double t = _sheetT;
    if (t <= 0.0) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 15,
      right: 20,
      child: IgnorePointer(
        ignoring: t < 0.5,
        child: Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: WorkoutTimer(
                  seconds: _globalSeconds, fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  // ── Summary Overlay (weight training UX style) ────────────────────────────────

  Widget _buildSummaryOverlay() {
    const Color green = Color(0xFF2BEE8C);
    final String autoCalories = _getCalculatedCalories().round().toString();
    final String distText = _distanceController.text.trim();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.95),
        child: SafeArea(
          child: Column(
            children: [

              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() => _showSummary = false);
                        _startGlobalTimer();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white54, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Content ────────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      const Text('สรุปผลการฝึก',
                          style: TextStyle(color: Colors.white70, fontSize: 13,
                              fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      Text(widget.exerciseName,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),

                      const SizedBox(height: 28),

                      // ── Stat boxes ─────────────────────────────────────────
                      Row(
                        children: [
                          _statBox(
                            icon: Icons.timer_rounded,
                            label: 'เวลาฝึก',
                            value: _formatTimeSummary(_globalSeconds),
                            color: green,
                          ),
                          const SizedBox(width: 12),
                          _statBox(
                            icon: Icons.local_fire_department_rounded,
                            label: 'เผาผลาญ',
                            value: '$autoCalories cal',
                            color: const Color(0xFFFFB74D),
                          ),
                          if (widget.hasDistance) ...[
                            const SizedBox(width: 12),
                            _statBox(
                              icon: Icons.straighten_rounded,
                              label: 'ระยะทาง',
                              value: distText.isNotEmpty ? '$distText กม.' : '- กม.',
                              color: const Color(0xFF64B5F6),
                            ),
                          ],
                        ],
                      ),

                      // ── Distance input (ถ้ามี) ─────────────────────────────
                      if (widget.hasDistance) ...[
                        const SizedBox(height: 28),
                        const Text('บันทึกระยะทาง',
                            style: TextStyle(color: Colors.white70, fontSize: 13,
                                fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildDarkInput('ระยะทาง (กม.)', _distanceController, allowDecimal: true),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Actions ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirmSaveWorkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('บันทึกการฝึก',
                            style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        setState(() => _showSummary = false);
                        _startGlobalTimer();
                      },
                      child: const Text('ฝึกต่อ', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _statBox({required IconData icon, required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value, textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkInput(String label, TextEditingController controller, {bool allowDecimal = false}) {
    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: const InputDecorationTheme()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            width: 120,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: controller,
              keyboardType: allowDecimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              inputFormatters: allowDecimal
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                  : [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '-',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted) Navigator.pop(context);
  }

  // ── Pre-Countdown Overlay ─────────────────────────────────────────────────────

  Widget _buildPreCountdownOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      width: double.infinity,
      child: Stack(
        children: [
          Center(
            child: Text(
              '$_countdownSeconds',
              style: const TextStyle(fontSize: 150, fontWeight: FontWeight.w900, color: Color(0xFF2BEE8C)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 16),
              child: AppBackButton(onTap: _cancelCountdown),
            ),
          ),
        ],
      ),
    );
  }
}

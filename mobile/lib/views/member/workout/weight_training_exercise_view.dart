// หน้า: Weight Training Exercise (บันทึกการฝึกเวท)
// ทำหน้าที่: หน้าออกกำลังกายจริง จับเวลาพัก บันทึกเซ็ต/น้ำหนัก/จำนวนครั้ง และบันทึกผลลงฐานข้อมูลเมื่อจบ

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
import '../../../services/workout_service.dart';

class WeightTrainingExerciseView extends StatefulWidget {
  final int exerciseId;
  final String exerciseName;
  final String imageUrl;
  final String loopVideoUrl;
  final int exerciseType;      // 1=หลายกลุ่ม, 2=เฉพาะส่วน
  final String muscleGroupName; // เช่น ขา, อก, หลัง
  final int? wschId;   // wsch_id จริงจาก workout_schedules ถ้าท่านี้อยู่ในแผน — มีแล้วใช้ตรงๆ ไม่ต้องสร้างใหม่
  final int? planId;   // ใช้เฉพาะตอนไม่มี wschId (ad-hoc: ท่านอกแผน) คู่กับ isCustomPlan
  final bool isCustomPlan;

  const WeightTrainingExerciseView({
    super.key,
    this.exerciseId = 0,
    this.exerciseName = 'Exercise',
    this.imageUrl = '',
    this.loopVideoUrl = '',
    this.exerciseType = 1,
    this.muscleGroupName = '',
    this.wschId,
    this.planId,
    this.isCustomPlan = false,
  });

  @override
  State<WeightTrainingExerciseView> createState() =>
      _WeightTrainingExerciseViewState();
}

class _WeightTrainingExerciseViewState
    extends State<WeightTrainingExerciseView>
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
  // Collapsed footer มีแค่แถวเดียว (นาฬิกา + ปุ่มหยุดพัก/จบการฝึก) — เตี้ยพอให้ 0.2
  // ของจอพอดี ไม่ล้น และเผื่อพื้นที่ภาพพื้นหลังด้านบนให้เห็นเยอะขึ้น
  // Expanded 0.65 (ไม่เต็มจอ 0.9 แบบเดิม — ดูโล่งกว่า เหลือพื้นที่ภาพพื้นหลังด้านบนเสมอ)
  static const _collapsedSheetSize = 0.2;
  static const _expandedSheetSize = 0.65;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _sheetExtent = _collapsedSheetSize;

  void _onSheetExtentChanged() {
    if (!_sheetController.isAttached) return;
    setState(() => _sheetExtent = _sheetController.size);
  }

  // 0 ตอน sheet หด (collapsed) → 1 ตอนยืดเต็ม (expanded) — ใช้ขับ morph ของนาฬิกา
  // และความมืดของพื้นหลัง (ดู _buildDimOverlay) แบบเรียลไทม์ตาม extent จริงของ sheet
  double get _sheetT =>
      ((_sheetExtent - _collapsedSheetSize) / (_expandedSheetSize - _collapsedSheetSize)).clamp(0.0, 1.0);

  String get _exerciseLabel {
    final type = widget.exerciseType == 2 ? 'เฉพาะส่วน' : 'หลายกลุ่ม';
    final group = widget.muscleGroupName.isNotEmpty ? ' • ${widget.muscleGroupName}' : '';
    return '$type$group';
  }

  // ── Loop Video ────────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;

  // ── Timer States ────────────────────────────────────────────────────────────
  bool _isCountingDown = true;
  bool _isResting = false;

  int _countdownSeconds = 5;
  // เวลาฝึกทั้งเซสชัน (รวมพักด้วย — เดินต่อเนื่องไม่หยุดตอนพัก ดู _startRest) คอมเมนต์เดิมตรงนี้
  // เขียนผิดว่า "ไม่รวมพัก" ทั้งที่โค้ดจริงไม่เคย cancel _globalTimer ตอนพักเลย แก้คำอธิบายให้ตรง
  // ของจริง (2026-08-22) — ใช้ตัวนี้เป็นฐานเวลาคำนวณแคลอรี่ระดับเซสชันด้วย (ดู _saveWorkoutToApi)
  int _globalSeconds = 0;
  int _restSeconds = 0;
  int _activeSetSeconds = 0; // เวลาออกแรงต่อเซต — ใช้คำนวณแคล
  bool _showSummary = false;
  double _summaryVolume = 0;

  Timer? _countdownTimer;
  Timer? _globalTimer;
  Timer? _activeSetTimer;
  Timer? _restTimer;
  Timer? _alertTimer;

  // ── Alert / Visual States ────────────────────────────────────────────────────
  String? _alertMessage;
  bool _isTimerHighlighted = false;

  // ── Set Data ─────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _completedSets = [];

  final _repsController = TextEditingController();
  final _weightController = TextEditingController();

  // ─────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ล็อกแนวตั้งระหว่างฝึก — เหตุผลเดียวกับ cardio_activity_exercise_view.dart (การ์ด
    // ตารางเซต/ปุ่มหยุด-จบ ใช้ความสูงคงที่ที่ออกแบบสำหรับจอแนวตั้ง หมุนแนวนอนแล้ว overflow
    // ปุ่มหลุดจอ — sheet นี้ expanded สูงถึง 0.9 ของจอด้วย เสี่ยง overflow มากกว่า cardio อีก)
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    _repsController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
    _sheetController.addListener(_onSheetExtentChanged);
    _startPreCountdown();
    if (widget.loopVideoUrl.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.loopVideoUrl),
      )..initialize().then((_) {
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

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _sheetController.removeListener(_onSheetExtentChanged);
    _sheetController.dispose();
    _glowController.dispose();
    _countdownTimer?.cancel();
    _globalTimer?.cancel();
    _activeSetTimer?.cancel();
    _restTimer?.cancel();
    _alertTimer?.cancel();
    _repsController.dispose();
    _weightController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Timer Logic
  // ─────────────────────────────────────────────────────────────────────────────

  void _startPreCountdown() {
    HapticFeedback.heavyImpact();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds > 1) {
        HapticFeedback.selectionClick();
        setState(() => _countdownSeconds--);
      } else {
        HapticFeedback.vibrate();
        timer.cancel();
        setState(() => _isCountingDown = false);
        _videoController?.play();
        _startGlobalTimer();
      }
    });
  }

  void _startGlobalTimer() {
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _globalSeconds++);
    });
    _startActiveSetTimer();
  }

  void _startActiveSetTimer() {
    _activeSetTimer?.cancel();
    _activeSetSeconds = 0;
    _activeSetTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _activeSetSeconds++;
    });
  }

  void _startRest() {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    // เวลาฝึกรวม (_globalSeconds) เดินต่อเนื่องไม่หยุดแม้ตอนพัก — นาฬิกาเรือนบนสุด
    // แสดงเวลาที่ใช้ไปทั้งเซสชันจริง ส่วนเวลาออกแรงต่อเซต (_activeSetSeconds ใช้คำนวณแคล)
    // หยุดนับระหว่างพักเท่านั้น เพราะร่างกายแทบไม่เผาผลาญจากการออกแรงตอนพัก
    _activeSetTimer?.cancel(); // หยุดนับ active time ระหว่างพัก

    // Smart auto-fill: ดึงน้ำหนักจากเซตล่าสุด ล้างครั้ง
    if (_completedSets.isNotEmpty) {
      _weightController.text = _completedSets.last['weight'].toString();
      _repsController.clear();
    } else {
      _repsController.clear();
      _weightController.clear();
    }

    setState(() {
      _isResting = true;
      _restSeconds = 0;
      _alertMessage = null;
      _isTimerHighlighted = false;
    });

    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _restSeconds++;
        _checkRestAlerts(_restSeconds);
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Alert Logic (แสดงเหนือนาฬิกาพัก แทน SnackBar)
  // ─────────────────────────────────────────────────────────────────────────────

  void _checkRestAlerts(int seconds) {
    String? msg;
    bool highlight = false;
    if (seconds == 30) {
      msg = '30 วิ · เริ่มฟื้นตัวดีแล้ว';
      HapticFeedback.mediumImpact();
    } else if (seconds == 60) {
      msg = '60 วิ · พร้อมลุยเซตต่อไปหรือยัง?';
      HapticFeedback.heavyImpact();
      highlight = true;
    } else if (seconds == 90) {
      msg = '90 วิ · ร่างกายพร้อมลุยเต็มที่';
      HapticFeedback.heavyImpact();
    } else if (seconds == 120) {
      msg = '2 นาที · พักนานเน้นพละกำลัง';
      HapticFeedback.vibrate();
    }

    if (msg != null) {
      _isTimerHighlighted = highlight;
      _showInlineAlert(msg);
    }
  }

  void _showInlineAlert(String message) {
    _alertTimer?.cancel();
    setState(() => _alertMessage = message);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Validation & Save Logic
  // ─────────────────────────────────────────────────────────────────────────────

  // กรอกครบทั้งน้ำหนักและจำนวนครั้งหรือไม่ — คุมทั้ง validation ตอนบันทึกเซต และ
  // สไตล์ปุ่ม "จบการพัก" (ดู _buildRestingRow) ให้ตรงกันเสมอ
  bool get _canSaveSet =>
      _weightController.text.trim().isNotEmpty && _repsController.text.trim().isNotEmpty;

  // จบการพัก: กดปุ่มนี้ "จบการพักได้เสมอ" ไม่ว่าจะกรอกครบหรือไม่ — ต่างจากเดิมที่กรอก
  // ไม่ครบแล้วกดไม่ออกจากโหมดพักเลย บันทึกเซตเฉพาะตอนกรอกครบทั้งสองช่องเท่านั้น
  // (ใช้ทั้งปุ่ม "เพิ่มเซต" ในฟอร์ม และปุ่ม "จบการพัก"/"จบการพักและบันทึก" ที่ footer —
  // ทำหน้าที่เดียวกัน) ปัดสไลด์ลงเฉยๆ ไม่นับว่าจบพัก ต้องกดปุ่มนี้เท่านั้น
  void _finishRest() {
    if (_canSaveSet) {
      final String w = _weightController.text.trim();
      final String r = _repsController.text.trim();
      setState(() {
        _completedSets.add({
          'set': _completedSets.length + 1,
          'reps': r,
          'weight': w,
          'active_seconds': _activeSetSeconds.clamp(5, 600),
        });
      });
    }
    _endRest();
  }

  // เริ่มพัก + กางแผ่นชีทขึ้นเป็น expanded อัตโนมัติ ให้ฟอร์มกรอกข้อมูลเลื่อนขึ้นมาพร้อมใช้
  // นาฬิกาพัก (_restTimer) เดินต่อเนื่องเบื้องหลังเสมอ ไม่ว่าผู้ใช้จะลากชีทขึ้น/ลงเองแค่ไหน
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

  void _endRest() {
    HapticFeedback.lightImpact();
    _restTimer?.cancel();
    _alertTimer?.cancel();
    setState(() {
      _isResting = false;
      _restSeconds = 0;
      _alertMessage = null;
      _isTimerHighlighted = false;
    });
    // พับ sheet กลับลง collapsed ทันที — จบพักคือกลับไปโฟกัสยกเซตต่อไป
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _collapsedSheetSize,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    // resume active set timer สำหรับเซตถัดไป — _globalTimer เดินตลอดอยู่แล้วไม่เคยหยุด
    _startActiveSetTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // End Workout
  // ─────────────────────────────────────────────────────────────────────────────

  void _endWorkout() {
    HapticFeedback.mediumImpact();
    _globalTimer?.cancel();
    _activeSetTimer?.cancel();
    double vol = 0;
    for (final s in _completedSets) {
      vol += (double.tryParse(s['weight'].toString()) ?? 0) *
             (int.tryParse(s['reps'].toString()) ?? 0);
    }
    setState(() {
      _summaryVolume = vol;
      _showSummary = true;
    });
  }

  // ยืนยันตอนกดบันทึกจริงจากหน้าสรุปผล (ไม่ใช่ตอนกดปุ่มหยุดสีแดงอีกต่อไป) — กันกดพลาด
  // ตรงจุดที่ข้อมูลจะถูกเขียนลงจริง แทนที่จะถามตั้งแต่กลางเซต
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
    if (confirm) {
      setState(() => _showSummary = false);
      await _saveWorkoutToApi();
    }
  }

  // ปิดสรุปแล้วกลับไปฝึกต่อ — ต้อง restart _globalTimer/_activeSetTimer ที่ถูก cancel
  // ไปตอน _endWorkout() ไม่งั้นนาฬิกา session ค้างตายและเซตถัดไปจะไม่มี active_seconds
  void _resumeWorkout() {
    setState(() => _showSummary = false);
    _startGlobalTimer();
  }

  Widget _buildSummaryOverlay() {
    const Color green = Color(0xFF2BEE8C);

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.95),
        child: SafeArea(
          child: Column(
            children: [

              // ── Header ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _resumeWorkout,
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

              // ── Content ────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // title
                      const Text('สรุปผลการฝึก',
                          style: TextStyle(color: Colors.white70, fontSize: 13,
                              fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      Text(widget.exerciseName,
                          style: const TextStyle(color: Colors.white, fontSize: 24,
                              fontWeight: FontWeight.w800)),

                      const SizedBox(height: 28),

                      // ── stat row ───────────────────────────────────────
                      Row(
                        children: [
                          _statBox(
                            icon: Icons.fitness_center_rounded,
                            label: 'เซต',
                            value: '${_completedSets.length}',
                            color: green,
                          ),
                          const SizedBox(width: 12),
                          _statBox(
                            icon: Icons.timer_rounded,
                            label: 'เวลาฝึก',
                            value: _formatTimeSummary(_globalSeconds),
                            color: const Color(0xFF64B5F6),
                          ),
                          const SizedBox(width: 12),
                          _statBox(
                            icon: Icons.bar_chart_rounded,
                            label: 'Volume',
                            value: '${_summaryVolume.round()} กก.',
                            color: const Color(0xFFFFB74D),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // ── set breakdown ─────────────────────────────────
                      if (_completedSets.isNotEmpty) ...[
                        const Text('รายละเอียดแต่ละเซต',
                            style: TextStyle(color: Colors.white70, fontSize: 13,
                                fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: _completedSets.asMap().entries.map((e) {
                              final i = e.key;
                              final s = e.value;
                              final isLast = i == _completedSets.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                decoration: BoxDecoration(
                                  border: isLast ? null : Border(
                                    bottom: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        color: green.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text('${i + 1}',
                                            style: const TextStyle(
                                                color: green, fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text('${s['reps']} ครั้ง',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 15,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    Text('${s['weight']} กก.',
                                        style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.6),
                                            fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${((double.tryParse(s['weight'].toString()) ?? 0) * (int.tryParse(s['reps'].toString()) ?? 0)).round()} กก.',
                                      style: const TextStyle(
                                          color: green, fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ] else
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Text('ไม่มีข้อมูลการฝึก',
                                style: TextStyle(color: Colors.white38, fontSize: 14)),
                          ),
                        ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Actions ───────────────────────────────────────────────
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('บันทึกการฝึก',
                            style: TextStyle(color: Colors.black, fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _resumeWorkout,
                      child: const Text('ฝึกต่อ',
                          style: TextStyle(color: Colors.white54, fontSize: 14)),
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

  Widget _statBox({required IconData icon, required String label,
      required String value, required Color color}) {
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
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _formatTimeSummary(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _saveWorkoutToApi() async {
    if (_completedSets.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final today = DateTime.now().toIso8601String().split('T').first;

    // ท่านี้มาจากตารางฝึกอยู่แล้ว (widget.wschId ติดมาจาก schedule view) — ใช้ตรงๆ
    // ห้ามเรียก createSchedule ซ้ำ ไม่งั้นได้แถวขยะใน workout_schedules เพิ่มทุกครั้งที่บันทึกผล
    int? scheduleId = widget.wschId;

    // ad-hoc path: ท่าที่ไม่ได้มาจากแผน (ไม่มี wschId ติดมา) — ต้องสร้าง schedule ใหม่เอง
    // ปัจจุบันไม่มีจุดเรียกจริงในแอป (ทุกทางเข้าไปหน้านี้มาจาก schedule view ที่มี wschId เสมอ)
    // เก็บไว้กันไว้เผื่ออนาคตมีปุ่ม "log ท่านอกแผน"
    if (scheduleId == null && widget.planId != null) {
      final schedResult = await WorkoutService.to.createSchedule({
        'wsch_date': today,
        // wpt_id/mwp_id แยกคอลัมน์กัน mutually exclusive — ต้องสลับ key ตาม isCustomPlan
        if (widget.isCustomPlan) 'mwp_id': widget.planId else 'plan_id': widget.planId,
        'wet_id': widget.exerciseId,
      });
      scheduleId = schedResult['wsch_id'] as int?;

      // สร้างไม่สำเร็จ → บล็อกตรงนี้เลย ไม่เดา schedule ที่มีอยู่จาก wsch_date เพราะ
      // wsch_date คือแค่วันที่สร้างแถว ไม่ใช่วันฝึก (wsch_day_number เป็นคีย์วันฝึกตัวเดียว)
      if (scheduleId == null) {
        if (mounted) {
          showAppAlert(context, schedResult['message'] as String? ?? 'ไม่สามารถสร้างตารางการฝึกได้ กรุณาลองใหม่', type: AppAlertType.error);
        }
        return;
      }
    }

    int successCount = 0;
    int failCount = 0;
    String? lastError;

    // (2026-08-22) ฐานเวลาคำนวณแคลอรี่เปลี่ยนจาก "ออกแรงต่อเซต" เป็น "ทั้งเซสชัน (รวมพัก) หารเฉลี่ย
    // เท่ากันทุกเซ็ต" ตามนิยาม METs ของ 2024 Adult Compendium of Physical Activities (ค่าเฉลี่ยทั้งรอบ
    // รวมพักแล้ว ไม่ใช่ขณะออกแรงล้วน) — _globalSeconds เดินต่อเนื่องไม่หยุดตอนพักอยู่แล้ว (ดู _startRest)
    // และหยุดนิ่งตั้งแต่ _endWorkout() ก่อนหน้าจอสรุปจะโชว์ จึงเป็นเวลาเซสชันทั้งหมดพอดี ไม่ต้องจับเวลาใหม่
    // หารด้วยจำนวนเซ็ตที่จะบันทึกจริง (reps>0) ไม่ใช่ _completedSets.length ดิบ กัน mismatch ถ้ามีเซ็ต
    // reps=0 ถูกข้ามทิ้ง — ไม่ได้อ้างว่ารู้พลังงานรายเซ็ตจริง แค่กระจายค่าเฉลี่ยทั้งเซสชันเท่าๆ กัน
    final validSets = _completedSets.where((s) => (int.tryParse(s['reps'].toString()) ?? 0) > 0).toList();
    final int perSetSeconds = validSets.isEmpty ? 0 : (_globalSeconds / validSets.length).round();

    for (final s in validSets) {
      final reps = int.tryParse(s['reps'].toString()) ?? 0;
      final payload = <String, dynamic>{
        'date': today,
        'wet_id': widget.exerciseId,
        if (scheduleId != null) 'wsch_id': scheduleId,
        'wtrs_set_no': s['set'],
        'wtrs_reps': reps,
        'wtrs_weight': double.tryParse(s['weight'].toString()) ?? 0.0,
        'wtrs_duration': perSetSeconds,
      };
      final result = await WorkoutService.to.saveWorkoutResult(payload);
      if (result['success'] == true) {
        successCount++;
      } else {
        failCount++;
        lastError = result['message'] as String?;
      }
    }

    if (!mounted) return;
    final String message;
    final AppAlertType type;
    if (failCount == 0) {
      // Volume/Estimated 1RM คำนวณแสดงผลอย่างเดียวตามสูตรบทที่ 2 — ไม่บันทึกลง DB
      double volume = 0;
      double best1RM = 0;
      for (final s in _completedSets) {
        final reps = int.tryParse(s['reps'].toString()) ?? 0;
        if (reps <= 0) continue;
        final weight = double.tryParse(s['weight'].toString()) ?? 0.0;
        volume += weight * reps;
        final e1RM = weight * (1 + reps / 30);
        if (e1RM > best1RM) best1RM = e1RM;
      }
      message = 'บันทึกแล้ว • Volume ${volume.round()} กก. • 1RM โดยประมาณ ${best1RM.round()} กก.';
      type = AppAlertType.success;
    } else if (successCount == 0) {
      message = 'บันทึกไม่สำเร็จ${lastError != null ? ": $lastError" : " กรุณาลองใหม่"}';
      type = AppAlertType.error;
    } else {
      message = 'บันทึกสำเร็จ $successCount เซต ไม่สำเร็จ $failCount เซต${lastError != null ? " ($lastError)" : ""}';
      type = AppAlertType.warning;
    }
    showAppAlert(context, message, type: type);
    // ป็อปกลับเฉพาะตอนไม่มีเซตไหน fail เลย — ถ้ามี fail ให้ user เห็น alert ค้างอยู่ก่อน
    // แล้วเลือกเองว่าจะลองใหม่หรือออก ไม่ปิดหน้าจอปิดบังว่ามีข้อมูลตกหล่น
    if (failCount == 0) {
      Navigator.pop(context);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _confirmExit() async {
    final confirm = await showAppConfirmDialog(
      context,
      icon: Icons.exit_to_app_rounded,
      title: 'ออกจากการฝึก?',
      content: 'set ที่บันทึกแล้วจะยังอยู่\nแต่ set ที่ยังไม่ได้กดบันทึกจะหาย',
      confirmLabel: 'ออก',
      cancelLabel: 'ฝึกต่อ',
    );
    if (confirm && mounted) Navigator.pop(context);
  }

  String _formatTime(int totalSeconds) {
    final int h = totalSeconds ~/ 3600;
    final int m = (totalSeconds % 3600) ~/ 60;
    final int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')} : ${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
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
          // 1. วิดีโอ/ภาพพื้นหลัง — เต็มจอเสมอ (Positioned.fill) ไม่มีช่องว่างเทา
          // ระหว่างภาพกับ sheet ไม่ว่า sheet จะหดหรือยืดแค่ไหน
          _buildHeaderImage(),

          // 1a. หรี่พื้นหลังตาม extent จริงของ sheet — ยืดขึ้นเท่าไหร่ พื้นหลังมืดลงเท่านั้น
          // (มืดสุด ~60% ตอน sheet ยืดเต็ม _expandedSheetSize) ขับด้วย _sheetT แบบเรียลไทม์
          _buildDimOverlay(),

          // 1b. Sheet เลื่อนขึ้น-ลงสไตล์ YouTube Music — หด=โฟกัสวิดีโอ/นาฬิกา, ยืด=โฟกัสตาราง
          ExpandableSessionSheet(
            controller: _sheetController,
            collapsedSize: _collapsedSheetSize,
            expandedSize: _expandedSheetSize,
            header: _buildExerciseHeaderRow(),
            bodyBuilder: (context, scrollController) => _buildWorkoutContent(scrollController),
            footer: _buildBottomControls(),
          ),

          // 2. ปุ่มย้อนกลับ (ด้านบนซ้าย — จะถูก overlay ทับตอนพัก)
          Positioned(
            left: 20,
            top: MediaQuery.of(context).padding.top + 15,
            child: AppBackButton(onTap: _confirmExit),
          ),

          // 2b. นาฬิกามุมขวาบน — โผล่ขึ้นมาแทนนาฬิกาที่ footer ตอน sheet ยืดขึ้น (morph)
          _buildCornerTimer(),

          // 2c. แจ้งเตือนพัก ลอยกลางบนสุดของจอสไตล์ One UI
          _buildRestAlertBanner(),

          // 3. Summary Overlay
          if (_showSummary) _buildSummaryOverlay(),

          // 4. Pre-Countdown Overlay
          if (_isCountingDown) _buildPreCountdownOverlay(),
        ],
      ),
    ),
    );
  }

  // ── Header Image ─────────────────────────────────────────────────────────────

  // ── Header Image ปรับปรุงตามภาพต้นฉบับ ─────────────────────────────────────────────

  Widget _buildHeaderImage() {
    final bool showVideo = _videoController != null && _videoController!.value.isInitialized;

    // crop-to-fill (BoxFit.cover) แทน AspectRatio+Center เดิม — กันแถบดำ letterbox
    // บน-ล่าง/ซ้าย-ขวา, Transform.scale overscan เล็กน้อยกันขอบเบลอของคลิปต้นฉบับ
    // (pattern เดียวกับ core/widgets/loop_video_header.dart)
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
                child: const Center(child: Icon(Icons.fitness_center, size: 80, color: Colors.white24)),
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
  // ชั้นสีดำโปร่งใสระหว่างพื้นหลังกับ sheet — opacity ผูกกับ _sheetT ตรงๆ (real-time
  // ตาม extent จริงจาก DraggableScrollableController) ไม่ต้อง animate เอง ลากมือขึ้น/ลง
  // ความมืดไล่ตามนิ้วทันที ไม่กินการแตะเพราะ IgnorePointer (ด้านล่าง sheet อยู่แล้วไม่มีอะไรให้กด)
  Widget _buildDimOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('bgDimOverlay'),
          color: Colors.black.withValues(alpha: _sheetT * 0.6),
        ),
      ),
    );
  }
  // ── Workout Content ───────────────────────────────────────────────────────────
  // SingleChildScrollView ธรรมดา — ต้องผูก scrollController ตรงนี้เท่านั้นสำหรับ
  // กลไก "ลากเพื่อรีไซส์" ของ DraggableScrollableSheet (ห้ามใช้ CustomScrollView +
  // SliverPersistentHeader(pinned:true) — ยืนยันด้วย widget test ว่าทำให้ sheet
  // ค้างลากไม่ได้เลยตอน viewport หดเล็กมาก ดูรายละเอียดที่ ExpandableSessionSheet)
  // ตารางเซตจึงไม่ sticky แต่จะเห็นได้ตอน sheet ยืดขึ้นเป็นหลัก — นาฬิกาย้ายไปมุมขวาบน
  // แทน (ดู _buildCornerTimer)
  //
  // สองสถานะเนื้อหาไม่เหมือนกัน: ปัดขึ้นเองตอนไม่ได้พัก (_isResting == false) = โหมด
  // "ดูผลย้อนหลัง" อย่างเดียว โชว์ตารางเซตที่บันทึกแล้ว หรือ empty state ถ้ายังไม่มี —
  // ไม่มีช่องกรอก ต่อเมื่อกดปุ่มพักจริงเท่านั้น (_isResting == true) ถึงจะเห็นฟอร์มกรอก
  Widget _buildWorkoutContent(ScrollController scrollController) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        children: _isResting
            ? [
                _buildLogInputCard(),
                if (_completedSets.isNotEmpty) _buildSetsTable(),
              ]
            : [
                if (_completedSets.isNotEmpty) _buildSetsTable() else _buildEmptySetsState(),
              ],
      ),
    );
  }

  // ── Empty Sets State ──────────────────────────────────────────────────────────
  // โชว์ตอนปัดขึ้นเองดูผลย้อนหลัง (ไม่ได้พัก) แต่ยังไม่มีเซตไหนบันทึกเลย
  Widget _buildEmptySetsState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 40),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text('ยังไม่มีผลการฝึก',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Sets Table ────────────────────────────────────────────────────────────────
  // กรอบเดียว (ไม่ใช่การ์ดขาวแยกทุกแถวเหมือนเดิม) — header กับแถวข้อมูลใช้ column
  // width ชุดเดียวกัน (42 เซ็ทที่ + Expanded น้ำหนัก + 70 จำนวนครั้ง) จึงตรงคอลัมน์เป๊ะ
  // ลำดับ น้ำหนัก→ครั้ง (ไม่ใช่ครั้ง→น้ำหนัก) ให้ตรงกับฟอร์มกรอกใน _buildLogInputCard
  // และรูปแบบ "80 กก. × 10 ครั้ง" ที่ใช้อยู่แล้วในหน้าประวัติ (weight_training_detail_view)
  static const double _setNoColWidth = 42;
  static const double _repsColWidth = 70;
  static const double _colGap = 14; // ระยะห่างเท่ากันทั้งสองช่วง เซ็ทที่<->น้ำหนัก<->จำนวนครั้ง

  Widget _buildSetsTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: const [
                  SizedBox(
                    width: _setNoColWidth,
                    child: Text('เซ็ทที่',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  SizedBox(width: _colGap),
                  Expanded(
                    child: Text('น้ำหนัก (กก.)',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  SizedBox(width: _colGap),
                  SizedBox(
                    width: _repsColWidth,
                    child: Text('จำนวนครั้ง',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
            ..._completedSets.asMap().entries.map((e) {
              final isLast = e.key == _completedSets.length - 1;
              return _buildSetRow(e.value, isLast);
            }),
          ],
        ),
      ),
    );
  }

  // ── Log Input Card (กรอกน้ำหนัก/ครั้ง) ────────────────────────────────────────
  // โชว์เฉพาะตอน resting เท่านั้น — ไม่มีปุ่มบันทึกในตัวเอง (เอาปุ่ม "เพิ่มเซต" ออกแล้ว
  // เพราะซ้ำซ้อนกับปุ่ม "จบการพัก" ที่ footer) กด "จบการพัก" ที่ footer เพื่อบันทึก
  // (ถ้ากรอกครบทั้งสองช่อง) + จบการพักจริงในทีเดียว (ดู _finishRest)
  Widget _buildLogInputCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildLightInput('น้ำหนัก (กก.)', _weightController, allowDecimal: true),
            const SizedBox(width: 16),
            const Text('×',
                style: TextStyle(color: Colors.black26, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(width: 16),
            _buildLightInput('จำนวนครั้ง', _repsController),
          ],
        ),
      ),
    );
  }

  Widget _buildLightInput(String label, TextEditingController controller, {bool allowDecimal = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          width: 105,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            keyboardType: allowDecimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
            inputFormatters: allowDecimal
                ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
                : [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87, fontSize: 32, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '-',
              hintStyle: TextStyle(color: Colors.black26),
            ),
          ),
        ),
      ],
    );
  }

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
                decoration: const BoxDecoration(
                  color: Color(0xFF00F28A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.exerciseName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F28A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _exerciseLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00C070),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }

  Widget _buildSetRow(Map<String, dynamic> item, bool isLast) {
    const green = Color(0xFF2BEE8C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _setNoColWidth,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: green.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Center(
                child: Text('${item['set']}',
                    style: const TextStyle(color: Color(0xFF00C070), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: _colGap),
          Expanded(
            child: Text('${item['weight']} กก.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
          const SizedBox(width: _colGap),
          SizedBox(
            width: _repsColWidth,
            child: Text('${item['reps']} ครั้ง',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  // ── Corner Timer (Expanded/Logging mode) ─────────────────────────────────────
  // Crossfade กับนาฬิกาที่ footer ตาม _sheetT แบบเรียลไทม์: t=0 นาฬิกาอยู่ footer
  // เต็มโทน, t=1 นาฬิกาย้ายมาโผล่มุมขวาบนแบบเล็กลง — ตรงตาม spec "morph ไปมุม"
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

  // ── Bottom Controls ───────────────────────────────────────────────────────────

  Color get _restTimerColor =>
      _isTimerHighlighted ? const Color(0xFF00FF6E) : const Color(0xFF2BEE8C);

  // แถวเดียว: ปกติ = นาฬิกาฝึก + ปุ่มหยุดพัก/จบการฝึก, ตอนพัก = morph เป็นนาฬิกาพัก
  // (สีเขียวมิ้นท์) + ปุ่มจบการพัก — คือทุกอย่างที่โชว์ตอน sheet หด
  //
  // alert bubble ย้ายออกจาก footer ไปเป็น banner ลอยกลางบนสุดของจอแล้ว (ดู
  // _buildRestAlertBanner ใน build()) ไม่กินพื้นที่เลย์เอาต์ของ footer เลย จึงไม่มีปัญหา
  // bottom overflow ที่เคยเกิดตอน alert โผล่ระหว่าง sheet หด
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
  // แจ้งเตือนพักลอยกลางบนสุดของจอ สไลด์ลง+เฟดเข้าเหมือน heads-up notification ของ
  // One UI ข้อความสั้นแถวเดียวอ่านง่าย (maxLines:1 กันล้น) — pattern เดียวกันทั้งหน้า
  // ฝึกเวทและคาร์ดิโอ (ดู cardio_activity_exercise_view) มีแสง glow สีเดียวกับนาฬิกาพัก
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

  // ปุ่ม "จบการพัก" ยืดออกด้านขวา + เปลี่ยนเป็น "จบการพักและบันทึก" (พื้นเขียวทึบ) ทันทีที่
  // กรอกครบทั้งน้ำหนัก+จำนวนครั้ง — ให้ผู้ใช้รู้ตัวว่ากดแล้วจะบันทึกเซตด้วย ไม่ใช่แค่จบพักเฉยๆ
  // (กรอกไม่ครบ/ว่าง ยังเป็นปุ่มเดิม กดได้เหมือนเดิมแค่ไม่บันทึก — ดู _finishRest)
  Widget _buildRestingRow() {
    final canSave = _canSaveSet;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.self_improvement_rounded, color: _restTimerColor, size: 22),
        const SizedBox(width: 10),
        WorkoutTimer(seconds: _restSeconds, fontSize: 24, color: _restTimerColor, fontWeight: FontWeight.w800),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _finishRest,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: canSave ? 24 : 18, vertical: 10),
            decoration: BoxDecoration(
              color: canSave ? _restTimerColor : _restTimerColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              boxShadow: canSave
                  ? [BoxShadow(color: _restTimerColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canSave) ...[
                  const Icon(Icons.check_circle_rounded, color: Colors.black, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(
                  canSave ? 'จบการพักและบันทึก' : 'จบการพัก',
                  style: TextStyle(
                    color: canSave ? Colors.black : _restTimerColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
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
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
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
              style: const TextStyle(
                fontSize: 150,
                fontWeight: FontWeight.w900,
                color: Color(0xFF2BEE8C),
              ),
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

// AppAlert — แจ้งเตือนมาตรฐานเดียวของทั้งแอป (ฝั่งสมาชิกและแอดมิน)
// สไตล์อ้างอิงจากแจ้งเตือนระบบของ Samsung One UI: การ์ดเล็กกึ่งกลางด้านบนจอ
// ขนาดพอดีกับข้อความ (ไม่ยืดเต็มจอ), ค้างตามความยาวข้อความ, ปัดขึ้นเพื่อปิดก่อนเวลาได้
//
// หมายเหตุ: ใช้สำหรับแจ้งสถานะการทำงาน (สำเร็จ/ผิดพลาด/คำเตือน/ข้อมูลทั่วไป) เท่านั้น
// ข้อผิดพลาดจากการกรอกฟอร์ม (validation) ให้ใช้ errorText ในช่องกรอกโดยตรง ไม่ใช้ตัวนี้
//
// ยังมี showAdminTopToast (แอดมิน > ลบข้อมูลทั่วไป — auto-dismiss ไม่มี undo) ตาม deletion UX matrix
// สีเดียวคือเขียว/สำเร็จเสมอ (ไม่ใช้ขอบแดง) เพราะ action ที่เรียกใช้จริงคือ "ลบสำเร็จ" ล้วนๆ
// ขอบแดงคู่กับไอคอนติ๊กเขียวจะทำให้ผู้ใช้สับสนว่าตกลงพังหรือสำเร็จกันแน่

import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AppAlertType { success, error, warning, info }

// bottom — ใช้เมื่อมีปุ่ม action ที่อยากให้กดถึงง่ายด้วยนิ้วโป้ง (เช่น "ดูตารางฝึก")
// top (ค่าเริ่มต้น) — แจ้งสถานะทั่วไปที่ไม่ต้องกดต่อ
enum AppAlertPosition { top, bottom }

OverlayEntry? _activeAlertEntry;

/// แจ้งเตือนมาตรฐาน — เรียกใช้จุดเดียวทั้งแอป
/// actionLabel/onAction — ใส่คู่กันเพื่อโชว์ปุ่มข้อความท้ายการ์ด (เช่น "ดูตารางฝึก", "ลองใหม่")
void showAppAlert(
  BuildContext context,
  String message, {
  AppAlertType type = AppAlertType.success,
  String? actionLabel,
  VoidCallback? onAction,
  AppAlertPosition position = AppAlertPosition.top,
}) {
  // ปิดอันที่ค้างอยู่ก่อน กันซ้อนทับกันเวลาเรียกติดกันเร็วๆ
  _activeAlertEntry?.remove();
  _activeAlertEntry = null;

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AppAlertWidget(
      message: message,
      type: type,
      actionLabel: actionLabel,
      position: position,
      onAction: onAction == null
          ? null
          : () {
              entry.remove();
              if (identical(_activeAlertEntry, entry)) _activeAlertEntry = null;
              onAction();
            },
      onDismiss: () {
        entry.remove();
        if (identical(_activeAlertEntry, entry)) _activeAlertEntry = null;
      },
    ),
  );
  _activeAlertEntry = entry;
  overlay.insert(entry);
}

/// Backward-compatible shim ของชื่อเดิม — isError=true → error, false → success
void showTopFlash(BuildContext context, String message, {bool isError = false}) {
  showAppAlert(context, message, type: isError ? AppAlertType.error : AppAlertType.success);
}

/// แอดมิน > ลบข้อมูลทั่วไป — กล่องเทาอ่อน ขอบแดง ไอคอนติ๊กถูก ไม่มีปุ่ม Undo หายเองใน 3-5 วิ
void showAdminTopToast(BuildContext context, String message) {
  _activeAlertEntry?.remove();
  _activeAlertEntry = null;

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AdminToastWidget(
      message: message,
      sticky: false,
      onDismiss: () {
        entry.remove();
        if (identical(_activeAlertEntry, entry)) _activeAlertEntry = null;
      },
    ),
  );
  _activeAlertEntry = entry;
  overlay.insert(entry);
}

class _AppAlertWidget extends StatefulWidget {
  final String message;
  final AppAlertType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppAlertPosition position;
  final VoidCallback onDismiss;

  const _AppAlertWidget({
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
    this.position = AppAlertPosition.top,
    required this.onDismiss,
  });

  @override
  State<_AppAlertWidget> createState() => _AppAlertWidgetState();
}

class _AppAlertWidgetState extends State<_AppAlertWidget>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  AnimationController? _particleCtrl;
  bool _dismissed = false;

  bool get _isSuccess => widget.type == AppAlertType.success;

  Color get _color {
    switch (widget.type) {
      case AppAlertType.success: return AppColors.alertSuccess;
      case AppAlertType.error:   return AppColors.alertError;
      case AppAlertType.warning: return AppColors.alertWarning;
      case AppAlertType.info:    return AppColors.alertInfo;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case AppAlertType.success: return Icons.check_circle_rounded;
      case AppAlertType.error:   return Icons.cancel_rounded;
      case AppAlertType.warning: return Icons.warning_rounded;
      case AppAlertType.info:    return Icons.info_rounded;
    }
  }

  // ทุกประเภทพื้นเข้มพอสำหรับตัวหนังสือขาวอยู่แล้ว (ดูค่าสีใน AppColors.alertXxx)
  Color get _fgColor => Colors.white;

  // ค้างนานตามความยาวข้อความ — สั้นก็หายเร็ว ยาวก็อ่านทัน (จำกัดขอบเขตไว้ไม่ให้สั้น/นานเกินไป)
  // มีปุ่ม action → ยืดเวลาขั้นต่ำเพิ่ม ให้มีจังหวะพอกดทัน
  Duration get _visibleDuration {
    final min = widget.onAction != null ? 3200 : 1800;
    final ms = (1600 + widget.message.length * 35).clamp(min, 4200);
    return Duration(milliseconds: ms);
  }

  @override
  void initState() {
    super.initState();
    final beginOffset = widget.position == AppAlertPosition.bottom
        ? const Offset(0, 1)
        : const Offset(0, -1);
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _slide = Tween<Offset>(begin: beginOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    // การ์ดสำเร็จเด้งเบาๆ ตอนเข้า (overshoot แล้วนิ่ง) ส่วนประเภทอื่นเข้าแบบปกติ
    _scale = _isSuccess
        ? TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.04)
                .chain(CurveTween(curve: Curves.easeOut)), weight: 65),
            TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0)
                .chain(CurveTween(curve: Curves.easeOut)), weight: 35),
          ]).animate(_ctrl)
        : const AlwaysStoppedAnimation(1.0);

    _ctrl.forward();

    if (_isSuccess) {
      _particleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..forward();
    }

    Future.delayed(_visibleDuration, _dismiss);
  }

  void _dismiss() async {
    if (!mounted || _dismissed) return;
    _dismissed = true;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _particleCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBottom = widget.position == AppAlertPosition.bottom;
    final maxWidth = MediaQuery.of(context).size.width * 0.86;

    return Positioned(
      top: isBottom ? null : MediaQuery.of(context).padding.top + 8,
      bottom: isBottom ? MediaQuery.of(context).padding.bottom + 20 : null,
      left: 0,
      right: 0,
      child: Align(
        alignment: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                final v = details.primaryVelocity;
                if (v == null) return;
                // ปัดออกไปทางเดียวกับที่การ์ดโผล่มา — บนสุดปัดขึ้น, ล่างสุดปัดลง
                if (isBottom ? v > 100 : v < -100) _dismiss();
              },
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (_particleCtrl != null)
                      AnimatedBuilder(
                        animation: _particleCtrl!,
                        builder: (ctx, _) => CustomPaint(
                          size: const Size(160, 60),
                          painter: _ParticleBurstPainter(
                            progress: _particleCtrl!.value,
                            color: _color,
                          ),
                        ),
                      ),
                    ScaleTransition(
                      scale: _scale,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: IntrinsicWidth(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              color: _color,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(_icon, color: _fgColor, size: 16),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    widget.message,
                                    style: TextStyle(color: _fgColor, fontSize: 13, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.actionLabel != null && widget.onAction != null) ...[
                                  const SizedBox(width: 14),
                                  GestureDetector(
                                    onTap: widget.onAction,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        widget.actionLabel!,
                                        style: TextStyle(
                                          color: _fgColor,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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
}

/// เอฟเฟกต์พลุจุดเล็กๆ กระจายออกจากกึ่งกลางแล้วจางหาย — ใช้ตอนแจ้งเตือนสำเร็จเท่านั้น
class _ParticleBurstPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  _ParticleBurstPainter({required this.progress, required this.color});

  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final travel = Curves.easeOut.transform(progress);

    for (var i = 0; i < _count; i++) {
      final angle = (2 * pi / _count) * i;
      final dist = 26 * travel;
      final pos = center + Offset(cos(angle), sin(angle)) * dist;
      final paint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 2.2 * (1 - progress * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleBurstPainter oldDelegate) => oldDelegate.progress != progress;
}

/// การ์ดโทนเทาอ่อน/ขอบเขียว สำหรับแอดมิน — auto-dismiss (general) หรือ sticky (critical, ต้องกด X)
class _AdminToastWidget extends StatefulWidget {
  final String message;
  final bool sticky;
  final VoidCallback onDismiss;

  const _AdminToastWidget({
    required this.message,
    required this.sticky,
    required this.onDismiss,
  });

  @override
  State<_AdminToastWidget> createState() => _AdminToastWidgetState();
}

class _AdminToastWidgetState extends State<_AdminToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    if (!widget.sticky) {
      Future.delayed(const Duration(milliseconds: 4000), _dismiss);
    }
  }

  void _dismiss() async {
    if (!mounted || _dismissed) return;
    _dismissed = true;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    final maxWidth = MediaQuery.of(context).size.width * 0.9;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: IntrinsicWidth(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.alertSuccess.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.alertSuccess, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(color: AppColors.textDark, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.sticky) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _dismiss,
                            child: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Floating Snackbar พร้อมปุ่ม "เลิกทำ" — ใช้กับ User > ลบรายการข้อมูลประจำวัน (อาหาร/ผลออกกำลังกาย)
// ลอยเหนือเมนูด้านล่าง กระจกเบลอสีเทาเข้มโปร่งแสง 65% — ตั้งใจให้สีต่างจากการ์ดขาวรอบข้าง
// (ต่างจาก navbar ที่เป็นกระจกขาว) เพื่อให้เด่นและอ่านง่ายเมื่อลอยทับเนื้อหา
// Motion: slide up เด้งเบาๆ ตอนมา / fade + slide down ตอนหายเอง
// ปัดซ้าย-ขวาปิดได้ก่อนหมดเวลา (ทิศทางเดียวกับท่าปัดลบการ์ดที่เหลือทั้งแอพ — SwipeDeleteItem) ปัดแล้ว
// ถือว่ายืนยันการลบทันที (เหมือนปล่อยให้หมดเวลาเอง) ไม่ใช่ยกเลิกการลบ

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

OverlayEntry? _activeUndoEntry;
// _expire() ของ _UndoSnackbarWidgetState ตัวที่กำลังลอยอยู่ (ถ้ามี) — ทั้ง commitPendingUndo() และ
// showUndoSnackbar() ตัวถัดไปเรียกช่องทางเดียวกันนี้เท่านั้นตอนต้องการ "commit ทันที" (ดู
// _forceCommitCurrent()) ห้ามมีช่องทางที่สองที่เรียก onExpire ดิบๆ ตรงๆ อีก — เดิมมี 2 ทางแยกกัน
// (ทางนี้ vs onExpire ดิบที่เก็บแยกไว้ใน _activeUndoExpire) ถ้าสองทางชนกันในช่วงเวลาไล่เลี่ยกัน
// (เช่นสลับหน้าเร็วมาก แล้วปัดลบรายการใหม่ในหน้าถัดไปทันทีระหว่างที่แอนิเมชันปิดตัวเก่ายังไม่จบ)
// onExpire ตัวเดิมจะถูกยิงซ้ำสอง (ลบซ้ำ/error หลอก) และ entry.remove() อาจถูกเรียกซ้ำจน assert พัง
VoidCallback? _activeForceExpire;

// ให้หน้าที่เปิด undo snackbar ได้ subscribe ด้วย RouteAware เพื่อรู้ตอนถูกหน้าอื่นมาบัง
// (didPushNext) — ลงทะเบียนที่ GetMaterialApp.navigatorObservers ใน main.dart
final RouteObserver<PageRoute> undoRouteObserver = RouteObserver<PageRoute>();

void showUndoSnackbar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  required VoidCallback onExpire,
  Duration duration = const Duration(seconds: 4),
}) {
  // มี undo ของรายการก่อนหน้าค้างอยู่ (เช่นปัดลบรายการถัดไปเร็วก่อนหมดเวลา หรือสลับหน้าไว) → commit
  // การลบเดิมทันทีผ่านช่องทางเดียวกับ commitPendingUndo() เสมอ เคลียร์ตัวแปร global "ก่อน" เรียก
  // เสมอ (ไม่ใช่หลังแอนิเมชันจบ) กัน entry ถัดไปมาเห็นค่าเก่าค้างระหว่างรอแล้วยิงซ้ำ
  _forceCommitCurrent();

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  // กัน onUndo/onExpire ของ entry นี้ถูกเรียกซ้ำสอง เผื่อ 2 เส้นทาง (หมดเวลาเอง vs ถูก force commit
  // จากรายการถัดไป/ออกจากหน้า) ชนกันไล่เลี่ยกัน — ผูกกับ entry นี้โดยเฉพาะ ไม่พึ่ง global ที่อาจถูก
  // เปลี่ยนไปชี้ entry ใหม่ไปแล้วตอนนั้น
  var resolved = false;
  void resolve(VoidCallback cb) {
    if (resolved) return;
    resolved = true;
    entry.remove();
    if (identical(_activeUndoEntry, entry)) {
      _activeUndoEntry = null;
      _activeForceExpire = null;
    }
    cb();
  }

  entry = OverlayEntry(
    builder: (ctx) => _UndoSnackbarWidget(
      message: message,
      duration: duration,
      onUndo: () => resolve(onUndo),
      onExpire: () => resolve(onExpire),
      registerForceExpire: (fn) => _activeForceExpire = fn,
    ),
  );
  _activeUndoEntry = entry;
  overlay.insert(entry);
}

// เรียกจาก dispose()/didPushNext() ของหน้าที่เปิด swipe-delete ได้ — กัน overlay entry ลอยตาม
// ผู้ใช้ข้ามหน้าไปเรื่อยๆ เพราะมันแทรกอยู่บน Overlay ระดับแอป (ตัวเดียวกับ Navigator ใช้)
// ไม่ผูกกับ route ใดๆ เลย ปิดหน้านี้ไปแล้วก็ยังลอยค้างทับหน้าถัดไปอยู่ดีถ้าไม่มีอะไรมาสั่งจบให้ทันที
void commitPendingUndo() => _forceCommitCurrent();

// จุดเดียวที่ "commit รายการที่ค้างอยู่ทันที" ไม่ว่าจะถูกเรียกจาก commitPendingUndo() (ออกจากหน้า/
// ถูกหน้าอื่นบัง) หรือจาก showUndoSnackbar() (มีรายการถัดไปมาแทรกก่อนหมดเวลา) — เคลียร์ global แบบ
// synchronous ก่อนเรียก _expire() เสมอ กันเรียกซ้ำเป็นรอบสองระหว่างที่แอนิเมชันปิดตัวเดิมยังไม่จบ
// (_expire() เป็น async รอ 260ms ก่อนยิง onExpire จริง — ถ้าไม่เคลียร์ global ก่อน ช่วงนี้จะยังมีค่า
// ค้างให้ตัวถัดไปเห็นแล้วเรียกซ้ำได้) ตัว entry เดิมมี resolved guard ของตัวเองอยู่แล้วด้วย เป็นการ
// กันซ้อนสองชั้น
void _forceCommitCurrent() {
  final expire = _activeForceExpire;
  _activeUndoEntry = null;
  _activeForceExpire = null;
  expire?.call();
}

class _UndoSnackbarWidget extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onUndo;
  final VoidCallback onExpire;
  final void Function(VoidCallback triggerExpire) registerForceExpire;

  const _UndoSnackbarWidget({
    required this.message,
    required this.duration,
    required this.onUndo,
    required this.onExpire,
    required this.registerForceExpire,
  });

  @override
  State<_UndoSnackbarWidget> createState() => _UndoSnackbarWidgetState();
}

class _UndoSnackbarWidgetState extends State<_UndoSnackbarWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  final _dismissKey = UniqueKey();
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _slide = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: const Offset(0, 1), end: const Offset(0, -0.06))
          .chain(CurveTween(curve: Curves.easeOut)), weight: 70),
      TweenSequenceItem(tween: Tween(begin: const Offset(0, -0.06), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    ]).animate(_ctrl);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    widget.registerForceExpire(_expire);
    Future.delayed(widget.duration, _expire);
  }

  void _expire() async {
    if (!mounted || _resolved) return;
    _resolved = true;
    await _ctrl.reverse();
    widget.onExpire();
  }

  void _undo() async {
    if (!mounted || _resolved) return;
    _resolved = true;
    await _ctrl.reverse();
    widget.onUndo();
  }

  // ปัดปิดเอง — Dismissible เล่นแอนิเมชันเลื่อนหายของตัวเองอยู่แล้ว ไม่ต้องเล่นซ้ำกับ _ctrl
  // ถือเป็นการยืนยันลบทันที (ผู้ใช้ปัดทิ้งเพราะไม่ต้องการกด "เลิกทำ" แล้ว)
  void _swipeDismiss() {
    if (_resolved) return;
    _resolved = true;
    HapticFeedback.lightImpact();
    widget.onExpire();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 88; // เผื่อพ้น bottom nav
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Dismissible(
            key: _dismissKey,
            direction: DismissDirection.horizontal,
            onDismissed: (_) => _swipeDismiss(),
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF32333A).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _undo,
                          child: const Text(
                            'เลิกทำ',
                            style: TextStyle(color: AppColors.primaryGreen, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
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

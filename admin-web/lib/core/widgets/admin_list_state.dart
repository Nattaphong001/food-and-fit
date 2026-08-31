// AdminListStateView — 4 สถานะบังคับของหน้าจัดการข้อมูล Admin แบบเดียวกันทุกหน้า:
// loading / empty / error / noResult (ค้นหาไม่เจอ ต่างจาก empty เพราะมีปุ่มล้างตัวกรองแทนปุ่มเพิ่ม)
//
// loading = shimmer skeleton (บรีฟรอบ 3 ข้อ 1) แทนจอว่าง/แถบเทาทึบเดิม — มี 2 รูปทรงให้เลือกผ่าน
// AdminSkeletonVariant ให้ตรงกับ layout จริงของแต่ละหน้า (การ์ดกริด หรือ ตาราง)

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum AdminListState { loading, empty, error, noResult }

enum AdminSkeletonVariant { rows, cards, table }

// ดีเลย์ก่อนโชว์ loading indicator — กัน flicker ตอน API ตอบเร็วกว่านี้ (< 0.1 วิ ตามหลัก Nielsen Norman
// ไม่ควรโชว์ loading indicator เลย เพราะ user รู้สึกว่าเป็น instant อยู่แล้ว)
// ใช้ร่วมกับ AdminListStateView (skeleton) และ runWithGuardedLoading (modal spinner)
// ใน admin_loading_guard.dart — กฎเดียวกันทั้งระบบ
const kAdminLoadingDelay = Duration(milliseconds: 150);

// คู่กับ kAdminLoadingDelay — พอโชว์ indicator แล้วต้องอยู่อย่างน้อยเท่านี้ก่อนสลับออก
// กัน flicker กรณี API ตอบช้ากว่า delay นิดเดียว (เช่น 160ms) แล้วโผล่แว้บเดียวหาย
const kAdminLoadingMinDisplay = Duration(milliseconds: 300);

class AdminListStateView extends StatefulWidget {
  final AdminListState state;
  final String? emptyMessage;
  final String? errorMessage;
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;
  final VoidCallback? onClearFilter;
  final AdminSkeletonVariant skeletonVariant;

  const AdminListStateView({
    super.key,
    required this.state,
    this.emptyMessage,
    this.errorMessage,
    this.onAdd,
    this.onRetry,
    this.onClearFilter,
    this.skeletonVariant = AdminSkeletonVariant.rows,
  });

  @override
  State<AdminListStateView> createState() => _AdminListStateViewState();
}

class _AdminListStateViewState extends State<AdminListStateView> {
  late AdminListState _effective = widget.state;
  bool _showSkeleton = false;
  DateTime? _shownAt;
  Timer? _delayTimer;
  Timer? _minDisplayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDelay();
  }

  void _scheduleDelay() {
    _delayTimer?.cancel();
    _delayTimer = Timer(kAdminLoadingDelay, () {
      if (mounted && widget.state == AdminListState.loading) {
        setState(() {
          _showSkeleton = true;
          _shownAt = DateTime.now();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AdminListStateView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == oldWidget.state) return;

    if (widget.state == AdminListState.loading) {
      _minDisplayTimer?.cancel();
      _showSkeleton = false;
      _shownAt = null;
      setState(() => _effective = AdminListState.loading);
      _scheduleDelay();
      return;
    }

    _delayTimer?.cancel();
    // skeleton โผล่มาแล้ว ต้องอยู่ให้ครบ _kMinSkeletonDisplay ก่อนสลับออก กัน flicker
    if (_showSkeleton && _shownAt != null) {
      final remaining = kAdminLoadingMinDisplay - DateTime.now().difference(_shownAt!);
      if (remaining > Duration.zero) {
        _minDisplayTimer = Timer(remaining, () {
          if (mounted) setState(() { _effective = widget.state; _showSkeleton = false; });
        });
        return;
      }
    }
    setState(() { _effective = widget.state; _showSkeleton = false; });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _minDisplayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_effective) {
      case AdminListState.loading:
        if (!_showSkeleton) return const SizedBox.shrink();
        return Semantics(
          label: 'กำลังโหลดข้อมูล',
          child: ExcludeSemantics(child: _LoadingSkeleton(variant: widget.skeletonVariant)),
        );
      case AdminListState.empty:
        return _StateBody(
          icon: Icons.inbox_outlined,
          message: widget.emptyMessage ?? 'ยังไม่มีข้อมูล',
          actionLabel: widget.onAdd != null ? 'เพิ่มรายการแรก' : null,
          onAction: widget.onAdd,
        );
      case AdminListState.error:
        return _StateBody(
          icon: Icons.error_outline,
          message: widget.errorMessage ?? 'เกิดข้อผิดพลาด ไม่สามารถโหลดข้อมูลได้',
          actionLabel: widget.onRetry != null ? 'ลองใหม่' : null,
          onAction: widget.onRetry,
          iconColor: AppColors.danger,
        );
      case AdminListState.noResult:
        return _StateBody(
          icon: Icons.search_off,
          message: 'ไม่พบรายการที่ค้นหา',
          actionLabel: widget.onClearFilter != null ? 'ล้างตัวกรอง' : null,
          onAction: widget.onClearFilter,
        );
    }
  }
}

class _StateBody extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  const _StateBody({required this.icon, required this.message, this.actionLabel, this.onAction, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: iconColor ?? AppColors.textDisabled),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.body),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(actionLabel!),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// sweep gradient shimmer — ไม่พึ่ง package เพิ่ม ใช้ AnimationController + ShaderMask ธรรมดา
class AdminShimmer extends StatefulWidget {
  final Widget child;
  const AdminShimmer({super.key, required this.child});

  @override
  State<AdminShimmer> createState() => AdminShimmerState();
}

class AdminShimmerState extends State<AdminShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    if (reduced) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ผู้ใช้ตั้งค่าลดการเคลื่อนไหว (accessibility) — โชว์กล่องสี skeleton นิ่งๆ ไม่ต้อง sweep
    if (_reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              begin: Alignment(-1 + t * 3, 0),
              end: Alignment(t * 3, 0),
              colors: [AppColors.skeletonBase, AppColors.skeletonHighlight, AppColors.skeletonBase],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class AdminSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  const AdminSkeletonBox({super.key, this.width, required this.height, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.skeletonBase, borderRadius: borderRadius ?? BorderRadius.circular(8)),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  final AdminSkeletonVariant variant;
  const _LoadingSkeleton({required this.variant});

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case AdminSkeletonVariant.cards:
        return AdminShimmer(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.95,
            ),
            itemCount: 8,
            itemBuilder: (context, index) => Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: AdminSkeletonBox(height: double.infinity, borderRadius: const BorderRadius.vertical(top: Radius.circular(18)))),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const AdminSkeletonBox(height: 14, width: 120),
                      const SizedBox(height: 8),
                      AdminSkeletonBox(height: 11, width: 80),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        );
      case AdminSkeletonVariant.table:
        return AdminShimmer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: List.generate(7, (index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        const AdminSkeletonBox(width: 32, height: 32, borderRadius: BorderRadius.all(Radius.circular(16))),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: AdminSkeletonBox(height: 14, width: null)),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: AdminSkeletonBox(height: 14, width: null)),
                        const SizedBox(width: 16),
                        Expanded(child: AdminSkeletonBox(height: 14, width: null)),
                      ]),
                    )),
              ),
            ),
          ),
        );
      case AdminSkeletonVariant.rows:
        return AdminShimmer(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.xs),
            itemCount: 6,
            itemBuilder: (context, index) => Container(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              height: 48,
              decoration: BoxDecoration(color: AppColors.skeletonHighlight, borderRadius: BorderRadius.circular(8)),
            ),
          ),
        );
    }
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// navbar แคปซูลลอย กระจกเบลอโปร่งแสงสว่าง (ให้เข้ากับธีมสว่างของแอพ) — ลอยห่างขอบจอทุกด้าน (ไม่ติดขอบ) ทรงสเตเดียมเต็ม
// (รัศมี = ครึ่งความสูง) หน้าอาหาร (index 1) เจาะหลุมโค้งมนกลางขอบบนรับปุ่ม + ที่ยกลอยสูงขึ้น
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _icons = [
    Icons.home_rounded,
    Icons.restaurant_rounded,
    Icons.fitness_center_rounded,
    Icons.bar_chart_rounded,
  ];

  static const double barHeight = 64; // export ไว้ให้หน้าอื่นใช้เว้น bottom padding กันเนื้อหาโดนบัง
  static const double _radius = barHeight / 2; // สเตเดียมเต็ม
  static const double _notchRadius = 34; // รัศมีหลุม รับปุ่ม + (มาตรฐานเส้นผ่านศูนย์กลาง 56)
  static const double raiseOffset = 26; // ยกปุ่ม + และหลุมสูงกว่าขอบบนแคปซูล (ใช้ร่วมกับ MainShell)

  @override
  Widget build(BuildContext context) {
    final hasNotch = currentIndex == 1;

    return SafeArea(
      top: false,
      child: Padding(
        // ลอยห่างขอบจอทุกด้าน ไม่ชิดขอบล่าง/ซ้าย/ขวา
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          // ClipPath ชนิดเดียวเสมอ (ไม่สลับ ClipPath/ClipRRect ไปมา) — ถ้าสลับชนิด widget ตอน
          // เข้า-ออกหน้าอาหาร Flutter จะทุบ subtree เดิมทิ้งแล้วสร้างใหม่ ทำให้ animation ไอเทมเสีย state
          child: ClipPath(
            clipper: _NotchedPillClipper(hasNotch: hasNotch, notchRadius: _notchRadius, raiseOffset: raiseOffset),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                height: barHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    _icons.length,
                    (i) => _NavItem(icon: _icons[i], selected: currentIndex == i, onTap: () => onTap(i)),
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

// พิลล์สเตเดียม — ถ้า hasNotch เจาะหลุมวงกลมกลางขอบบนเพิ่ม (ตัดวงกลมตรงๆ ไม่ปาดมุมเพิ่ม)
class _NotchedPillClipper extends CustomClipper<Path> {
  final bool hasNotch;
  final double notchRadius;
  final double raiseOffset;
  const _NotchedPillClipper({required this.hasNotch, required this.notchRadius, required this.raiseOffset});

  @override
  Path getClip(Size size) {
    final hostRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final pillPath = Path()
      ..addRRect(RRect.fromRectAndRadius(hostRect, Radius.circular(size.height / 2)));
    if (!hasNotch) return pillPath;

    final cx = size.width / 2;
    final cy = -raiseOffset;
    final notch = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: notchRadius));

    return Path.combine(PathOperation.difference, pillPath, notch);
  }

  @override
  bool shouldReclip(covariant _NotchedPillClipper oldClipper) =>
      oldClipper.hasNotch != hasNotch ||
      oldClipper.notchRadius != notchRadius ||
      oldClipper.raiseOffset != raiseOffset;
}

// ไอเทมเมนู 1 ช่อง — ตอนเลือก แคปซูลขยายกว้างขึ้น (54→76) พื้นหลังเขียวจาง (AppColors.primaryGreen) โผล่ขึ้น ไอคอนเปลี่ยนเป็นสีเขียว
class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: selected ? 76 : 54,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          icon,
          size: 26,
          color: selected ? AppColors.primaryGreen : AppColors.textMuted,
        ),
      ),
    );
  }
}

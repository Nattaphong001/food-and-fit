// กล่อง Floating Bar ด้านล่างจอ สรุปจำนวนรายการที่เลือกไว้ (Quick Select multi-select)
// ต้องอยู่ภายใน Stack ของหน้าที่เรียกใช้ (ใช้ Positioned วางลอยเหนือขอบล่าง)

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class FloatingSelectionBar extends StatelessWidget {
  final int count;
  final String confirmLabel;
  final VoidCallback onConfirm;

  const FloatingSelectionBar({
    super.key,
    required this.count,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                child: Text('$count',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('เลือกแล้ว $count รายการ',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
              ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  // theme กลาง (main.dart) ตั้ง minimumSize เป็น Size(double.infinity, 55) ไว้
                  // สำหรับปุ่มเต็มความกว้างทั่วแอป — ปุ่มนี้อยู่ใน Row (ไม่มีความกว้าง bound
                  // ให้ยึด) ต้อง override ทับ ไม่งั้น layout พังทันทีที่ bar นี้โผล่ (infinite width)
                  minimumSize: Size.zero,
                ),
                child: Text(confirmLabel,
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

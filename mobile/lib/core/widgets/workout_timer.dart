import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class WorkoutTimer extends StatelessWidget {
  final int seconds;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;

  const WorkoutTimer({
    super.key,
    required this.seconds,
    this.fontSize = 60, // ขนาดเริ่มต้นที่ออกแบบไว้
    this.color = AppColors.primaryGreen, // สีเขียวหลักตามธีม
    this.fontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    // Logic การจัดการ Format เวลา
    String minutesStr = (seconds / 60).floor().toString().padLeft(2, '0');
    String secondsStr = (seconds % 60).toString().padLeft(2, '0');

    return Text(
      '$minutesStr:$secondsStr',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: 2, // เพิ่มช่องว่างให้ดูสปอร์ต
      ),
    );
  }
}
// widget: ช่องกรอก OTP แบบแยกกล่องรายหลัก
// ทำหน้าที่: แสดงตัวเลข OTP เป็นกล่องแยกทีละหลัก จัดกึ่งกลาง ไฮไลต์กล่องที่กำลังจะพิมพ์
// เบื้องหลังใช้ TextField ตัวเดียวโปร่งใสรับ input จริงทั้งหมด (พิมพ์/ลบ/วางรหัสทั้งชุด)
// เพื่อใช้ระบบจัดการ cursor/backspace/paste ของ Flutter เอง แทนการเดา FocusNode เรียงช่องมือ
// ซึ่งเสี่ยงจับ backspace บนคีย์บอร์ดมือถือไม่ได้ครบทุกแพลตฟอร์ม

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class AppOtpInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;

  const AppOtpInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
  });

  @override
  State<AppOtpInput> createState() => _AppOtpInputState();
}

class _AppOtpInputState extends State<AppOtpInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focusNode.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focusNode.removeListener(_onChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.text.length == widget.length) {
      widget.onCompleted?.call(widget.controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(widget.length, (i) {
            final filled = i < text.length;
            final isCurrent = i == text.length && _focusNode.hasFocus;
            return Container(
              width: 46,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCurrent
                      ? AppColors.primaryGreen
                      : (filled ? AppColors.primaryGreen.withValues(alpha: 0.4) : AppColors.inputBorder),
                  width: isCurrent ? 2 : 1,
                ),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Text(
                filled ? text[i] : '',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
            );
          }),
        ),
        // TextField จริงซ่อนไว้ (โปร่งใสสนิท) รับ input ทั้งหมด — แตะที่ไหนในกล่องก็โฟกัสตัวนี้
        // บังคับ cursor ไปท้ายข้อความเสมอทุกครั้งที่แตะ (มาตรฐาน OTP ทั่วไป: พิมพ์ต่อท้าย/backspace
        // จากท้ายเท่านั้น ไม่ให้แตะกลางกล่องแล้วแทรกตัวเลขกลางข้อความ ซึ่งกล่องที่เห็นกับตำแหน่ง
        // cursor จริงในฟิลด์ที่ซ่อนไว้จะไม่ตรงกันอยู่แล้ว)
        Opacity(
          opacity: 0,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            autofocus: true,
            showCursor: false,
            onTap: () => widget.controller.selection =
                TextSelection.collapsed(offset: widget.controller.text.length),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.length),
            ],
            decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
          ),
        ),
      ],
    );
  }
}

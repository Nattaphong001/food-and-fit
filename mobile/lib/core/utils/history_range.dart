// ตัวช่วยกรองช่วงเวลาสำหรับหน้าประวัติ (เวทเทรนนิ่ง/คาร์ดิโอ) — ใช้ร่วมกัน 2 ที่
// กรองฝั่ง frontend ล้วนๆ เพราะ endpoint ประวัติที่มีอยู่ (getExerciseHistory,
// getCardioResults) คืนทั้งหมดมาอยู่แล้ว ไม่มี date-range param ฝั่ง backend
import 'package:flutter/material.dart';

enum HistoryRangeOption { sevenDays, thirtyDays, threeMonths, custom }

const Map<HistoryRangeOption, String> historyRangeLabels = {
  HistoryRangeOption.sevenDays: '7 วัน',
  HistoryRangeOption.thirtyDays: '30 วัน',
  HistoryRangeOption.threeMonths: '3 เดือน',
  HistoryRangeOption.custom: 'กำหนดเอง',
};

bool isDateWithinHistoryRange(DateTime date, HistoryRangeOption option, DateTimeRange? customRange) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  switch (option) {
    case HistoryRangeOption.sevenDays:
      return !d.isBefore(today.subtract(const Duration(days: 6)));
    case HistoryRangeOption.thirtyDays:
      return !d.isBefore(today.subtract(const Duration(days: 29)));
    case HistoryRangeOption.threeMonths:
      return !d.isBefore(DateTime(today.year, today.month - 3, today.day));
    case HistoryRangeOption.custom:
      if (customRange == null) return true;
      return !d.isBefore(customRange.start) && !d.isAfter(customRange.end);
  }
}

// แปลง String date จาก API ('2026-08-17' หรือ '2026-08-17T00:00:00Z') เป็น DateTime
DateTime? parseHistoryDate(String raw) {
  try {
    return DateTime.parse(raw.split('T').first);
  } catch (_) {
    return null;
  }
}

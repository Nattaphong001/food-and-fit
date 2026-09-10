// เลือกไอคอนสำรองแบบ deterministic จากชื่อ (hash) เมื่อไม่มี keyword ไหนตรงกับชื่อหมวดหมู่/ประเภท
// ป้องกันปัญหาที่ audit เจอ: หลายหมวดหมู่ชื่อไม่ตรง keyword ที่ตั้งไว้เลย (เช่นชื่อภาษาอังกฤษ)
// ตกไปใช้ไอคอนสำรองตัวเดียวกันหมดจนแยกไม่ออก — สุ่มจาก palette คงที่ตามชื่อแทน ยังคง
// เดิมทุกครั้งที่ reload (ไม่ใช่ random จริง) เพราะอิงจาก hash ของชื่อ

import 'package:flutter/material.dart';

IconData fallbackIconFor(String text, List<IconData> palette) {
  if (palette.isEmpty) return Icons.category_outlined;
  final index = text.hashCode.abs() % palette.length;
  return palette[index];
}

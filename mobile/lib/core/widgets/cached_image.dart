import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// ใช้แทน Image.network() ทุกที่ในแอป
/// - โหลดครั้งแรกจากเน็ต แล้วเก็บ cache ไว้
/// - ครั้งต่อไปขึ้นทันทีไม่มีการรอ
Widget cachedImage(
  String? url, {
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
  Widget? errorWidget,
  double? width,
  double? height,
}) {
  if (url == null || url.isEmpty) {
    return errorWidget ?? _defaultError();
  }
  // เพิ่ม ?v= เฉพาะ URL ที่เป็น path ของ server (ไม่ใช่ external URL)
  // เพื่อป้องกัน cached_network_image ใช้ cache เก่าเมื่อไฟล์ถูกเปลี่ยนชื่อเดิม
  final cacheKey = url.contains('uploads/') ? '$url?v=4' : url;
  return CachedNetworkImage(
    imageUrl: url,
    cacheKey: cacheKey,
    fit: fit,
    width: width,
    height: height,
    placeholder: (context, url) =>
        placeholder ??
        Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
            ),
          ),
        ),
    errorWidget: (context, url, error) => errorWidget ?? _defaultError(),
  );
}

Widget _defaultError() => Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
    );

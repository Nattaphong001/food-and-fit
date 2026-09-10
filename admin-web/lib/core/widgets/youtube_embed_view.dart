// YoutubeEmbedView — เล่นพรีวิววิดีโอ YouTube แบบฝัง iframe บนเว็บ
// แทนที่ flutter_inappwebview (InAppWebView) ที่ใช้ในแอปมือถือ — เหตุผล: flutter_inappwebview
// ไม่รองรับ Flutter Web อย่างสมบูรณ์ (เอกสารทางการยืนยันว่า plugin นี้ทำงานเฉพาะ Android/iOS/
// macOS/Windows เท่านั้น ไม่มี web support) ตัวเลือกนี้ใช้ dart:ui_web ซึ่งมากับ Flutter SDK
// โดยตรง ไม่ต้องเพิ่ม package ใหม่ — ลงทะเบียน <iframe> ของจริงผ่าน platformViewRegistry
// ป้อน URL ตรงๆ เหมือนพฤติกรรม InAppWebView(initialUrlRequest: ...) เดิมทุกจุด (ไม่ตัดฟีเจอร์)
//
// ห้ามห่อ widget นี้ด้วย ClipRRect/ClipRect ที่เรียกทุกจุด — Flutter Web มีบั๊กที่รู้จักกันดี
// (platform view เช่น HtmlElementView ที่ถูก widget ตระกูล Clip* ห่ออยู่ จะยัง "เห็น" ปกติแต่
// รับ pointer event ไม่ได้อีกต่อไป กดเล่น/แชร์/ดูใน YouTube ไม่ได้เลยทั้งที่ iframe โหลดสำเร็จ)
// ต้องการมุมโค้งให้ใช้พารามิเตอร์ borderRadius สั่ง CSS ตรงบน iframe แทน
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class YoutubeEmbedView extends StatefulWidget {
  final String embedUrl;
  // ค่า CSS border-radius ดิบ (เช่น '16px' หรือ '0 0 16px 16px') — ไม่ใช้ Flutter ClipRRect
  // เพราะ clip ancestor ทำให้ platform view รับ pointer event ไม่ได้ (ดูคอมเมนต์ด้านบน)
  final String borderRadius;
  const YoutubeEmbedView({super.key, required this.embedUrl, this.borderRadius = '0'});

  @override
  State<YoutubeEmbedView> createState() => _YoutubeEmbedViewState();
}

class _YoutubeEmbedViewState extends State<YoutubeEmbedView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'youtube-embed-${widget.embedUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = widget.embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.borderRadius = widget.borderRadius
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture'
        ..allowFullscreen = true;
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

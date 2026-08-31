// วิดีโอ loop พื้นหลังส่วนหัวจอ (ใช้ระหว่างฝึกคาร์ดิโอ/เวทเทรนนิ่ง)
// เล่นวนไม่มีเสียง เต็มกรอบแบบ crop-to-fill (BoxFit.cover) — ไม่ยืด ไม่มีแถบดำซ้ายขวา
// ถ้าไม่มี loopVideoUrl หรือโหลดไม่สำเร็จ จะ fallback เป็นภาพนิ่ง imageUrl แทนอัตโนมัติ

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'cached_image.dart';

/// เรียกล่วงหน้าตอนอยู่หน้า detail (ก่อนกดเริ่มฝึก) เพื่อดาวน์โหลดไฟล์วิดีโอ loop
/// เก็บลง cache ไว้ก่อน — พอถึงหน้าฝึกจริง LoopVideoHeader จะอ่านจาก cache ได้ทันที
/// ไม่ต้องรอดาวน์โหลดใหม่ ลดโอกาสกระตุก/ค้างตอนเข้าหน้าฝึก
/// เรียกแบบ fire-and-forget ได้เลย (ไม่ต้อง await) — ล้มเหลวเงียบๆ ถ้าโหลดไม่สำเร็จ
Future<void> preloadLoopVideo(String url) async {
  if (url.isEmpty) return;
  try {
    await DefaultCacheManager().getSingleFile(url);
  } catch (_) {}
}

class LoopVideoHeader extends StatefulWidget {
  final String loopVideoUrl;
  final String imageUrl;
  final double height;
  final IconData fallbackIcon;
  final Color fadeToColor;

  const LoopVideoHeader({
    super.key,
    required this.loopVideoUrl,
    required this.imageUrl,
    required this.height,
    this.fallbackIcon = Icons.fitness_center,
    this.fadeToColor = const Color(0xFFF6F6F6),
  });

  @override
  State<LoopVideoHeader> createState() => _LoopVideoHeaderState();
}

class _LoopVideoHeaderState extends State<LoopVideoHeader> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    if (widget.loopVideoUrl.isEmpty) return;
    try {
      VideoPlayerController controller;
      try {
        final file = await DefaultCacheManager().getSingleFile(widget.loopVideoUrl);
        controller = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } catch (_) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.loopVideoUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      controller.setVolume(0);
      controller.play();
      setState(() => _controller = controller);
    } catch (_) {
      // โหลดวิดีโอไม่สำเร็จ (ไฟล์เสีย/รูปแบบเล่นไม่ได้/เน็ตหลุด) — ปล่อยให้ fallback เป็นภาพนิ่งแทน
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final showVideo = ctrl != null && ctrl.value.isInitialized;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      // AnimatedSwitcher: ครอสเฟดระหว่างภาพนิ่ง (placeholder) กับวิดีโอตอนโหลดเสร็จ
      // กันไม่ให้วิดีโอ "ผุด" ขึ้นมาทันทีแบบไม่มีทรานซิชัน
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: showVideo
            ? Container(
                key: const ValueKey('video'),
                color: const Color(0xFF111111),
                // ClipRect + FittedBox(cover): ขยาย/ครอบตัดวิดีโอให้เต็มกรอบตามสัดส่วนจริง
                // ไม่ยืดภาพผิดสัดส่วนเหมือนใช้ BoxFit.fill
                // Transform.scale ซูมเกินเล็กน้อย (overscan) เพื่อครอบตัดขอบไฟล์ต้นฉบับ
                // ที่อาจมีขอบดำ/ขอบเบลอติดมากับตัวคลิปเอง ซึ่ง BoxFit.cover เพียงอย่างเดียวลบไม่ได้
                child: ClipRect(
                  child: Transform.scale(
                    scale: 1.1,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: ctrl.value.size.width,
                        height: ctrl.value.size.height,
                        child: VideoPlayer(ctrl),
                      ),
                    ),
                  ),
                ),
              )
            : Stack(
                key: const ValueKey('placeholder'),
                fit: StackFit.expand,
                children: [
                  widget.imageUrl.isNotEmpty
                      ? cachedImage(widget.imageUrl, fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey.shade900,
                          child: Center(child: Icon(widget.fallbackIcon, size: 80, color: Colors.white24)),
                        ),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, widget.fadeToColor],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

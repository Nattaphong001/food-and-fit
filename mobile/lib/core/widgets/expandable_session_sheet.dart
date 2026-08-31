// Panel เลื่อนขึ้น-ลงจากขอบล่างสไตล์ YouTube Music ("Expandable Bottom Sheet")
// รองรับ 2 สถานะ: หดลง (โฟกัสวิดีโอ/นาฬิกา) และ ยืดขึ้น (โฟกัสตารางบันทึกผล)
// ควบคุมด้วยนิ้วแบบเรียลไทม์ผ่าน DraggableScrollableController — ตัวเรียกใช้ฟังการเปลี่ยนแปลง
// extent จาก controller เองเพื่อ morph วิดีโอ/ปุ่มด้านนอก Stack ให้สอดคล้องกัน
//
// สำคัญ — เหตุผลที่ handle ลากได้เอง (ไม่พึ่งแค่ scrollController):
// DraggableScrollableSheet ใช้กลไก "ลากเพื่อรีไซส์" ผ่าน scrollController ของ
// [bodyBuilder] เท่านั้น — พื้นที่ handle/footer ที่อยู่นอก Expanded(bodyBuilder)
// เป็น dead zone ลากไม่ได้เลยถ้าไม่มี GestureDetector ของตัวเอง ตอน sheet หดเหลือ
// แค่ 0.2 ของจอ พื้นที่ scrollable ข้างในมันเล็กมาก (แค่ไม่กี่สิบพิกเซล) ผู้ใช้
// จะจับ handle/footer เป็นหลัก จึงต้องขับ controller.jumpTo/animateTo เองตรงนี้
//
// ห้ามใช้ SliverPersistentHeader(pinned:true) ใน bodyBuilder — ยืนยันด้วย
// widget test แล้วว่า viewport ที่หดเล็กมากตอน collapsed ทำให้ sliver แบบ pinned
// throw exception ภายใน framework (_ViewportElement) จน sheet ค้างลากไม่ได้เลย
//
// ใช้ที่: weight_training_exercise_view.dart, cardio_activity_exercise_view.dart

import 'package:flutter/material.dart';

class ExpandableSessionSheet extends StatefulWidget {
  final DraggableScrollableController controller;
  final double collapsedSize;
  final double expandedSize;

  /// เนื้อหาที่เลื่อนได้ด้านในการ์ด — ต้องผูก [scrollController] ที่ได้รับเข้ากับ
  /// scrollable ของตัวเอง (SingleChildScrollView/CustomScrollView แบบไม่มี
  /// pinned SliverPersistentHeader) เพื่อให้ลากถูกต้อง
  final Widget Function(BuildContext context, ScrollController scrollController) bodyBuilder;

  /// แถบปุ่มคำสั่งด้านล่าง — ไม่เลื่อนตาม, ตรึงอยู่ก้นการ์ดเสมอทั้งสองสถานะ
  final Widget? footer;

  /// เนื้อหาหัวการ์ด (เช่น ชื่อท่าออกกำลังกาย) — ไม่เลื่อนตาม, อยู่ใต้ handle ตรงๆ
  /// วางไว้ในโซนลากเดียวกับ handle (ดู GestureDetector ด้านล่าง) เพื่อขยายพื้นที่ลาก
  /// ให้กว้างกว่าเส้น handle บางๆ — ผู้ใช้ลากขึ้น/ลงได้จากทั้งโซนหัวการ์ด ไม่ต้องเล็งแค่กลาง
  final Widget? header;

  const ExpandableSessionSheet({
    super.key,
    required this.controller,
    required this.bodyBuilder,
    this.footer,
    this.header,
    this.collapsedSize = 0.18,
    this.expandedSize = 0.88,
  });

  @override
  State<ExpandableSessionSheet> createState() => _ExpandableSessionSheetState();
}

class _ExpandableSessionSheetState extends State<ExpandableSessionSheet> {
  double _dragStartSize = 0;

  void _onHandleDragStart(DragStartDetails _) {
    if (!widget.controller.isAttached) return;
    _dragStartSize = widget.controller.size;
  }

  void _onHandleDragUpdate(DragUpdateDetails details, double screenHeight) {
    if (!widget.controller.isAttached || screenHeight <= 0) return;
    _dragStartSize -= details.delta.dy / screenHeight;
    final double clamped = _dragStartSize.clamp(widget.collapsedSize, widget.expandedSize);
    widget.controller.jumpTo(clamped);
  }

  void _onHandleDragEnd(DragEndDetails _) {
    if (!widget.controller.isAttached) return;
    final double mid = (widget.collapsedSize + widget.expandedSize) / 2;
    final double target = widget.controller.size >= mid ? widget.expandedSize : widget.collapsedSize;
    widget.controller.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: widget.collapsedSize,
      minChildSize: widget.collapsedSize,
      maxChildSize: widget.expandedSize,
      snap: true,
      snapSizes: [widget.collapsedSize, widget.expandedSize],
      builder: (context, scrollController) {
        return Container(
          key: const ValueKey('expandableSessionSheetPanel'),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -6))],
          ),
          child: ClipRect(
            // กันแถบ debug overflow (เหลือง-ดำ) โผล่ตอน handle+header+footer รวมกันเกิน
            // ความสูง collapsed sheet ไปเล็กน้อย (เช่นตอนมี alert bubble ใน footer) — ตัด
            // ส่วนเกินออกเงียบๆ แทนที่จะพังทั้งจอ ดีกว่าปล่อยให้ overflow banner โผล่จริง
            child: Column(
            children: [
              // Handle + header: โซนลากรวมกันเป็นก้อนเดียว (ไม่ใช่แค่เส้น 4px กลางจอ)
              // ครอบทั้ง handle indicator และ header (เช่นชื่อท่าออกกำลังกาย) ให้ผู้ใช้
              // ลากขึ้น/ลงจากตรงไหนของหัวการ์ดก็ได้ ไม่ต้องเล็งเส้นเล็กๆ ตรงกลาง
              // ลากรีไซส์ได้เองโดยตรง ไม่ต้องพึ่ง scrollController ของ body
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onHandleDragStart,
                onVerticalDragUpdate: (d) => _onHandleDragUpdate(d, screenHeight),
                onVerticalDragEnd: _onHandleDragEnd,
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                      if (widget.header != null) widget.header!,
                    ],
                  ),
                ),
              ),
              Expanded(child: widget.bodyBuilder(context, scrollController)),
              if (widget.footer != null) widget.footer!,
            ],
            ),
          ),
        );
      },
    );
  }
}

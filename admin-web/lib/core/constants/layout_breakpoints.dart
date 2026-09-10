// AppBreakpoints — breakpoint กลางสำหรับ layout จอกว้างฝั่ง Admin เว็บ
// ใช้ร่วมกันทุกหน้า ห้าม hardcode ตัวเลขความกว้างซ้ำที่หน้าไหนอีก
//
// < mobile        : sidebar ยุบเป็น Drawer, ตารางเลื่อนแนวนอนได้
// mobile..tablet  : sidebar แบบไอคอนอย่างเดียว (icon rail)
// > tablet        : sidebar เต็ม + จำกัดความกว้างเนื้อหาสูงสุดที่ maxContentWidth

enum LayoutTier { compact, medium, wide }

class AppBreakpoints {
  static const double mobile = 900;
  static const double tablet = 1400;
  static const double maxContentWidth = 1280;

  static LayoutTier of(double width) {
    if (width < mobile) return LayoutTier.compact;
    if (width < tablet) return LayoutTier.medium;
    return LayoutTier.wide;
  }
}

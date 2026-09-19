-- 2026-09-19 — ปรับค่า METs ตาราง cardio ให้ตรงรหัส Compendium of Physical Activities 2011
-- (ฉบับแปลไทย ดร.ชุติมา ชลายนเดชะ ม.มหิดล = "Ainsworth et al., 2554" ที่บทที่ 2 ข้อ 2.1.4.10 อ้าง)
-- ผลตรวจเต็ม → docs/compendium-2011-met-check.md
--
-- เหตุผล: กฎเหล็ก "ห้ามเดาค่า MET" — ทุกค่าใน cardio.cdo_mets ต้องตรวจสอบย้อนกลับถึงรหัสใน Compendium ได้
-- ตรวจ 9 แถว พบ 2 แถวไม่ตรงรหัสใดเลย:
--   cdo_id 4 เครื่องกรรเชียงบก 7.5  → 02072 พายเรืออยู่กับที่ 100 วัตต์ ปานกลาง = 7.0
--   cdo_id 8 มวยไทย / ชกมวย 8.0     → แยกเป็น 2 กิจกรรมตามที่ Compendium แยกรหัส:
--        มวยไทย       15430 ศิลปะการต่อสู้ จังหวะปานกลาง (ระบุมวยไทยตรงๆ) = 10.3  (คง cdo_id 8 เดิม)
--        ชกมวย (ซ้อม)  15120 มวย ซ้อม = 7.8                                        (แถวใหม่)
-- ไม่แตะ cdo_id 5 (สะบัดเชือกหนา 8.0 อิง 02040) และ 7 (HIIT บอดี้เวท 8.0 อิง 02020) — ไม่มีรหัสชื่อตรง
-- ใช้รหัสใกล้เคียงที่สุด ค่าเท่าเดิม ไม่ต้องแก้ DB
--
-- ⚠️ ผลข้างเคียงที่ทราบแล้ว: cardio_result เดิมของ cdo_id 4 (21 แถว) และ cdo_id 8 (18 แถว) คำนวณ
--    cdors_calories ด้วย METs เดิม (7.5 / 8.0) ไม่ backfill (ตัดสินใจเดียวกับข้อมูลก่อน 2026-09-19 ที่เปลี่ยน
--    สูตร ACSM — เทียบย้อนหลังตรงๆ ไม่ได้) แถวเดิมของ cdo_id 8 ที่เคยบันทึกไว้ในชื่อ "มวยไทย / ชกมวย"
--    จะแสดงเป็น "มวยไทย" หลังรัน
-- ⚠️ ไฟล์รูป/วิดีโอ Loop ของแถวใหม่ (boxing_training*) คัดลอกจากของ boxing_muay_thai* เป็นค่าชั่วคราว
--    แอดมินเปลี่ยนภายหลังได้ที่หน้าจัดการกิจกรรมคาร์ดิโอ
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ (รันแล้ว 2026-09-19)
--   mysqldump -u root -p food_and_fit_db cardio > backups/backup_cardio_before_compendium_mets_20260919.sql

START TRANSACTION;

UPDATE cardio
   SET cdo_mets = 7.00
 WHERE cdo_id = 4 AND cdo_name = 'เครื่องกรรเชียงบก' AND cdo_mets = 7.50;

UPDATE cardio
   SET cdo_name = 'มวยไทย',
       cdo_mets = 10.30
 WHERE cdo_id = 8 AND cdo_name = 'มวยไทย / ชกมวย' AND cdo_mets = 8.00;

INSERT INTO cardio
  (cdo_image, cdo_name, cdo_mets, cdo_has_distance, cdo_description, cdo_technique, cdo_video, cdo_loop_video, cdc_id)
VALUES
  ('uploads/cardio/images/boxing_training.jpg',
   'ชกมวย (ซ้อม)',
   7.80,
   0,
   'การซ้อมมวยสากลด้วยการชกกระสอบทรายหรือชกลม (Shadow Boxing) ช่วยฝึกความอึด ความเร็วของหมัด และการทำงานประสานกันของแขน ไหล่ และแกนกลางลำตัว',
   'ยืนตั้งการ์ดในท่ามวยสากล เท้าแยกมั่นคง ย่อเข่าเล็กน้อย มือสองข้างยกขึ้นบังแนวใบหน้า
ออกหมัดตรง หมัดฮุก และหมัดอัปเปอร์คัตใส่กระสอบทรายหรืออากาศ โดยบิดสะโพกและลำตัวส่งแรงจากเท้าขึ้นมาที่หมัด หายใจออกทุกครั้งที่ออกหมัด
ระวังอย่าล็อกข้อศอกตึงเป๊ะตอนปล่อยหมัดสุดแรง และดึงหมัดกลับมาตั้งการ์ดทุกครั้งหลังออกหมัด',
   '',
   'uploads/cardio/videoloop/boxing_training_loop.mp4',
   2);

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-19_align_cardio_mets_to_compendium_2011.sql',
   'cdo_id 4: 7.5→7.0 (02072) · cdo_id 8: 8.0→10.3 มวยไทย (15430) · เพิ่ม ชกมวย (ซ้อม) 7.8 (15120)');

COMMIT;

-- Rollback:
-- START TRANSACTION;
-- UPDATE cardio SET cdo_mets = 7.50 WHERE cdo_id = 4;
-- UPDATE cardio SET cdo_name = 'มวยไทย / ชกมวย', cdo_mets = 8.00 WHERE cdo_id = 8;
-- -- ระวัง: ถ้ามี cardio_result ผูกกับแถวใหม่แล้ว การลบจะทำให้ cdo_id ของแถวเหล่านั้นเป็น NULL (FK SET NULL)
-- DELETE FROM cardio WHERE cdo_name = 'ชกมวย (ซ้อม)';
-- DELETE FROM schema_migrations WHERE filename = '2026-09-19_align_cardio_mets_to_compendium_2011.sql';
-- COMMIT;
-- (หรือกู้ทั้งตารางจาก backups/backup_cardio_before_compendium_mets_20260919.sql)

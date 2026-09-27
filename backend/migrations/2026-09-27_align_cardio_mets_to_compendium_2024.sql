-- 2026-09-27 — ปรับค่า METs ตาราง cardio ให้ตรงรหัส 2024 Adult Compendium of Physical Activities
-- (Herrmann et al., 2567 — ที่มาที่บทที่ 2 ตารางที่ 2.1 อ้างไว้จริง แทนฉบับ 2011 ที่เคยใช้ตรวจ)
-- ที่มาไฟล์อ้างอิง: 1_2024-adult-compendium_1_2024.pdf (ผู้ใช้ส่งให้ตรวจ 2026-09-27)
--
-- เหตุผล: กฎเหล็ก "ห้ามเดาค่า MET" — migration 2026-09-19_align_cardio_mets_to_compendium_2011.sql
-- เคยตรวจกับฉบับ 2011 (ฉบับเดียวที่มีไฟล์ในตอนนั้น) แต่ตารางที่ 2.1 อ้างฉบับ 2024 มาตลอด — ตรวจซ้ำกับ
-- ฉบับ 2024 ตัวจริงพบ 6 จาก 10 แถวค่าไม่ตรง (2 แถวรหัสเดิมไม่มีอยู่จริงในฉบับ 2024 ด้วย):
--
--   cdo_id 1 เดินชันบนสายพาน   8.00 → 8.80  (รหัสเดิม 17211 ไม่มีในฉบับ 2024 → เปลี่ยนเป็น 17036
--                                             "Climbing hills, no load, 11-20% grade, slow-to-moderate pace")
--   cdo_id 2 เครื่องก้าวบันได   9.00 → 9.30  (02065 Stair treadmill ergometer, general — รหัสเดิมถูกอยู่แล้ว
--                                             แค่ตัวเลขต่างจาก 2011)
--   cdo_id 3 ปั่นจักรยานฟิตเนส  7.00 → 6.80  (รหัสเดิม 02010 ไม่มีในฉบับ 2024 → ย้ายหมวดเป็น 01200
--                                             "Bicycling, stationary, general")
--   cdo_id 4 เครื่องกรรเชียงบก  7.00 → 7.50  (02072 Rowing, stationary, 100-149 watts, vigorous effort —
--                                             ฉบับ 2011 เคยให้ 7.0/ปานกลาง ฉบับ 2024 คือ 7.5/หนัก)
--   cdo_id 5 สะบัดเชือกหนา     8.00 → 7.50  (เปลี่ยนรหัสจาก 02040 เป็น 02020 Calisthenics ที่ระบุ
--                                             "battling ropes" ตรงตัว)
--   cdo_id 7 HIIT บอดี้เวท      8.00 → 11.00 (เปลี่ยนรหัสจาก 02020 เป็น 02214 High intensity interval
--                                             exercise, burpees/mountain climbers/squat jumps/Tabata,
--                                             vigorous effort — รหัส HIIT เฉพาะที่ฉบับ 2024 เพิ่มเข้ามาใหม่)
--
-- ไม่แตะ cdo_id 6 (กระโดดเชือก 12.30 ตรงกับรหัส 15550 "Rope jumping, fast pace, 120-160 skips/min" อยู่แล้ว
-- แค่ต้องแก้รหัสที่อ้างในเล่มจาก 02068 เป็น 15550 — ไม่กระทบ DB), cdo_id 8/9/10 (มวยไทย/ว่ายน้ำ/ชกมวย
-- ตรงฉบับ 2024 อยู่แล้วตั้งแต่ตรวจ 2011 เพราะเป็นรหัสเดียวกันทั้ง 2 ฉบับ)
--
-- ⚠️ ผลข้างเคียงที่ทราบแล้ว: cardio_result เดิมของ 6 cdo_id นี้คำนวณ cdors_calories ด้วย METs เดิม
--    ไม่ backfill (นโยบายเดียวกับ migration ก่อนหน้าทุกครั้งที่แก้ METs — เทียบย้อนหลังตรงๆ ไม่ได้)
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ (รันแล้ว 2026-09-27)
--   mysqldump -u root food_and_fit_db cardio > backups/backup_cardio_before_compendium_2024_mets_20260927.sql

START TRANSACTION;

UPDATE cardio SET cdo_mets = 8.80  WHERE cdo_id = 1 AND cdo_name = 'เดินชันบนสายพาน' AND cdo_mets = 8.00;
UPDATE cardio SET cdo_mets = 9.30  WHERE cdo_id = 2 AND cdo_name = 'เครื่องก้าวบันได' AND cdo_mets = 9.00;
UPDATE cardio SET cdo_mets = 6.80  WHERE cdo_id = 3 AND cdo_name = 'ปั่นจักรยานฟิตเนส' AND cdo_mets = 7.00;
UPDATE cardio SET cdo_mets = 7.50  WHERE cdo_id = 4 AND cdo_name = 'เครื่องกรรเชียงบก' AND cdo_mets = 7.00;
UPDATE cardio SET cdo_mets = 7.50  WHERE cdo_id = 5 AND cdo_name = 'สะบัดเชือกหนา' AND cdo_mets = 8.00;
UPDATE cardio SET cdo_mets = 11.00 WHERE cdo_id = 7 AND cdo_name = 'HIIT บอดี้เวท' AND cdo_mets = 8.00;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-27_align_cardio_mets_to_compendium_2024.sql',
   'cdo_id 1: 8.0→8.8 (17036) · 2: 9.0→9.3 (02065) · 3: 7.0→6.8 (01200) · 4: 7.0→7.5 (02072) · 5: 8.0→7.5 (02020) · 7: 8.0→11.0 (02214)');

COMMIT;

-- Rollback:
-- START TRANSACTION;
-- UPDATE cardio SET cdo_mets = 8.00 WHERE cdo_id = 1 AND cdo_name = 'เดินชันบนสายพาน';
-- UPDATE cardio SET cdo_mets = 9.00 WHERE cdo_id = 2 AND cdo_name = 'เครื่องก้าวบันได';
-- UPDATE cardio SET cdo_mets = 7.00 WHERE cdo_id = 3 AND cdo_name = 'ปั่นจักรยานฟิตเนส';
-- UPDATE cardio SET cdo_mets = 7.00 WHERE cdo_id = 4 AND cdo_name = 'เครื่องกรรเชียงบก';
-- UPDATE cardio SET cdo_mets = 8.00 WHERE cdo_id = 5 AND cdo_name = 'สะบัดเชือกหนา';
-- UPDATE cardio SET cdo_mets = 8.00 WHERE cdo_id = 7 AND cdo_name = 'HIIT บอดี้เวท';
-- DELETE FROM schema_migrations WHERE filename = '2026-09-27_align_cardio_mets_to_compendium_2024.sql';
-- COMMIT;
-- (หรือกู้ทั้งตารางจาก backups/backup_cardio_before_compendium_2024_mets_20260927.sql)

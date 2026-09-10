-- =====================================================================
-- 2026-09-06 : เก็บกวาดร่องรอยข้อมูลทดลองที่ค้างในข้อมูลแม่ (แอดมินป้อน)
-- ---------------------------------------------------------------------
-- 1) nutrition ntt_id = 163 "TSQA Food 2026-08-24 120101" — แถวที่สร้างจาก
--    การทดสอบอัตโนมัติ (TestSprite) ไม่ใช่ข้อมูลอาหารจริง → ลบทิ้ง
--    (ตอนลบ daily_nutrition ว่างแล้ว ไม่มีประวัติการกินอ้างถึงแถวนี้)
-- 2) cardio cdo_id = 6 — กิจกรรมจริง แต่ชื่อโดนแก้ตอนทดสอบเป็น
--    "กระโดดเชือก (แก้ไขทดสอบ)" → คืนชื่อเดิม "กระโดดเชือก"
-- 3) weight_exercises wet_id = 6 — ท่าฝึกจริง ชื่อโดนแก้ตอนทดสอบเป็น
--    "Chest Press Machine UPDATED (QA Edited)" → คืนชื่อ "Chest Press Machine"
-- ไม่แตะ PK / FK / index / คอลัมน์อื่น — แก้เฉพาะชื่อ 2 แถว และลบ 1 แถว
--
-- backup : migrations/backups/backup_before_20260906_purge_member_data.sql
-- =====================================================================

DELETE FROM nutrition WHERE ntt_id = 163 AND ntt_food_name = 'TSQA Food 2026-08-24 120101';
UPDATE cardio           SET cdo_name = 'กระโดดเชือก'        WHERE cdo_id = 6;
UPDATE weight_exercises SET wet_name = 'Chest Press Machine' WHERE wet_id = 6;
ALTER TABLE nutrition AUTO_INCREMENT = 149;

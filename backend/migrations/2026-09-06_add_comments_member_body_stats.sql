-- เติม COMMENT ให้ member_body_stats ให้ตรง Datadic_edit.dart
-- (บล็อกนี้เขียนไว้แล้วใน migrations/2026-09-05_sync_column_order_and_comments_with_datadic.sql
--  บรรทัด 138-144 แต่หลุดไม่ถูกรันจริงตอนนั้น — ตรวจสอบแล้ว 2026-09-06 ว่าตารางข้างเคียงในไฟล์เดียวกัน
--  (member_profile, member_bmr_history, workout_schedules ฯลฯ) มี comment ครบหมด มีแค่ตารางนี้ตารางเดียว
--  ที่ว่างเปล่า)
-- ไม่เปลี่ยนชนิดข้อมูล, NULL/NOT NULL, DEFAULT, PK/FK/INDEX, ลำดับคอลัมน์ใดๆ ทั้งสิ้น แก้แค่ COMMENT
--
-- ⚠️ ต้องรันด้วย: mysql -u root food_and_fit_db --default-character-set=utf8mb4 < <ไฟล์นี้>
--    ห้ามรันแบบไม่ระบุ --default-character-set=utf8mb4 หรือผ่าน -e เป็น argument ตรงๆ
--    (client บนเครื่องนี้ default เป็น tis620 ทำให้ข้อความไทยเพี้ยนตอนเขียนลง DB จริง)
--
-- Rollback (คืนกลับเป็นไม่มี comment เหมือนก่อนรัน):
--   ALTER TABLE member_body_stats
--     MODIFY COLUMN mbs_height decimal(5,2) DEFAULT NULL,
--     MODIFY COLUMN mbs_weight decimal(5,2) DEFAULT NULL,
--     MODIFY COLUMN mbs_activity_level decimal(4,3) DEFAULT NULL,
--     MODIFY COLUMN mbs_target tinyint(4) DEFAULT NULL,
--     MODIFY COLUMN mbs_recorded_date datetime DEFAULT NULL,
--     MODIFY COLUMN mb_id int(11) DEFAULT NULL;

ALTER TABLE member_body_stats
  MODIFY COLUMN mbs_height decimal(5,2) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)',
  MODIFY COLUMN mbs_weight decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนัก (กก.)',
  MODIFY COLUMN mbs_activity_level decimal(4,3) DEFAULT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9',
  MODIFY COLUMN mbs_target tinyint(4) DEFAULT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)',
  MODIFY COLUMN mbs_recorded_date datetime DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล (upsert ระดับแอป 1 วันต่อ 1 แถวเป็นหลัก)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]';

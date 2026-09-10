-- เติม COMMENT ให้ cardio_result ให้ตรง Datadic_edit.dart
-- (บล็อกนี้เขียนไว้แล้วใน migrations/2026-09-05_sync_column_order_and_comments_with_datadic.sql
--  บรรทัด 212-218 แต่หลุดไม่ถูกรันจริงตอนนั้น เหมือนกับ member_body_stats และ weight_training_result
--  (ดู migrations/2026-09-06_add_comments_member_body_stats.sql,
--   migrations/2026-09-06_add_comments_weight_training_result.sql) — เหลือแค่ cdors_id ที่มี comment เดิม)
-- ไม่เปลี่ยนชนิดข้อมูล, NULL/NOT NULL, DEFAULT, PK/FK/INDEX, ลำดับคอลัมน์ใดๆ ทั้งสิ้น แก้แค่ COMMENT
--
-- ⚠️ ต้องรันด้วย: mysql -u root food_and_fit_db --default-character-set=utf8mb4 < <ไฟล์นี้>
--    ห้ามรันแบบไม่ระบุ --default-character-set=utf8mb4 หรือผ่าน -e เป็น argument ตรงๆ
--    (client บนเครื่องนี้ default เป็น tis620 ทำให้ข้อความไทยเพี้ยนตอนเขียนลง DB จริง)
--
-- Rollback (คืนกลับเป็นไม่มี comment เหมือนก่อนรัน):
--   ALTER TABLE cardio_result
--     MODIFY COLUMN cdors_date date DEFAULT NULL,
--     MODIFY COLUMN cdors_duration bigint(20) DEFAULT NULL,
--     MODIFY COLUMN cdors_distance decimal(5,2) DEFAULT 0.00,
--     MODIFY COLUMN cdors_calories decimal(7,2) DEFAULT NULL,
--     MODIFY COLUMN mb_id int(11) DEFAULT NULL,
--     MODIFY COLUMN cdo_id int(10) unsigned DEFAULT NULL;

ALTER TABLE cardio_result
  MODIFY COLUMN cdors_date date DEFAULT NULL COMMENT 'วันที่บันทึกผลการคาร์ดิโอ',
  MODIFY COLUMN cdors_duration bigint(20) DEFAULT NULL COMMENT 'ระยะเวลา (นาที)',
  MODIFY COLUMN cdors_distance decimal(5,2) DEFAULT 0.00 COMMENT 'ระยะทาง (กม., ส่งมาเฉพาะกิจกรรมที่ cdo_has_distance=1)',
  MODIFY COLUMN cdors_calories decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ หักฐาน 1 MET แล้ว)',
  MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  MODIFY COLUMN cdo_id int(10) unsigned DEFAULT NULL COMMENT 'รหัสคาร์ดิโอ [FK -> cardio] ON DELETE SET NULL';

-- ============================================================================
-- เติม COMMENT ที่ยังว่างอยู่จริงใน live DB ให้ครบ 25 คอลัมน์ (2026-09-06)
-- ============================================================================
-- ที่มา: query information_schema.COLUMNS สดวันที่ 2026-09-06 พบคอลัมน์ที่ COLUMN_COMMENT
-- ยังเป็นค่าว่างอยู่ 25 คอลัมน์ แบ่งเป็น
--   [ก] ตารางธุรกิจ 12 คอลัมน์ — member_body_stats (6), weight_training_result (3),
--       cardio_result (3)
--   [ข] ตารางภายในระบบ 13 คอลัมน์ — audit_logs (10), revoked_tokens (3)
--       (2 ตารางนี้ไม่อยู่ใน ER/Datadic เลยไม่เคยมีใครเติม comment ให้)
--
-- ทำไมยังว่างอยู่ทั้งที่ commit 56cb887 บอกว่าเติมแล้ว:
--   ไฟล์ migrations/2026-09-06_add_comments_{cardio_result,member_body_stats,
--   weight_training_result}.sql ถูก commit ไว้ แต่ "ไม่เคยถูกรันจริงกับ DB" — ยืนยันจากข้อความ
--   comment ที่มีอยู่ตอนนี้ไม่ตรงกับในไฟล์ (DB มี 'แคลอรี่ที่เผาผลาญ (สุทธิ)' ส่วนไฟล์เขียนว่า
--   '(สุทธิ หักฐาน 1 MET แล้ว)') comment ที่มีอยู่จริงมาจาก
--   2026-09-06_repair_automigrate_corruption.sql +
--   2026-09-06_reapply_notnull_and_add_constraints.sql แทน
--
--   ⚠️ ห้ามรัน 3 ไฟล์ add_comments_*.sql นั้นอีก — MODIFY COLUMN ในไฟล์ยังระบุชนิดเก่า
--   (decimal(7,2), bigint(20), mb_id DEFAULT NULL) ถ้ารันจะทำ schema พังกลับไปเป็นสภาพก่อนซ่อม
--   AutoMigrate corruption ที่ซ่อมไปแล้วในรอบก่อน
--
-- ไฟล์นี้แก้ "เฉพาะ COMMENT เท่านั้น" — ชนิดข้อมูล/NULL/NOT NULL/DEFAULT/PK/FK/INDEX/ลำดับคอลัมน์
-- ทุกตัวคัดลอกมาจากค่าที่อยู่ใน live DB ตอนนี้เป๊ะ ๆ ไม่มีการเปลี่ยนแปลงใด ๆ
--
-- ⚠️ ต้องรันด้วย: mysql -u root food_and_fit_db --default-character-set=utf8mb4 < <ไฟล์นี้>
--    ห้ามรันผ่าน -e เป็น argument ตรง ๆ (console codepage บนเครื่องนี้ทำข้อความไทยเพี้ยน)
--
-- Backup: migrations/backups/backup_before_20260906_fill_missing_comments.sql
--
-- หมายเหตุ audit_logs / revoked_tokens: 2 ตารางนี้ยังอยู่ใน DB.AutoMigrate(...) ที่
-- config/database.go — GORM MigrateColumn เทียบ COMMENT ด้วย ถ้า gorm tag ไม่มี `comment:`
-- มันจะ ALTER ลบ comment ที่เติมไว้ทิ้งทุกครั้งที่ restart server ดังนั้นไฟล์นี้ต้องแก้คู่กับ
-- models/security.go (เพิ่ม `comment:...` ให้ครบทุก field) ไม่งั้น comment จะหายอีก
-- (บทเรียนเดียวกับ D10.1)
--
-- Rollback (คืนกลับเป็นไม่มี comment เหมือนก่อนรัน):
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_height decimal(4,1) DEFAULT NULL;
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_weight decimal(5,2) DEFAULT NULL;
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_activity_level decimal(4,3) DEFAULT NULL;
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_target tinyint(4) DEFAULT NULL;
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_recorded_date datetime DEFAULT NULL;
--   ALTER TABLE member_body_stats MODIFY COLUMN mb_id int(11) NOT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN mb_id int(11) NOT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN wet_id int(10) unsigned DEFAULT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN wsch_id int(10) unsigned DEFAULT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN cdors_distance decimal(5,2) DEFAULT 0.00;
--   ALTER TABLE cardio_result MODIFY COLUMN mb_id int(11) NOT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN cdo_id int(10) unsigned DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN actor_type varchar(20) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN actor_id bigint(20) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN action varchar(50) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN detail varchar(255) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN table_name varchar(64) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN record_id varchar(64) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN old_value json DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN new_value json DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN ip_address varchar(45) DEFAULT NULL;
--   ALTER TABLE audit_logs MODIFY COLUMN created_at datetime(3) DEFAULT NULL;
--   ALTER TABLE revoked_tokens MODIFY COLUMN jti varchar(64) NOT NULL;
--   ALTER TABLE revoked_tokens MODIFY COLUMN expires_at datetime(3) NOT NULL;
--   ALTER TABLE revoked_tokens MODIFY COLUMN created_at datetime(3) DEFAULT NULL;
-- ============================================================================


-- ---------------------------------------------------------------------------
-- [ก1] member_body_stats — เดิมมี comment แค่ mbs_id ตัวเดียว
--      ข้อความอ้างอิงจาก Datadic_edit.dart ตารางที่ 4.3
--      (แยก ALTER ทีละคอลัมน์ เพราะ mb_id เป็นคอลัมน์ FK รวมสเตตเมนต์แล้ว MariaDB ขึ้น
--       error 1832 "Cannot change column used in a foreign key constraint" — ดูบทเรียนใน
--       2026-09-06_reapply_notnull_and_add_constraints.sql)
-- ---------------------------------------------------------------------------
ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_height` decimal(4,1) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_weight` decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนัก (กก.)';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_activity_level` decimal(4,3) DEFAULT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_target` tinyint(4) DEFAULT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_recorded_date` datetime DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล (upsert ระดับแอป 1 วันต่อ 1 แถวเป็นหลัก)';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]';


-- ---------------------------------------------------------------------------
-- [ก2] weight_training_result — ขาด comment เฉพาะ 3 คอลัมน์ FK ท้ายตาราง
--      (คอลัมน์ที่เหลือมี comment แล้วจาก 2026-09-06_repair_automigrate_corruption.sql)
-- ---------------------------------------------------------------------------
ALTER TABLE `weight_training_result`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises] ON DELETE SET NULL';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wsch_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางเวทเทรนนิ่ง [FK -> workout_schedules] ON DELETE SET NULL, NULL = ฝึกนอกแผนที่วางไว้';


-- ---------------------------------------------------------------------------
-- [ก3] cardio_result — ขาด comment 3 คอลัมน์ (cdors_distance + 2 FK ท้ายตาราง)
-- ---------------------------------------------------------------------------
ALTER TABLE `cardio_result`
  MODIFY COLUMN `cdors_distance` decimal(5,2) DEFAULT 0.00 COMMENT 'ระยะทาง (กม., ส่งมาเฉพาะกิจกรรมที่ cdo_has_distance=1)';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `cdo_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสคาร์ดิโอ [FK -> cardio] ON DELETE SET NULL';


-- ---------------------------------------------------------------------------
-- [ข1] audit_logs — ตารางบันทึกเหตุการณ์ภายในระบบ (ไม่อยู่ใน ER)
--      ค่าที่เป็นไปได้ของ actor_type/action ตรวจจากข้อมูลจริงในตาราง 949 แถว
--      (actor_type: admin/member/guest — guest ใช้ actor_id = 0)
--      old_value/new_value ประกาศเป็น json (MariaDB alias ของ longtext + CHECK json_valid)
--      ตรงกับที่ GORM สร้างไว้จาก tag `type:json` ใน models/security.go
-- ---------------------------------------------------------------------------
ALTER TABLE `audit_logs`
  MODIFY COLUMN `actor_type` varchar(20) DEFAULT NULL COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)',
  MODIFY COLUMN `actor_id` bigint(20) DEFAULT NULL COMMENT 'รหัสผู้กระทำ (mb_id หรือ sys_id ตาม actor_type, 0 = guest)',
  MODIFY COLUMN `action` varchar(50) DEFAULT NULL COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)',
  MODIFY COLUMN `detail` varchar(255) DEFAULT NULL COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์',
  MODIFY COLUMN `table_name` varchar(64) DEFAULT NULL COMMENT 'ชื่อตารางที่ถูกแก้ไข (เฉพาะ action create/update/delete)',
  MODIFY COLUMN `record_id` varchar(64) DEFAULT NULL COMMENT 'รหัสแถวข้อมูลที่ถูกแก้ไขในตารางนั้น',
  MODIFY COLUMN `old_value` json DEFAULT NULL COMMENT 'ค่าเดิมก่อนแก้ไข (JSON, NULL เมื่อเป็นการเพิ่มข้อมูลใหม่)',
  MODIFY COLUMN `new_value` json DEFAULT NULL COMMENT 'ค่าใหม่หลังแก้ไข (JSON, NULL เมื่อเป็นการลบข้อมูล)',
  MODIFY COLUMN `ip_address` varchar(45) DEFAULT NULL COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)',
  MODIFY COLUMN `created_at` datetime(3) DEFAULT NULL COMMENT 'วันและเวลาที่บันทึกเหตุการณ์';


-- ---------------------------------------------------------------------------
-- [ข2] revoked_tokens — denylist ของ JWT ที่ถูกเพิกถอน (logout / เปลี่ยนรหัสผ่าน)
-- ---------------------------------------------------------------------------
ALTER TABLE `revoked_tokens`
  MODIFY COLUMN `jti` varchar(64) NOT NULL COMMENT 'รหัสอ้างอิงโทเคน (JWT claim jti) ที่ถูกเพิกถอน',
  MODIFY COLUMN `expires_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่โทเคนหมดอายุตามค่า exp ใน JWT',
  MODIFY COLUMN `created_at` datetime(3) DEFAULT NULL COMMENT 'วันและเวลาที่เพิกถอนโทเคน';

-- Schema for food_and_fit_db — 17 business tables + 3 internal tables (audit_logs, revoked_tokens,
-- schema_migrations). Structure only, no data — see seed_master.sql for catalog/master data.
-- Regenerated from the live database 2026-09-29 (previous schema.sql/seed_master.sql were deleted
-- in commit b864731 on 2026-09-11 along with the rest of the old migrations/ directory — an
-- unintended side effect, not a policy change; README's setup steps need these two files).
--
-- Import:
--   mysql -u root -p food_and_fit_db --default-character-set=utf8mb4 < migrations/schema.sql
--   mysql -u root -p food_and_fit_db --default-character-set=utf8mb4 < migrations/seed_master.sql

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS=0;


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
DROP TABLE IF EXISTS `audit_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `audit_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `actor_type` varchar(20) NOT NULL COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)',
  `actor_id` bigint(20) NOT NULL COMMENT 'รหัสผู้กระทำ (mb_id หรือ sys_id ตาม actor_type, 0 = guest)',
  `action` varchar(50) NOT NULL COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)',
  `detail` varchar(255) NOT NULL COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์',
  `table_name` varchar(64) DEFAULT NULL COMMENT 'ชื่อตารางที่ถูกแก้ไข (เฉพาะ action create/update/delete)',
  `record_id` varchar(64) DEFAULT NULL COMMENT 'รหัสแถวข้อมูลที่ถูกแก้ไขในตารางนั้น',
  `old_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'ค่าเดิมก่อนแก้ไข (JSON, NULL เมื่อเป็นการเพิ่มข้อมูลใหม่)' CHECK (json_valid(`old_value`)),
  `new_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'ค่าใหม่หลังแก้ไข (JSON, NULL เมื่อเป็นการลบข้อมูล)' CHECK (json_valid(`new_value`)),
  `ip_address` varchar(45) NOT NULL COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)',
  `created_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่บันทึกเหตุการณ์',
  PRIMARY KEY (`id`),
  KEY `idx_audit_logs_actor_type` (`actor_type`),
  KEY `idx_audit_logs_actor_id` (`actor_id`),
  KEY `idx_audit_logs_action` (`action`),
  KEY `idx_audit_logs_target_table` (`table_name`),
  KEY `idx_audit_logs_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=55 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio` (
  `cdo_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสคาร์ดิโอ [PK]',
  `cdo_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปกิจกรรมคาร์ดิโอ',
  `cdo_name` varchar(100) NOT NULL COMMENT 'ชื่อกิจกรรมคาร์ดิโอ',
  `cdo_mets` decimal(4,2) NOT NULL COMMENT 'ค่าความหนักของกิจกรรม (METs)',
  `cdo_has_distance` tinyint(1) unsigned NOT NULL DEFAULT 0 COMMENT 'แสดงช่องกรอกระยะทาง (0=ไม่แสดง, 1=แสดง)',
  `cdo_description` text NOT NULL COMMENT 'คำอธิบายวิธีฝึก',
  `cdo_technique` text NOT NULL COMMENT 'เทคนิคในการฝึก',
  `cdo_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอแนะนำวิธีฝึก',
  `cdo_loop_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอ Loop คาร์ดิโอ',
  `cdc_id` int(10) unsigned NOT NULL DEFAULT 1 COMMENT 'รหัสประเภทคาร์ดิโอ [FK -> cardio_category]',
  PRIMARY KEY (`cdo_id`),
  UNIQUE KEY `uq_cdo_name` (`cdo_name`),
  KEY `idx_cdo_category` (`cdc_id`),
  CONSTRAINT `fk_cardio_category` FOREIGN KEY (`cdc_id`) REFERENCES `cardio_category` (`cdc_id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio_category` (
  `cdc_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสประเภทคาร์ดิโอ [PK]',
  `cdc_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปประเภทคาร์ดิโอ',
  `cdc_name` varchar(100) NOT NULL COMMENT 'ชื่อประเภทคาร์ดิโอ',
  `cdc_description` text NOT NULL COMMENT 'คำอธิบายประเภทคาร์ดิโอ',
  PRIMARY KEY (`cdc_id`),
  UNIQUE KEY `uq_cdc_name` (`cdc_name`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio_result`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio_result` (
  `cdors_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสผลการฝึกคาร์ดิโอ [PK]',
  `cdors_date` date NOT NULL COMMENT 'วันที่บันทึกผลการคาร์ดิโอ',
  `cdors_duration` smallint(5) unsigned NOT NULL COMMENT 'ระยะเวลา (นาที)',
  `cdors_distance` decimal(5,2) DEFAULT NULL COMMENT 'ระยะทาง (กม.)',
  `cdors_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `cdo_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสคาร์ดิโอ [FK -> cardio] ON DELETE SET NULL',
  PRIMARY KEY (`cdors_id`),
  KEY `idx_cdors_cdo_id` (`cdo_id`),
  KEY `fk_cdors_member` (`mb_id`),
  CONSTRAINT `fk_cdors_cardio` FOREIGN KEY (`cdo_id`) REFERENCES `cardio` (`cdo_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_cdors_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=214 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `daily_nutrition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `daily_nutrition` (
  `dntt_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสบันทึกโภชนาการประจำวัน [PK]',
  `dntt_date` date NOT NULL COMMENT 'วันที่บันทึก',
  `dntt_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพอาหารที่บันทึก',
  `dntt_food_name` varchar(100) NOT NULL COMMENT 'ชื่ออาหารที่บันทึก',
  `dntt_quantity` decimal(5,2) NOT NULL COMMENT 'จำนวนที่บริโภค',
  `dntt_unit` varchar(20) NOT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)',
  `dntt_meal_type` tinyint(4) NOT NULL COMMENT 'มื้ออาหาร (1=มื้อเช้า, 2=มื้อกลางวัน, 3=มื้อเย็น, 4=มื้อว่าง)',
  `dntt_total_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่รวมของรายการนี้',
  `dntt_total_protein` decimal(6,2) NOT NULL COMMENT 'โปรตีนรวมของรายการนี้',
  `dntt_total_carb` decimal(6,2) NOT NULL COMMENT 'คาร์โบไฮเดรตรวมของรายการนี้',
  `dntt_total_fat` decimal(6,2) NOT NULL COMMENT 'ไขมันรวมของรายการนี้',
  `dntt_time` time NOT NULL COMMENT 'เวลาที่กิน',
  `dntt_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่บันทึกรายการ',
  `dntt_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `ntt_id` int(11) DEFAULT NULL COMMENT 'รหัสโภชนาการ [FK -> nutrition]',
  PRIMARY KEY (`dntt_id`),
  KEY `ntt_id` (`ntt_id`),
  KEY `daily_nutrition_ibfk_1` (`mb_id`),
  CONSTRAINT `daily_nutrition_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE,
  CONSTRAINT `daily_nutrition_ibfk_2` FOREIGN KEY (`ntt_id`) REFERENCES `nutrition` (`ntt_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=2391 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `exercise_muscle_details`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exercise_muscle_details` (
  `emd_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสรายละเอียดกล้ามเนื้อในท่าฝึก [PK]',
  `exm_type` tinyint(4) NOT NULL COMMENT 'ประเภทของกลุ่มกล้ามเนื้อในการฝึก (1=หลัก, 2=รอง)',
  `wet_id` int(10) unsigned NOT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]',
  `mug_id` int(10) unsigned NOT NULL COMMENT 'รหัสกลุ่มกล้ามเนื้อ [FK -> muscle_group]',
  PRIMARY KEY (`emd_id`),
  UNIQUE KEY `uq_wet_mug` (`wet_id`,`mug_id`),
  KEY `fk_emd_weight` (`wet_id`),
  KEY `fk_emd_muscle` (`mug_id`),
  CONSTRAINT `fk_emd_muscle` FOREIGN KEY (`mug_id`) REFERENCES `muscle_group` (`mug_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_emd_weight` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=127 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_bmr_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_bmr_history` (
  `mbh_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประวัติพลังงานพื้นฐานผู้ใช้ [PK]',
  `mbh_record_date` date NOT NULL COMMENT 'วันที่บันทึกและวิเคราะห์',
  `mbh_bmi` decimal(5,2) NOT NULL COMMENT 'ค่าดัชนีมวลกาย',
  `mbh_bmr` decimal(6,2) NOT NULL COMMENT 'อัตราการเผาผลาญพื้นฐาน',
  `mbh_tdee` decimal(6,2) NOT NULL COMMENT 'พลังงานที่ใช้ต่อวัน',
  `mbh_tdee_target` decimal(6,2) NOT NULL COMMENT 'พลังงานที่ใช้ต่อวันตามเป้าหมาย',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `mbs_id` int(11) DEFAULT NULL COMMENT 'รหัสประวัติร่างกายผู้ใช้ [FK -> member_body_stats]',
  PRIMARY KEY (`mbh_id`),
  UNIQUE KEY `uq_mbh_member_date` (`mb_id`,`mbh_record_date`),
  KEY `mbs_id` (`mbs_id`),
  CONSTRAINT `member_bmr_history_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE,
  CONSTRAINT `member_bmr_history_ibfk_2` FOREIGN KEY (`mbs_id`) REFERENCES `member_body_stats` (`mbs_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=96 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_body_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_body_stats` (
  `mbs_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประวัติร่างกายผู้ใช้ [PK]',
  `mbs_height` decimal(4,1) NOT NULL COMMENT 'ส่วนสูง (ซม.)',
  `mbs_weight` decimal(5,2) NOT NULL COMMENT 'น้ำหนัก (กก.)',
  `mbs_activity_level` decimal(4,3) NOT NULL COMMENT 'Activity Factor ตัวคูณ TDEE (ไม่ใช่ความถี่การออกกำลังกายต่อสัปดาห์) ค่าที่เป็นไปได้: 1.2 / 1.375 / 1.55 / 1.725 / 1.9',
  `mbs_target` tinyint(4) NOT NULL COMMENT 'เป้าหมาย (1=ลดน้ำหนัก, 2=เพิ่มน้ำหนัก, 3=รักษาน้ำหนัก)',
  `mbs_recorded_date` datetime NOT NULL COMMENT 'วันและเวลาที่บันทึกข้อมูล',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  PRIMARY KEY (`mbs_id`),
  KEY `fk_mbs_member` (`mb_id`),
  CONSTRAINT `fk_mbs_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=96 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_profile`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_profile` (
  `mb_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสสมาชิก [PK]',
  `mb_full_name` varchar(100) NOT NULL COMMENT 'ชื่อ - นามสกุล',
  `mb_email` varchar(100) NOT NULL COMMENT 'อีเมลผู้ใช้งาน',
  `mb_password_hash` varchar(255) NOT NULL COMMENT 'รหัสผ่าน (bcrypt hash)',
  `mb_otp` varchar(60) DEFAULT NULL COMMENT 'bcrypt hash เธเธญเธเธฃเธซเธฑเธช OTP (เนเธเธดเธกเนเธเนเธ plaintext เนเธเน 2026-09-29)',
  `mb_otp_expired` datetime DEFAULT NULL COMMENT 'วันและเวลาที่รหัส OTP หมดอายุ',
  `mb_is_verified` tinyint(1) unsigned NOT NULL DEFAULT 0 COMMENT 'สถานะการยืนยันตัวตน (0=ยังไม่ยืนยัน, 1=ยืนยันแล้ว)',
  `mb_birth_date` date DEFAULT NULL COMMENT 'วัน เดือน ปีเกิด',
  `mb_gender` tinyint(4) DEFAULT NULL COMMENT 'เพศ (1=ชาย, 2=หญิง)',
  `mb_profile_pic` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปโปรไฟล์',
  `mb_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่สมัครสมาชิก',
  `mb_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  PRIMARY KEY (`mb_id`),
  UNIQUE KEY `uq_mb_email` (`mb_email`)
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `muscle_group`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `muscle_group` (
  `mug_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสกลุ่มกล้ามเนื้อ [PK]',
  `mug_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพกลุ่มกล้ามเนื้อ',
  `mug_name` varchar(100) NOT NULL COMMENT 'ชื่อกลุ่มกล้ามเนื้อ',
  `mug_zone` tinyint(4) NOT NULL COMMENT 'ส่วนของกล้ามเนื้อ (1=ร่างกายส่วนบน, 2=ร่างกายส่วนล่าง, 3=แกนกลางลำตัว)',
  PRIMARY KEY (`mug_id`),
  UNIQUE KEY `uq_mug_name` (`mug_name`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `nutrition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `nutrition` (
  `ntt_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสโภชนาการ [PK]',
  `ntt_food_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพโภชนาการ',
  `ntt_food_name` varchar(100) NOT NULL COMMENT 'ชื่อโภชนาการ',
  `ntt_protein` decimal(6,2) NOT NULL COMMENT 'โปรตีน (กรัม)',
  `ntt_carbs` decimal(6,2) NOT NULL COMMENT 'คาร์โบไฮเดรต (กรัม)',
  `ntt_fat` decimal(6,2) NOT NULL COMMENT 'ไขมัน (กรัม)',
  `ntt_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ต่อหน่วย',
  `ntt_serving_weight` smallint(5) unsigned NOT NULL COMMENT 'ขนาดต่อหน่วยบริโภค',
  `ntt_unit` varchar(20) NOT NULL COMMENT 'หน่วยนับ (กรัม,ออนซ์)',
  `nttc_id` int(11) NOT NULL COMMENT 'รหัสประเภทโภชนาการ [FK -> nutrition_category]',
  PRIMARY KEY (`ntt_id`),
  UNIQUE KEY `uq_ntt_food_name` (`ntt_food_name`),
  KEY `idx_ntt_nttc_id` (`nttc_id`),
  CONSTRAINT `nutrition_ibfk_1` FOREIGN KEY (`nttc_id`) REFERENCES `nutrition_category` (`nttc_id`)
) ENGINE=InnoDB AUTO_INCREMENT=149 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `nutrition_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `nutrition_category` (
  `nttc_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประเภทโภชนาการ [PK]',
  `nttc_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพประเภทโภชนาการ',
  `nttc_name` varchar(100) NOT NULL COMMENT 'ชื่อประเภทโภชนาการ',
  PRIMARY KEY (`nttc_id`),
  UNIQUE KEY `uq_nttc_name` (`nttc_name`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `plan_template_detail`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `plan_template_detail` (
  `ptd_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสรายละเอียดแผนแนะนำ [PK]',
  `ptd_day_number` tinyint(3) unsigned NOT NULL COMMENT 'ลำดับวันที่ในแผน',
  `ptd_day_name` varchar(50) NOT NULL COMMENT 'ชื่อเรียกวันฝึก',
  `ptd_sets` tinyint(3) unsigned NOT NULL COMMENT 'จำนวนเซต',
  `ptd_reps` varchar(10) NOT NULL COMMENT 'จำนวนครั้ง',
  `ptd_rest_seconds` smallint(5) unsigned DEFAULT 90 COMMENT 'เวลาพัก (วินาที)',
  `ptd_order` tinyint(3) unsigned NOT NULL COMMENT 'ลำดับท่าในวันนั้น',
  `wpt_id` int(10) unsigned NOT NULL COMMENT 'รหัสแผนแนะนำ [FK -> workout_plan_template]',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]',
  PRIMARY KEY (`ptd_id`),
  KEY `fk_ptd_plan` (`wpt_id`),
  KEY `fk_ptd_weight` (`wet_id`),
  CONSTRAINT `fk_ptd_plan` FOREIGN KEY (`wpt_id`) REFERENCES `workout_plan_template` (`wpt_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ptd_weight` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=132 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `revoked_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `revoked_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสโทเคนที่ถูกเพิกถอน [PK]',
  `jti` varchar(64) NOT NULL COMMENT 'รหัสอ้างอิงโทเคน (JWT claim jti) ที่ถูกเพิกถอน',
  `expires_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่โทเคนหมดอายุตามค่า exp ใน JWT',
  `created_at` datetime(3) NOT NULL COMMENT 'วันและเวลาที่เพิกถอนโทเคน',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_revoked_tokens_jti` (`jti`),
  KEY `idx_revoked_tokens_expires_at` (`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=73 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `schema_migrations` (
  `filename` varchar(255) NOT NULL COMMENT 'ชื่อไฟล์ migration ตรงกับใน backend/migrations/ เป๊ะ',
  `applied_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'เวลาที่รัน migration นี้บน DB เครื่องนี้',
  `note` varchar(255) DEFAULT NULL COMMENT 'หมายเหตุเพิ่มเติม (เช่น backfill ประมาณเวลาจาก file mtime)',
  PRIMARY KEY (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='ติดตามว่าไฟล์ backend/migrations/*.sql ไหนรันไปแล้วบน DB เครื่องนี้ (รันมือ ไม่มี auto-runner)';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `system_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `system_data` (
  `sys_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสข้อมูลผู้ดูแลระบบ [PK]',
  `sys_email` varchar(100) NOT NULL COMMENT 'อีเมลผู้ใช้งานระบบ',
  `sys_full_name` varchar(100) NOT NULL COMMENT 'ชื่อ-นามสกุล',
  `sys_organization` varchar(100) NOT NULL DEFAULT '' COMMENT 'หน่วยงานเจ้าของระบบ',
  `sys_start_date` date DEFAULT NULL COMMENT 'วันที่เริ่มใช้ระบบ',
  `sys_password_hash` varchar(255) NOT NULL COMMENT 'รหัสผ่าน',
  `sys_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่สร้างบัญชี',
  `sys_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  PRIMARY KEY (`sys_id`),
  UNIQUE KEY `uq_sys_email` (`sys_email`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `weight_exercises`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `weight_exercises` (
  `wet_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [PK]',
  `wet_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพท่าฝึกเวทเทรนนิ่ง',
  `wet_name` varchar(100) NOT NULL COMMENT 'ชื่อท่าฝึกเวทเทรนนิ่ง',
  `wet_difficulty` tinyint(4) NOT NULL COMMENT 'ระดับของท่าฝึก (1=ง่าย, 2=ปานกลาง, 3=ยาก)',
  `wet_equipment` tinyint(4) NOT NULL COMMENT 'อุปกรณ์ที่ใช้ฝึก (1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight)',
  `wet_exercise_type` tinyint(4) NOT NULL COMMENT 'ประเภทของท่าฝึกตามกลุ่มกล้ามเนื้อ (1=หลายกลุ่ม, 2=เฉพาะส่วน)',
  `wet_is_timed` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'ท่าค้างเวลา ไม่มีจำนวนครั้งให้กรอก (1=ใช่ เช่น Plank, 0=นับจำนวนครั้งได้)',
  `wet_description` text NOT NULL COMMENT 'คำอธิบายวิธีฝึก',
  `wet_technique` text NOT NULL COMMENT 'เทคนิคในการฝึก',
  `wet_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอแนะนำวิธีฝึก',
  `wet_loop_video` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path วิดีโอ Loop เวทเทรนนิ่ง',
  PRIMARY KEY (`wet_id`),
  UNIQUE KEY `uq_wet_name` (`wet_name`)
) ENGINE=InnoDB AUTO_INCREMENT=56 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `weight_training_result`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `weight_training_result` (
  `wtrs_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสผลการฝึกเวทเทรนนิ่ง [PK]',
  `wtrs_date` date NOT NULL COMMENT 'วันที่บันทึกผลการฝึก',
  `wtrs_set_no` tinyint(3) unsigned NOT NULL COMMENT 'หมายเลขเซต',
  `wtrs_weight` decimal(5,2) NOT NULL COMMENT 'น้ำหนักที่ยกได้',
  `wtrs_reps` smallint(5) unsigned NOT NULL COMMENT 'จำนวนครั้งที่ยกได้',
  `wtrs_work_seconds` smallint(5) unsigned NOT NULL COMMENT 'เวลาที่ใช้ทำเซตนี้ (วินาที) นับตั้งแต่จบการพักรอบก่อน/เริ่มฝึก จนถึงกดพัก',
  `wtrs_rest_seconds` smallint(5) unsigned DEFAULT NULL COMMENT 'เวลาพักหลังเซตนั้น (หน่วยวินาที)',
  `wtrs_near_failure` tinyint(1) unsigned DEFAULT NULL COMMENT 'คำตอบผู้ใช้ตอนไม่มี PR: 1=หมดแรงแล้ว (ยกต่อได้ไม่เกิน 2-3 ครั้ง) 0=ยังยกได้อีก NULL=ไม่ได้ถาม',
  `wtrs_calories` decimal(6,2) NOT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]',
  `wsch_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางเวทเทรนนิ่ง [FK -> workout_schedules] NULL = ฝึกนอกแผนที่วางไว้',
  PRIMARY KEY (`wtrs_id`),
  KEY `idx_wtrs_wet_id` (`wet_id`),
  KEY `idx_wtrs_wsch_id` (`wsch_id`),
  KEY `fk_wtrs_member` (`mb_id`),
  CONSTRAINT `fk_wtrs_exercise` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_wtrs_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wtrs_schedule` FOREIGN KEY (`wsch_id`) REFERENCES `workout_schedules` (`wsch_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=6810 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `workout_plan_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workout_plan_template` (
  `wpt_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสแผนแนะนำ [PK]',
  `wpt_image` varchar(255) NOT NULL DEFAULT '' COMMENT 'Path รูปภาพแผน',
  `wpt_name` varchar(100) NOT NULL COMMENT 'ชื่อแผนการฝึก',
  `wpt_description` text NOT NULL COMMENT 'คำอธิบายแผน',
  `wpt_days_per_week` tinyint(3) unsigned NOT NULL COMMENT 'จำนวนวันฝึกต่อสัปดาห์',
  `wpt_difficulty` tinyint(4) NOT NULL COMMENT 'ระดับความยาก (1=ระดับเริ่มต้น, 2=ระดับกลาง, 3=ระดับสูง)',
  PRIMARY KEY (`wpt_id`),
  UNIQUE KEY `uq_wpt_name` (`wpt_name`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `workout_schedules`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workout_schedules` (
  `wsch_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสตารางเวทเทรนนิ่ง [PK]',
  `wsch_plan_name` varchar(100) NOT NULL COMMENT 'ชื่อแผนที่สมาชิกกำหนด',
  `wsch_days_per_week` tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันฝึกต่อสัปดาห์ของแผน',
  `wsch_day_number` tinyint(4) NOT NULL DEFAULT 0 COMMENT 'วันในสัปดาห์ที่ฝึก',
  `wsch_day_name` varchar(50) DEFAULT NULL COMMENT 'ชื่อเรียกวันฝึก',
  `wsch_order` tinyint(4) NOT NULL COMMENT 'ลำดับท่าในวันนั้น',
  `wsch_sets` tinyint(4) NOT NULL DEFAULT 3 COMMENT 'จำนวนเซต',
  `wsch_reps` varchar(10) NOT NULL DEFAULT '10' COMMENT 'จำนวนครั้ง',
  `wsch_rest_seconds` smallint(5) unsigned NOT NULL DEFAULT 90 COMMENT 'เวลาพัก (วินาที)',
  `wsch_plan_created_at` datetime DEFAULT current_timestamp() COMMENT 'วันที่สร้างแผน',
  `wsch_plan_updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขแผนล่าสุด',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `wpt_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสแผนแนะนำ [FK -> workout_plan_template], NULL = สร้างแผนเอง',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [FK -> weight_exercises]',
  PRIMARY KEY (`wsch_id`),
  KEY `idx_wsch_wet_id` (`wet_id`),
  KEY `fk_wsch_wpt` (`wpt_id`),
  KEY `fk_wsch_member` (`mb_id`),
  CONSTRAINT `fk_wsch_exercise` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wsch_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wsch_wpt` FOREIGN KEY (`wpt_id`) REFERENCES `workout_plan_template` (`wpt_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=397 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;


SET FOREIGN_KEY_CHECKS=1;

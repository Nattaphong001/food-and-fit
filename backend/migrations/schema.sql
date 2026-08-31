
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
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสบันทึกการทำงานของระบบ (Audit Log) [PK]',
  `actor_type` varchar(20) DEFAULT NULL,
  `actor_id` bigint(20) DEFAULT NULL,
  `action` varchar(50) DEFAULT NULL,
  `detail` varchar(255) DEFAULT NULL,
  `table_name` varchar(64) DEFAULT NULL,
  `record_id` varchar(64) DEFAULT NULL,
  `old_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_value`)),
  `new_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_value`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_audit_logs_actor_type` (`actor_type`),
  KEY `idx_audit_logs_actor_id` (`actor_id`),
  KEY `idx_audit_logs_action` (`action`),
  KEY `idx_audit_logs_created_at` (`created_at`),
  KEY `idx_audit_table_record` (`table_name`,`record_id`),
  KEY `idx_audit_logs_target_table` (`table_name`)
) ENGINE=InnoDB AUTO_INCREMENT=918 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio` (
  `cdo_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสคาร์ดิโอ [PK]',
  `cdo_name` varchar(100) NOT NULL COMMENT 'ชื่อกิจกรรมคาร์ดิโอ',
  `cdo_mets` decimal(4,2) NOT NULL DEFAULT 0.00 COMMENT 'ค่าความเข้มข้นของกิจกรรม (METs)',
  `cdo_description` text DEFAULT NULL COMMENT 'คำอธิบายกิจกรรมคาร์ดิโอ',
  `cdo_technique` text DEFAULT NULL COMMENT 'เทคนิคในการฝึก',
  `cdo_image` varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพกิจกรรม',
  `cdo_video` varchar(255) DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก',
  `cdc_id` int(10) unsigned NOT NULL DEFAULT 1 COMMENT 'รหัสประเภทคาร์ดิโอ [FK -> cardio_category]',
  `cdo_has_distance` tinyint(4) NOT NULL DEFAULT 0 COMMENT 'แสดงช่องกรอกระยะทาง (0=ไม่แสดง, 1=แสดง)',
  `cdo_loop_video` varchar(255) DEFAULT NULL COMMENT 'path ไฟล์วิดีโอ loop คาร์ดิโอ',
  PRIMARY KEY (`cdo_id`),
  UNIQUE KEY `uq_cdo_name` (`cdo_name`),
  KEY `idx_cdo_category` (`cdc_id`),
  CONSTRAINT `fk_cardio_category` FOREIGN KEY (`cdc_id`) REFERENCES `cardio_category` (`cdc_id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=24 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio_category` (
  `cdc_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสประเภทคาร์ดิโอ [PK]',
  `cdc_name` varchar(100) NOT NULL COMMENT 'ชื่อประเภท (LISS, HIIT, etc.)',
  `cdc_description` text DEFAULT NULL COMMENT 'คำอธิบายย่อ',
  `cdc_image` varchar(255) DEFAULT NULL COMMENT 'เธฃเธนเธเธซเธกเธงเธเธซเธกเธนเนเธเธฒเธฃเนเธเธดเนเธญ (path)',
  PRIMARY KEY (`cdc_id`),
  UNIQUE KEY `uq_cdc_name` (`cdc_name`)
) ENGINE=InnoDB AUTO_INCREMENT=24 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cardio_result`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cardio_result` (
  `cdors_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสผลการฝึกคาร์ดิโอ [PK]',
  `cdors_date` date DEFAULT NULL COMMENT 'วันที่ทำกิจกรรมคาร์ดิโอ',
  `cdors_duration` int(11) DEFAULT NULL COMMENT 'ระยะเวลา (นาที)',
  `cdors_distance` decimal(5,2) DEFAULT 0.00 COMMENT 'ระยะทาง (กม.)',
  `cdors_calories` decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญได้',
  `mb_id` int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก (FK -> member_profile)',
  `cdo_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสคาร์ดิโอ (FK -> cardio)',
  PRIMARY KEY (`cdors_id`),
  KEY `idx_cdors_mb_id` (`mb_id`),
  KEY `idx_cdors_cdo_id` (`cdo_id`),
  KEY `idx_cdors_date` (`cdors_date`),
  CONSTRAINT `fk_cdors_cardio` FOREIGN KEY (`cdo_id`) REFERENCES `cardio` (`cdo_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_cdors_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `daily_nutrition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `daily_nutrition` (
  `dntt_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสบันทึกโภชนาการประจำวัน [PK]',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `ntt_id` int(11) DEFAULT NULL COMMENT 'รหัสโภชนาการอาหาร [FK -> nutrition]',
  `dntt_date` date NOT NULL COMMENT 'วันที่บันทึก',
  `dntt_time` time DEFAULT NULL COMMENT 'เวลาที่รับประทาน',
  `dntt_meal_type` tinyint(4) DEFAULT NULL COMMENT 'มื้ออาหาร (1=เช้า, 2=กลาง, 3=เย็น, 4=ว่าง)',
  `dntt_food_name` varchar(100) DEFAULT NULL COMMENT 'ชื่ออาหารที่บันทึก',
  `dntt_quantity` decimal(5,2) DEFAULT NULL COMMENT 'จำนวนที่บริโภค',
  `dntt_unit` varchar(50) DEFAULT NULL COMMENT 'หน่วยนับของอาหาร',
  `dntt_total_calories` decimal(7,2) DEFAULT NULL COMMENT 'ผลรวมแคลอรี่สุทธิ',
  `dntt_total_protein` decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมโปรตีนสุทธิ (กรัม)',
  `dntt_total_carb` decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมคาร์โบไฮเดรตสุทธิ (กรัม)',
  `dntt_total_fat` decimal(5,2) DEFAULT NULL COMMENT 'ผลรวมไขมันสุทธิ (กรัม)',
  `dntt_image` varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพอาหาร',
  `dntt_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่บันทึกรายการ',
  `dntt_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  PRIMARY KEY (`dntt_id`),
  KEY `ntt_id` (`ntt_id`),
  KEY `idx_dntt_mb_id` (`mb_id`),
  KEY `idx_dntt_date` (`dntt_date`),
  KEY `idx_dntt_meal_type` (`dntt_meal_type`),
  CONSTRAINT `daily_nutrition_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE,
  CONSTRAINT `daily_nutrition_ibfk_2` FOREIGN KEY (`ntt_id`) REFERENCES `nutrition` (`ntt_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=265 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `exercise_muscle_details`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `exercise_muscle_details` (
  `emd_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสรายละเอียดกล้ามเนื้อในท่าฝึก [PK]',
  `wet_id` int(10) unsigned NOT NULL COMMENT 'รหัสท่าฝึกเวท [FK -> weight_exercises]',
  `mug_id` int(10) unsigned NOT NULL COMMENT 'รหัสกลุ่มกล้ามเนื้อ [FK -> muscle_group]',
  `exm_type` tinyint(4) NOT NULL COMMENT 'ประเภทของกลุ่มกล้ามเนื้อในการฝึก (1=หลัก, 2=รอง)',
  PRIMARY KEY (`emd_id`),
  UNIQUE KEY `uq_wet_mug` (`wet_id`,`mug_id`),
  KEY `fk_emd_weight` (`wet_id`),
  KEY `fk_emd_muscle` (`mug_id`),
  CONSTRAINT `fk_emd_muscle` FOREIGN KEY (`mug_id`) REFERENCES `muscle_group` (`mug_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_emd_weight` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=126 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_bmr_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_bmr_history` (
  `mbh_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประวัติพลังงานพื้นฐานผู้ใช้ [PK]',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `mbs_id` int(11) DEFAULT NULL COMMENT 'รหัสประวัติร่างกายผู้ใช้ [FK -> member_body_stats]',
  `mbh_record_date` date NOT NULL COMMENT 'วันที่บันทึกและวิเคราะห์',
  `mbh_bmi` decimal(4,2) DEFAULT NULL COMMENT 'ค่าดัชนีมวลกาย (BMI)',
  `mbh_bmr` decimal(7,2) DEFAULT NULL COMMENT 'Basal Metabolic Rate (อัตราการเผาผลาญพื้นฐาน)',
  `mbh_tdee` decimal(7,2) DEFAULT NULL COMMENT 'Total Daily Energy Expenditure (พลังงานรวมที่เผาผลาญต่อวัน)',
  `mbh_tdee_target` decimal(7,2) DEFAULT NULL COMMENT 'TDEE เป้าหมาย',
  PRIMARY KEY (`mbh_id`),
  KEY `mbs_id` (`mbs_id`),
  KEY `idx_mbh_mb_id` (`mb_id`),
  KEY `idx_mbh_record_date` (`mbh_record_date`),
  CONSTRAINT `member_bmr_history_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE,
  CONSTRAINT `member_bmr_history_ibfk_2` FOREIGN KEY (`mbs_id`) REFERENCES `member_body_stats` (`mbs_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=60 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_body_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_body_stats` (
  `mbs_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประวัติร่างกายผู้ใช้ [PK]',
  `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิก [FK -> member_profile]',
  `mbs_weight` decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนัก (กก.)',
  `mbs_height` decimal(5,2) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)',
  `mbs_activity_level` decimal(4,3) DEFAULT NULL,
  `mbs_target` tinyint(4) DEFAULT NULL COMMENT '1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก',
  `mbs_recorded_date` datetime DEFAULT current_timestamp() COMMENT 'วันและเวลาที่บันทึกข้อมูล',
  PRIMARY KEY (`mbs_id`),
  KEY `idx_mbs_mb_id` (`mb_id`),
  CONSTRAINT `member_body_stats_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=60 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_profile`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_profile` (
  `mb_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสสมาชิก [PK]',
  `mb_email` varchar(100) NOT NULL COMMENT 'อีเมลผู้ใช้งาน',
  `mb_password_hash` varchar(255) NOT NULL COMMENT 'รหัสผ่าน (Hash)',
  `mb_full_name` varchar(100) NOT NULL COMMENT 'ชื่อ-นามสกุล',
  `mb_gender` tinyint(4) DEFAULT NULL COMMENT '1=ชาย, 2=หญิง',
  `mb_birth_date` date DEFAULT NULL COMMENT 'วัน เดือน ปีเกิด',
  `mb_profile_pic` varchar(255) DEFAULT NULL COMMENT 'Path รูปโปรไฟล์',
  `mb_is_verified` tinyint(4) DEFAULT 0 COMMENT '0=ยังไม่ยืนยัน, 1=ยืนยันแล้ว',
  `mb_otp` varchar(6) DEFAULT NULL COMMENT 'รหัสยืนยันตัวตน 6 หลัก (OTP)',
  `mb_otp_expired` datetime DEFAULT NULL COMMENT 'วันและเวลาที่รหัส OTP หมดอายุ',
  `mb_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่สมัครสมาชิก',
  `mb_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  `mb_status` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'สถานะบัญชี (1=Active, 2=Deleted)',
  `mb_active_wpt_id` int(10) unsigned DEFAULT NULL,
  `mb_active_mwp_id` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`mb_id`),
  UNIQUE KEY `mb_email` (`mb_email`),
  KEY `idx_mb_email` (`mb_email`),
  KEY `idx_mb_is_verified` (`mb_is_verified`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `member_workout_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `member_workout_plans` (
  `mwp_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `mb_id` int(11) NOT NULL,
  `mwp_name` varchar(100) NOT NULL,
  `mwp_days_per_week` int(11) NOT NULL DEFAULT 7,
  `mwp_created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`mwp_id`),
  KEY `fk_mwp_member` (`mb_id`),
  CONSTRAINT `fk_mwp_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `muscle_group`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `muscle_group` (
  `mug_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสกลุ่มกล้ามเนื้อ [PK]',
  `mug_name` varchar(100) NOT NULL COMMENT 'ชื่อกลุ่มกล้ามเนื้อ',
  `mug_zone` tinyint(4) NOT NULL DEFAULT 1 COMMENT 'โซน (1=ท่อนบน, 2=ท่อนล่าง, 3=แกนกลาง)',
  `mug_image` varchar(255) DEFAULT NULL COMMENT 'รูปกล้ามเนื้อ (path)',
  PRIMARY KEY (`mug_id`),
  UNIQUE KEY `uq_mug_name` (`mug_name`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `nutrition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `nutrition` (
  `ntt_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสโภชนาการอาหาร [PK]',
  `ntt_food_name` varchar(100) NOT NULL COMMENT 'ชื่ออาหาร',
  `ntt_calories` decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ต่อหน่วย',
  `ntt_serving_weight` int(11) DEFAULT NULL COMMENT 'ขนาดต่อหน่วย (ก.)',
  `ntt_unit` varchar(50) DEFAULT NULL COMMENT 'หน่วยนับ',
  `ntt_protein` decimal(5,1) DEFAULT NULL COMMENT 'โปรตีน (ก.)',
  `ntt_carbs` decimal(5,1) DEFAULT NULL COMMENT 'คาร์บ (ก.)',
  `ntt_fat` decimal(5,1) DEFAULT NULL COMMENT 'ไขมัน (ก.)',
  `ntt_food_image` varchar(255) DEFAULT NULL COMMENT 'Path รูปอาหาร',
  `nttc_id` int(11) NOT NULL COMMENT 'รหัสประเภทอาหาร [FK -> nutrition_category]',
  PRIMARY KEY (`ntt_id`),
  UNIQUE KEY `uq_ntt_food_name` (`ntt_food_name`),
  KEY `idx_ntt_nttc_id` (`nttc_id`),
  KEY `idx_ntt_food_name` (`ntt_food_name`),
  KEY `idx_ntt_calories` (`ntt_calories`),
  CONSTRAINT `nutrition_ibfk_1` FOREIGN KEY (`nttc_id`) REFERENCES `nutrition_category` (`nttc_id`)
) ENGINE=InnoDB AUTO_INCREMENT=167 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `nutrition_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `nutrition_category` (
  `nttc_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสประเภทอาหาร [PK]',
  `nttc_name` varchar(100) NOT NULL COMMENT 'ชื่อประเภทอาหาร',
  `nttc_image` varchar(255) DEFAULT NULL COMMENT 'เธฃเธนเธเธซเธกเธงเธ”เธซเธกเธนเนเนเธ เธเธเธฒเธเธฒเธฃ (path)',
  PRIMARY KEY (`nttc_id`),
  UNIQUE KEY `uq_nttc_name` (`nttc_name`)
) ENGINE=InnoDB AUTO_INCREMENT=10010 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `plan_template_detail`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `plan_template_detail` (
  `ptd_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสรายละเอียดแม่แบบแผนการออกกำลังกาย [PK]',
  `wpt_id` int(10) unsigned NOT NULL COMMENT 'เชื่อมกับหัวข้อแผน [FK -> workout_plan_template]',
  `ptd_day_number` int(11) NOT NULL COMMENT 'วันที่เท่าไหร่ของแผน (1, 2, 3...)',
  `ptd_day_name` varchar(50) DEFAULT NULL COMMENT 'ชื่อเรียกวัน (เช่น Push Day, Upper Body)',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าเวท (ถ้ามี) [FK -> weight_exercises]',
  `ptd_sets` int(11) DEFAULT NULL COMMENT 'จำนวนเซต',
  `ptd_reps` varchar(20) DEFAULT NULL COMMENT 'จำนวนครั้ง (เช่น 8-12)',
  `ptd_rest_seconds` int(11) DEFAULT 90 COMMENT 'เวลาพัก (วินาที)',
  `ptd_order` int(11) NOT NULL DEFAULT 1 COMMENT 'ลำดับท่าในวันนั้น',
  PRIMARY KEY (`ptd_id`),
  KEY `fk_ptd_plan` (`wpt_id`),
  KEY `fk_ptd_weight` (`wet_id`),
  CONSTRAINT `fk_ptd_plan` FOREIGN KEY (`wpt_id`) REFERENCES `workout_plan_template` (`wpt_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ptd_weight` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=252 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `revoked_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `revoked_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสโทเคนที่ถูกเพิกถอน [PK]',
  `jti` varchar(64) NOT NULL,
  `expires_at` datetime(3) NOT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_revoked_tokens_jti` (`jti`),
  KEY `idx_revoked_tokens_expires_at` (`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=42 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `system_data`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `system_data` (
  `sys_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'รหัสข้อมูลผู้ดูแลระบบ [PK]',
  `sys_email` varchar(100) NOT NULL COMMENT 'อีเมลผู้ใช้งานระบบ',
  `sys_password_hash` varchar(255) NOT NULL COMMENT 'รหัสผ่าน (Hash)',
  `sys_full_name` varchar(100) NOT NULL COMMENT 'ชื่อ-นามสกุล',
  `sys_organization` varchar(100) DEFAULT NULL COMMENT 'หน่วยงานเจ้าของระบบ',
  `sys_start_date` date DEFAULT NULL COMMENT 'วันที่เริ่มใช้ระบบ',
  `sys_status` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'เธชเธเธฒเธเธฐเธเธฑเธเธเธตเธเธนเนเธเธนเนเธฅเธฃเธฐเธเธ (1=เนเธเนเธเธฒเธ, 0=เธเธดเธเนเธเนเธเธฒเธ)',
  `sys_created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'วันที่สร้างบัญชี',
  `sys_updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'วันที่แก้ไขข้อมูลล่าสุด',
  PRIMARY KEY (`sys_id`),
  UNIQUE KEY `sys_email` (`sys_email`),
  KEY `idx_sys_email` (`sys_email`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `weight_exercises`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `weight_exercises` (
  `wet_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสท่าฝึกเวทเทรนนิ่ง [PK]',
  `wet_name` varchar(100) NOT NULL COMMENT 'ชื่อท่าฝึกเวทเทรนนิ่ง',
  `wet_description` text DEFAULT NULL COMMENT 'คำอธิบายวิธีฝึก',
  `wet_technique` text DEFAULT NULL COMMENT 'เทคนิคในการฝึก',
  `wet_difficulty` tinyint(4) NOT NULL DEFAULT 1 COMMENT '1=ง่าย, 2=กลาง, 3=ยาก',
  `wet_equipment` tinyint(4) NOT NULL DEFAULT 5 COMMENT '1=Barbell, 2=Dumbbell, 3=Machine, 4=Cable, 5=Bodyweight',
  `wet_image` varchar(255) DEFAULT NULL COMMENT 'Path รูปกิจกรรม',
  `wet_video` varchar(255) DEFAULT NULL COMMENT 'Path วิดีโอแนะนำวิธีฝึก',
  `mug_id` int(10) unsigned DEFAULT NULL COMMENT 'FK -> muscle_group (กลุ่มกล้ามเนื้อหลัก)',
  `wet_loop_video` varchar(255) DEFAULT NULL COMMENT 'path ไฟล์วิดีโอ loop ท่าฝึก (สั้น 2-4 วิ ไม่มีเสียง)',
  `wet_exercise_type` tinyint(4) NOT NULL DEFAULT 1 COMMENT '1=หลายกลุ่ม 2=เฉพาะส่วน',
  PRIMARY KEY (`wet_id`),
  UNIQUE KEY `uq_wet_name` (`wet_name`),
  KEY `idx_wet_muscle` (`mug_id`),
  KEY `idx_wet_difficulty` (`wet_difficulty`),
  CONSTRAINT `fk_wet_muscle_group` FOREIGN KEY (`mug_id`) REFERENCES `muscle_group` (`mug_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=66 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `weight_training_result`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `weight_training_result` (
  `wtrs_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสผลการฝึกเวทเทรนนิ่ง [PK]',
  `wtrs_date` date DEFAULT NULL COMMENT 'วันที่บันทึกผลการฝึก',
  `wtrs_set_no` int(11) DEFAULT NULL COMMENT 'หมายเลขเซต',
  `wtrs_reps` int(11) DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้',
  `wtrs_weight` decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักที่ยก (กก.)',
  `wtrs_intensity_level` tinyint(4) DEFAULT 2 COMMENT 'ระดับความหนัก (1=เบา, 2=กลาง, 3=หนัก) ใช้กำหนดค่า MET',
  `wtrs_calories` decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ',
  `mb_id` int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก (FK -> member_profile)',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท (FK -> weight_exercises)',
  `wsch_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางฝึก (FK -> workout_schedules, NULL ได้หากฝึกนอกแผน)',
  PRIMARY KEY (`wtrs_id`),
  KEY `idx_wtrs_mb_id` (`mb_id`),
  KEY `idx_wtrs_wet_id` (`wet_id`),
  KEY `idx_wtrs_wsch_id` (`wsch_id`),
  KEY `idx_wtrs_date` (`wtrs_date`),
  CONSTRAINT `fk_wtrs_exercise` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_wtrs_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wtrs_schedule` FOREIGN KEY (`wsch_id`) REFERENCES `workout_schedules` (`wsch_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=532 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `weight_training_result_bak_20260820`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `weight_training_result_bak_20260820` (
  `wtrs_id` int(10) unsigned NOT NULL DEFAULT 0 COMMENT 'รหัสผลการฝึกเวทเทรนนิ่ง [PK]',
  `wtrs_date` date DEFAULT NULL COMMENT 'วันที่บันทึกผลการฝึก',
  `wtrs_set_no` int(11) DEFAULT NULL COMMENT 'หมายเลขเซต',
  `wtrs_reps` int(11) DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้',
  `wtrs_weight` decimal(5,2) DEFAULT NULL COMMENT 'น้ำหนักที่ยก (กก.)',
  `wtrs_intensity_level` tinyint(4) DEFAULT 2 COMMENT 'ระดับความหนัก (1=เบา, 2=กลาง, 3=หนัก) ใช้กำหนดค่า MET',
  `wtrs_calories` decimal(7,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ',
  `mb_id` int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก (FK -> member_profile)',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท (FK -> weight_exercises)',
  `wsch_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสตารางฝึก (FK -> workout_schedules, NULL ได้หากฝึกนอกแผน)'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `workout_plan_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workout_plan_template` (
  `wpt_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสแม่แบบแผนการออกกำลังกาย [PK]',
  `wpt_name` varchar(100) NOT NULL COMMENT 'ชื่อแผน (เช่น Full Body 2 Days)',
  `wpt_description` text DEFAULT NULL COMMENT 'คำอธิบายแผนและจุดเด่น',
  `wpt_days_per_week` int(11) NOT NULL DEFAULT 3 COMMENT 'จำนวนวันที่ต้องเข้ายิม/สัปดาห์',
  `wpt_difficulty` tinyint(4) NOT NULL DEFAULT 1 COMMENT '1=Beginner, 2=Intermediate, 3=Advanced',
  `wpt_image` varchar(255) DEFAULT NULL COMMENT 'Path รูปภาพแผน',
  PRIMARY KEY (`wpt_id`),
  UNIQUE KEY `uq_wpt_name` (`wpt_name`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `workout_schedules`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `workout_schedules` (
  `wsch_id` int(10) unsigned NOT NULL AUTO_INCREMENT COMMENT 'รหัสตารางกำหนดการออกกำลังกาย [PK]',
  `wsch_date` date DEFAULT NULL,
  `mb_id` int(11) DEFAULT NULL COMMENT 'รหัสสมาชิก (FK -> member_profile)',
  `wet_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสท่าฝึกเวท (FK -> weight_exercises)',
  `wpt_id` int(10) unsigned DEFAULT NULL COMMENT 'รหัสแผนระบบ (FK -> workout_plan_template) NULL ถ้าเป็นแผนส่วนตัว',
  `mwp_id` int(10) unsigned DEFAULT NULL,
  `wsch_day_number` bigint(20) DEFAULT 0,
  `wsch_day_name` varchar(50) DEFAULT NULL,
  `wsch_sets` bigint(20) DEFAULT 3,
  `wsch_rest_seconds` bigint(20) DEFAULT 90,
  `wsch_reps` varchar(20) DEFAULT '10',
  `wsch_order` bigint(20) DEFAULT 1,
  PRIMARY KEY (`wsch_id`),
  KEY `idx_wsch_mb_id` (`mb_id`),
  KEY `idx_wsch_wet_id` (`wet_id`),
  KEY `idx_wsch_wpt_id` (`wpt_id`),
  KEY `fk_wsch_mwp` (`mwp_id`),
  KEY `idx_wsch_date` (`wsch_date`),
  CONSTRAINT `fk_wsch_exercise` FOREIGN KEY (`wet_id`) REFERENCES `weight_exercises` (`wet_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wsch_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_wsch_mwp` FOREIGN KEY (`mwp_id`) REFERENCES `member_workout_plans` (`mwp_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wsch_plan_template` FOREIGN KEY (`wpt_id`) REFERENCES `workout_plan_template` (`wpt_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `chk_wsch_plan_source` CHECK (`wpt_id` is null and `mwp_id` is not null or `wpt_id` is not null and `mwp_id` is null)
) ENGINE=InnoDB AUTO_INCREMENT=844 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;


-- เพิ่มคอลัมน์รองรับสูตรคำนวณแคลอรี่เวทเทรนนิ่งแบบใหม่ (Smart Auto Calorie — ดูสรุปการออกแบบ
-- ในบทสนทนา 2026-09-08) แทนที่ระบบเดิมที่ผู้ใช้เลือกความหนัก 3 ระดับเอง (wtrs_intensity_level)
-- ซึ่งตรวจแล้วพบว่าไม่เคยทำงานจริง — mobile ไม่เคยส่งค่านี้ขึ้น API เลย ทุกแถวใน DB จริง (6 แถว)
-- เป็นค่า fallback = 1 (เบา) หมด (ยืนยันด้วย SELECT จริง 2026-09-08)
--
-- ⚠️ ต้องรันด้วย: mysql -u root food_and_fit_db --default-character-set=utf8mb4 < <ไฟล์นี้>
--    ห้ามรันแบบไม่ระบุ --default-character-set=utf8mb4 (client เครื่องนี้ default tis620 ทำข้อความไทยเพี้ยน)
--
-- Backup ก่อนรัน (ทำไว้แล้ว 2026-09-08):
--   migrations/backups/backup_weight_exercises_before_base_met_20260908.sql
--   migrations/backups/backup_weight_training_result_before_duration_cols_20260908.sql
--
-- Rollback:
--   ALTER TABLE weight_exercises DROP COLUMN wet_base_met;
--   ALTER TABLE weight_training_result DROP COLUMN wtrs_active_seconds, DROP COLUMN wtrs_duration;

-- ═══════════════════════════════════════════════════════════════════════
-- 1) weight_exercises.wet_base_met — MET พื้นฐานของท่า (ก่อนปรับด้วยน้ำหนัก/ความหนาแน่น)
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE weight_exercises
  ADD COLUMN wet_base_met DECIMAL(3,1) NOT NULL DEFAULT 4.5
  COMMENT 'MET พื้นฐานของท่านี้ ก่อนปรับด้วย %1RM และความหนาแน่นการฝึก — อิงช่วง 3.5-6.0 ของ 2011/2024 Compendium of Physical Activities รหัสเวทเทรนนิ่ง แบ่งกลุ่มโดยผู้พัฒนา: 3.0=ท่าเดี่ยวข้อต่อเดียว, 4.5=ท่าผสมหลายข้อต่อช่วงบน, 5.5=ท่าผสมหลายข้อต่อช่วงล่าง, 7.0=ท่าผสมทั้งตัว/ยกลักษณะ Olympic'
  AFTER wet_exercise_type;

-- Step A: isolation (wet_exercise_type = 2) → 3.0 (14 ท่า)
UPDATE weight_exercises
SET wet_base_met = 3.0
WHERE wet_exercise_type = 2;

-- Step B: compound ช่วงล่าง — primary muscle (exm_type=1) อยู่ใน ขา(7)/ก้นและหลังขา(8) → 5.5
-- ยกเว้น wet_id 7,41 ที่จะ override เป็น full-body ในขั้นถัดไป
UPDATE weight_exercises we
JOIN exercise_muscle_details emd ON emd.wet_id = we.wet_id AND emd.exm_type = 1
JOIN muscle_group mg ON mg.mug_id = emd.mug_id
SET we.wet_base_met = 5.5
WHERE we.wet_exercise_type = 1
  AND mg.mug_id IN (7, 8)
  AND we.wet_id NOT IN (7, 41);

-- Step C: compound ช่วงบน — primary muscle อยู่ใน อก/หลัง/ไหล่/หน้าแขน/หลังแขน/ท่อนแขน(1-6) → 4.5
-- (เท่ากับ DEFAULT อยู่แล้ว แต่เขียนชัดเจนเพื่อความชัดเจนของ intent)
UPDATE weight_exercises we
JOIN exercise_muscle_details emd ON emd.wet_id = we.wet_id AND emd.exm_type = 1
JOIN muscle_group mg ON mg.mug_id = emd.mug_id
SET we.wet_base_met = 4.5
WHERE we.wet_exercise_type = 1
  AND mg.mug_id IN (1, 2, 3, 4, 5, 6)
  AND we.wet_id NOT IN (7, 41);

-- Step D: manual override — full-body/loaded-carry (ตรวจแล้วกล้ามเนื้อที่ใช้ครอบคลุมทั้ง 3 โซน
-- บน/ล่าง/แกนกลาง พร้อมกัน — เป็นเหตุผลที่ตัดสินใจเอง ไม่ได้มาจากงานวิจัยเฉพาะ ต้องประกาศในบทที่ 2):
--   wet_id 7  = Deadlift      (หลัง[บน] + ก้นและหลังขา/ขา[ล่าง] + หน้าท้องและแกนกลาง[แกนกลาง])
--   wet_id 41 = Farmers Walk  (ท่อนแขน/หลัง[บน] + ขา[ล่าง] + หน้าท้องและแกนกลาง[แกนกลาง])
UPDATE weight_exercises
SET wet_base_met = 7.0
WHERE wet_id IN (7, 41);

-- Step E: manual override — ท่าคอร์ isometric/bodyweight ที่ DB ติดป้าย wet_exercise_type=1
-- (compound) ไว้ตามนิยาม "ใช้หลายกลุ่มกล้ามเนื้อ" แต่ profile การออกแรงจริงใกล้เคียงท่าเดี่ยว
-- มากกว่าท่าผสมยกน้ำหนักหนัก (Plank/Hanging Leg Raise ไม่มีการเคลื่อนไหวรับน้ำหนักภายนอกแบบ
-- squat/press) — ตัดสินใจเอง ต้องประกาศในบทที่ 2 เช่นกัน:
--   wet_id 34 = Plank, wet_id 35 = Hanging Leg Raise
UPDATE weight_exercises
SET wet_base_met = 3.0
WHERE wet_id IN (34, 35);

-- ═══════════════════════════════════════════════════════════════════════
-- 2) weight_training_result — เก็บเวลาที่ใช้จริง (เดิมไม่มีคอลัมน์เวลาเลย ทั้งที่ mobile
--    จับเวลาไว้อยู่แล้ว (_globalSeconds, _activeSetSeconds) แต่ไม่เคยส่งขึ้น API — backend
--    คำนวณแคลอรี่จาก duration ที่รับมาแล้วทิ้ง ตรวจย้อนหลัง/คำนวณใหม่ไม่ได้เลย)
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE weight_training_result
  ADD COLUMN wtrs_active_seconds SMALLINT UNSIGNED DEFAULT NULL
    COMMENT 'เวลาออกแรงจริงของเซตนี้ (วินาที) เก็บเป็นหลักฐานตรวจสอบย้อนหลังเท่านั้น สูตร Smart Auto Calorie ไม่ได้ใช้คอลัมน์นี้ — ฐานเวลาที่ใช้คำนวณจริงคือ wtrs_duration (เวลารวมทั้งเซสชัน รวมพัก)'
    AFTER wtrs_reps,
  ADD COLUMN wtrs_duration SMALLINT UNSIGNED DEFAULT NULL
    COMMENT 'เวลารวมทั้งเซสชันการฝึกท่านี้ (วินาที, รวมพัก) ค่าเดียวกันซ้ำทุกแถวของเซสชันเดียวกัน — ห้าม SUM ข้ามแถว (จะได้ค่าคูณด้วยจำนวนเซต) ดูค่าจากแถวใดแถวหนึ่งพอ เหมือนหลักการเดียวกับ wtrs_calories ที่ถูกหารเฉลี่ยแล้วก่อนเก็บ'
    AFTER wtrs_active_seconds;

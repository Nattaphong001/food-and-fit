-- 2026-09-29 — เปลี่ยนวิธีกำหนด METs เวทเทรนนิ่ง จาก Session MET + RIR (ตัดสินระดับความหนักตอนบันทึก
-- ผลแต่ละเซสชัน) มาเป็น METs คงที่ต่อท่า (กำหนดไว้ล่วงหน้าในตาราง weight_exercises) แบบเดียวกับที่
-- cardio ใช้อยู่แล้ว (cardio.cdo_mets) — ค่าอ้างอิงจาก 2024 Adult Compendium of Physical Activities
-- (Herrmann et al., 2567) เท่านั้น (ตัดฉบับ 2011 ออก) จับคู่จากคำอธิบายกิจกรรมที่ตรงกับท่านั้นที่สุด
-- ไม่ระบุรหัสกิจกรรม 5 หลักไว้ในคอลัมน์/คอมเมนต์โค้ด (เก็บไว้ในเอกสารวิจัยแยกต่างหากแทน)
--
-- เหตุผลที่เปลี่ยน: สูตร Session MET + RIR เดิมมีจุดตีความสะสม 6 จุด (กลับสมการ Epley เพื่อประมาณ
-- RIR, ใช้ Best e1RM แทน 1RM จริง, ค่าเฉลี่ย RIR ทั้งเซสชัน, threshold RIR ≤ 3, จับคู่ระดับ High กับ
-- MET 6.0, ท่าน้ำหนักตัวติดค่าเดียวเสมอ) ย้ายมาใช้ METs คงที่ต่อท่าเหลือจุดตีความเดียว (จะจับคู่ท่าไหน
-- กับคำอธิบายกิจกรรมใด) ซึ่งเป็นแบบเดียวกับที่ใช้กับ cardio ทั้ง 11 กิจกรรมอยู่แล้วโดยไม่มีปัญหา
--
-- ⚠️ ก่อนรัน: backup แล้ว (2026-09-29)
--   mysqldump -u root food_and_fit_db weight_exercises weight_training_result > backups/backup_weight_tables_before_per_exercise_mets_20260929.sql
--
-- ⚠️ ผลข้างเคียงที่ทราบแล้ว: weight_training_result เดิม (6,809 แถว) คำนวณ wtrs_calories ด้วยสูตร
--    Session MET + RIR เก่า ไม่ backfill (นโยบายเดียวกับทุกครั้งที่เคยแก้สูตร METs — เทียบย้อนหลัง
--    ตรงๆ ไม่ได้ ต้องระบุในเล่มบทที่ 5 "ปัญหาที่พบระหว่างพัฒนา")
--
-- ค่า wet_mets ที่กำหนด (อ้างอิงคำอธิบายกิจกรรมในฉบับ 2024 Adult Compendium, Herrmann et al., 2567):
--   ค่าเริ่มต้น 3.5 — "Resistance (weight) training, multiple exercises, 8-15 reps at varied resistance"
--     ใช้กับท่าที่ใช้อุปกรณ์ (barbell/dumbbell/machine/cable) ทุกท่า ยกเว้นที่ระบุด้านล่าง
--   5.0 — "Resistance (weight) training, squats, deadlift, slow or explosive effort"
--     wet_id 7 Deadlift, 26 Back Squat, 28 Romanian Deadlift, 29 Bulgarian Split Squat, 46 Hack Squat
--   2.8 — "Calisthenics (e.g., curl ups, abdominal crunches, plank), light effort"
--     wet_id 34 Plank, 35 Hanging Leg Raise, 45 Crunch
--   3.0 — "Body weight resistance exercises (e.g., squat, lunge, push-up, crunch), general"
--     wet_id 8 Pull-up, 25 Dips (ท่าน้ำหนักตัวที่เหลือ — ไม่มีในระบบตอนนี้)
--
-- ท่าที่ตัดสินใจเป็นค่าเริ่มต้น 3.5 ทั้งที่อาจโต้แย้งได้ (บันทึกไว้ให้เขียนกำกับในเล่ม):
--   wet_id 27 Leg Press, 32 Hip Thrust — ท่าช่วงล่างหลายข้อต่อ แต่คำอธิบายกิจกรรมระบุเฉพาะ squat/deadlift
--   wet_id 36 Russian Twist — ท่าหน้าท้องถือน้ำหนัก ไม่เข้าเกณฑ์ calisthenics ล้วน (มีอุปกรณ์)
--   wet_id 41 Farmers Walk — ไม่มีกิจกรรม "เดินถือของ" ในหมวดฝึกแรงต้านของ Compendium

START TRANSACTION;

ALTER TABLE weight_exercises
  ADD COLUMN wet_mets DECIMAL(4,2) NOT NULL DEFAULT 3.50
  COMMENT 'METs ของท่านี้ (คงที่ต่อท่า, 2024 Adult Compendium)'
  AFTER wet_exercise_type;

UPDATE weight_exercises SET wet_mets = 5.00 WHERE wet_id IN (7, 26, 28, 29, 46);
UPDATE weight_exercises SET wet_mets = 2.80 WHERE wet_id IN (34, 35, 45);
UPDATE weight_exercises SET wet_mets = 3.00 WHERE wet_id IN (8, 25);
-- ท่าที่เหลือทั้งหมดคงค่า default 3.50 ไว้ (ไม่ต้อง UPDATE)

ALTER TABLE weight_training_result DROP COLUMN wtrs_intensity_level;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-29_weight_exercises_per_exercise_mets.sql',
   'เพิ่ม weight_exercises.wet_mets (METs คงที่ต่อท่า) แทน Session MET + RIR, ลบ weight_training_result.wtrs_intensity_level');

COMMIT;

-- Rollback:
-- START TRANSACTION;
-- ALTER TABLE weight_training_result ADD COLUMN wtrs_intensity_level TINYINT NOT NULL DEFAULT 2
--   COMMENT 'ระดับความหนักของการฝึก' AFTER wtrs_duration;
-- ALTER TABLE weight_exercises DROP COLUMN wet_mets;
-- DELETE FROM schema_migrations WHERE filename = '2026-09-29_weight_exercises_per_exercise_mets.sql';
-- COMMIT;
-- (ค่า wtrs_intensity_level เดิมกู้คืนได้จาก backups/backup_weight_tables_before_per_exercise_mets_20260929.sql เท่านั้น
--  ค่า default 2 ข้างบนเป็นแค่ placeholder กันคอลัมน์ NOT NULL พัง ไม่ใช่ค่าจริงของแถวเดิม)

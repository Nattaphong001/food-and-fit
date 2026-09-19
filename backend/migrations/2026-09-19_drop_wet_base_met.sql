-- 2026-09-19 — ตัดคอลัมน์ wet_base_met (weight_exercises) ทิ้งถาวร
-- เหตุผล: เป็น dead input มาตั้งแต่ Step 1 เปลี่ยนเป็น Dynamic Base MET (2026-09-08) —
-- services.CalculateWeightTrainingCalories (backend/services/calculator.go) ไม่เคยอ่านค่านี้เลย
-- แม้แต่บรรทัดเดียว คำนวณ Session Base MET จาก Reps+เวลาพักต่อเซตล้วนๆ ไม่อิงท่าฝึกอีกต่อไป
-- ก่อนหน้านี้เคยตัดสินใจ "คงคอลัมน์ไว้เป็น legacy ไม่ลบ" (ดู CLAUDE.md ข้อ 7[B-1] ฉบับก่อนแก้)
-- แต่ทบทวนแล้วว่าเป็นภาระผู้ใช้งานจริง เพราะแอดมินยังต้องกรอกค่านี้ทุกครั้งที่เพิ่ม/แก้ท่าฝึก
-- (ฟอร์ม admin-web validate 1.0-12.0 บังคับ) ทั้งที่ค่าที่กรอกไม่มีผลต่อพลังงานที่คำนวณได้เลย
-- จึงตัดสินใจตัดออกจริงรอบนี้ พร้อมกับโค้ด Go (models/controllers) และฟอร์ม admin-web ที่อ้างอิงคอลัมน์นี้
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root -p food_and_fit_db weight_exercises > backup_weight_exercises_before_drop_base_met_20260919.sql

ALTER TABLE weight_exercises
  DROP COLUMN wet_base_met;

-- Rollback (ต้อง backfill ค่าเองจาก backup ด้านบน คอลัมน์เดิมเป็น NOT NULL ไม่มี DEFAULT ที่ปลอดภัยตายตัว):
-- ALTER TABLE weight_exercises
--   ADD COLUMN wet_base_met DECIMAL(3,1) NOT NULL DEFAULT 4.5
--   COMMENT 'MET พื้นฐานของท่านี้ (LEGACY - เลิกใช้ในการคำนวณตั้งแต่ 2026-09-08)'
--   AFTER wet_loop_video;
-- แล้ว UPDATE ค่าจริงกลับจาก backup_weight_exercises_before_drop_base_met_20260919.sql

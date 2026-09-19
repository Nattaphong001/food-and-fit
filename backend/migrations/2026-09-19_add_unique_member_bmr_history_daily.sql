-- ชี้ขาด D10/D12 conflict: member_bmr_history เปลี่ยนจาก "append-only ตั้งใจ" (ข้อ 3.6 เดิม,
-- 2026-09-04) เป็น "upsert รายวันบังคับที่ระดับ DB" (ผู้ใช้ตัดสินใจ 2026-09-19)
--
-- เหตุผลของผู้ใช้: ระบบใช้ค่ารายวันเป็นหลัก (พล็อตกราฟ/รายงานรายวัน-สัปดาห์-เดือน, Energy Balance
-- คำนวณรายวัน) — trade-off ที่ยอมรับ: ถ้าแก้น้ำหนักหลายครั้งในวันเดียวกัน ค่าก่อนหน้าในวันนั้นจะหายไป
-- (ไม่ใช่ append-only log อีกต่อไป) แลกกับ query/รายงานง่ายกว่า ไม่ต้องมี "เลือกแถวล่าสุดของวัน" logic
-- ทุกจุดที่อ่านตารางนี้
--
-- โค้ดฝั่ง Go (member_controller.go: UpdateProfile/EditProfile/UpdateBodyStats -> services.
-- UpsertBmrHistoryToday) ทำ upsert รายวันอยู่แล้วตั้งแต่ D10 (2026-09-05) — migration นี้แค่ทำให้
-- DB บังคับตรงกับที่แอปทำอยู่แล้วจริง (กันกรณี race condition/บั๊กในอนาคตที่จะแอบ insert ซ้ำได้
-- โดยไม่มีใครรู้ตัว เหมือนที่เคยเกิดปัญหาแถวผีมาก่อน)
--
-- ตรวจก่อนรัน (2026-09-19): ไม่มีแถวซ้ำ (mb_id, mbh_record_date) อยู่ในข้อมูลจริงตอนนี้เลย
--   SELECT mb_id, mbh_record_date, COUNT(*) FROM member_bmr_history
--   GROUP BY mb_id, mbh_record_date HAVING COUNT(*) > 1;
--   -> ผลลัพธ์ว่างเปล่า ไม่ต้อง dedupe ก่อนใส่ UNIQUE
--
-- หมายเหตุ: ดัชนีเดิมในตารางจริงชื่อ `idx_mbh_mb_id (mb_id)` เฉยๆ (ไม่ใช่ `idx_mbh_member_date
-- (mb_id, mbh_record_date)` ตามที่ข้อ 3.6 เดิมเคยเขียนไว้ — เอกสารกับของจริงไม่ตรงกันมาก่อนแล้ว
-- ไม่เกี่ยวกับการแก้รอบนี้) แทนที่ด้วย UNIQUE ตัวใหม่ที่ครอบคลุมทั้ง 2 คอลัมน์แทน
--
-- ⚠️ BACKUP แล้ว: backend/migrations/backups/backup_member_bmr_history_before_unique_20260919.sql
-- (SELECT * ทั้งตาราง 81 แถว)

ALTER TABLE member_bmr_history
  DROP INDEX idx_mbh_mb_id,
  ADD UNIQUE KEY uq_mbh_member_date (mb_id, mbh_record_date);

-- Rollback (กลับไปตามที่ข้อ 3.6 เดิมเคยตั้งใจไว้ — append-only, ดัชนีธรรมดาไม่ใช่ UNIQUE):
-- ALTER TABLE member_bmr_history
--   DROP INDEX uq_mbh_member_date,
--   ADD INDEX idx_mbh_mb_id (mb_id);

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-19_add_unique_member_bmr_history_daily.sql',
   'ชี้ขาด D10/D12: member_bmr_history เป็น upsert รายวันบังคับ DB แล้ว ไม่ใช่ append-only');

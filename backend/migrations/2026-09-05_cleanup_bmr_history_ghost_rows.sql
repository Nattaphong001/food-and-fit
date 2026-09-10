-- ============================================================================
-- cleanup_bmr_history_ghost_rows — 2026-09-05
-- ============================================================================
-- บริบท: ก่อนหน้านี้ member_controller.go (EditProfile + UpdateBodyStats) เคย insert
-- member_bmr_history ซ้ำได้หลายแถวผูกกับ member_body_stats แถวเดียวกัน (mbs_id เดียวกัน) —
-- เคสหลักคือ "แถวผี" จากการยิง PUT /member/profile ตามด้วย PUT /member/body-stats ติดกัน
-- (แก้ที่ backend แล้วใน commit FIX-DOUBLE-WRITE — ดู member_controller.go ปัจจุบัน)
-- สคริปต์นี้ไล่ backfill ข้อมูลเก่าที่ค้างมาก่อนวันแก้ ไม่เกี่ยวกับโค้ดที่รันอยู่ตอนนี้
--
-- นิยาม "แถวผี" ที่ใช้ในสคริปต์นี้: แถวใน member_bmr_history ที่ mbs_id ไม่ใช่ NULL,
-- มี mbs_id ซ้ำกับแถวอื่นอย่างน้อย 1 แถว, และ mbh_id ของแถวนั้นไม่ใช่ mbh_id สูงสุดของกลุ่ม
-- mbs_id เดียวกัน (เก็บเฉพาะแถวล่าสุดสุดของแต่ละ mbs_id ไว้ ลบที่เหลือทั้งหมด)
--
-- ⚠️ หมายเหตุสำคัญที่ต้องรู้ก่อนรัน — ผลข้างเคียงที่ยอมรับได้:
-- นิยามนี้ยุบทุกกรณีที่ 1 mbs_id ผูกกับ member_bmr_history หลายแถว ไม่ได้จำกัดเฉพาะเคส
-- "double-write ในคำขอเดียวกัน" เท่านั้น — รวมถึงเคส "ร่างกาย (น้ำหนัก/ส่วนสูง) เท่าเดิม แต่
-- ผ่านวันเกิดจนอายุเพิ่มขึ้น 1 ปี" ด้วย (EditProfile เดิม/ปัจจุบันจะ insert แถวใหม่ผูกกับ mbs_id
-- เดิมถ้า activity_level/target ก็ไม่เปลี่ยนตาม) เคสนี้จะถูกยุบเหลือแค่แถวล่าสุดไปด้วย
-- ยอมรับได้เพราะ BMR เปลี่ยนจากอายุปีเดียวแค่ ~5 kcal/ปี (ดูสูตร Mifflin-St Jeor ใน docs/SPEC.md
-- หัวข้อ 5 — เทอม 5×อายุ) ไม่มีนัยสำคัญบนกราฟแนวโน้ม BMI/BMR/TDEE ระยะยาว
--
-- ขั้นตอน: (1) SELECT ตรวจก่อน (2) backup (3) DELETE (4) SELECT ตรวจหลัง
-- รันทีละ block เอง ตรวจผลลัพธ์ block ก่อนหน้าก่อนรัน block ถัดไปเสมอ — ห้ามรันรวดเดียวทั้งไฟล์
-- ============================================================================


-- ============================================================================
-- STEP 1 — SELECT ตรวจสอบก่อนลบ
-- ============================================================================

-- 1a) รายละเอียดทุกแถวที่จะถูกลบ (ตรวจด้วยตาก่อนว่าค่าที่จะหายไปสมเหตุสมผลจริง)
SELECT
    h.mb_id,
    h.mbs_id,
    h.mbh_id,
    h.mbh_record_date,
    h.mbh_bmi,
    h.mbh_bmr,
    h.mbh_tdee,
    h.mbh_tdee_target,
    dup.max_mbh_id AS mbh_id_ที่จะเก็บไว้
FROM member_bmr_history h
JOIN (
    SELECT mbs_id, MAX(mbh_id) AS max_mbh_id
    FROM member_bmr_history
    WHERE mbs_id IS NOT NULL
    GROUP BY mbs_id
    HAVING COUNT(*) > 1
) dup ON dup.mbs_id = h.mbs_id
WHERE h.mbh_id <> dup.max_mbh_id
ORDER BY h.mb_id, h.mbs_id, h.mbh_id;

-- 1b) สรุปจำนวนแถวที่จะโดนลบ แยกตาม mb_id
SELECT
    h.mb_id,
    COUNT(*) AS จำนวนแถวผีที่จะลบ
FROM member_bmr_history h
JOIN (
    SELECT mbs_id, MAX(mbh_id) AS max_mbh_id
    FROM member_bmr_history
    WHERE mbs_id IS NOT NULL
    GROUP BY mbs_id
    HAVING COUNT(*) > 1
) dup ON dup.mbs_id = h.mbs_id
WHERE h.mbh_id <> dup.max_mbh_id
GROUP BY h.mb_id
ORDER BY h.mb_id;

-- 1c) รวมทั้งหมดทุก mb_id (เทียบกับจำนวนที่ DELETE รายงานหลังรันจริง ต้องตรงกันเป๊ะ)
SELECT COUNT(*) AS รวมแถวผีทั้งหมดที่จะลบ
FROM member_bmr_history h
JOIN (
    SELECT mbs_id, MAX(mbh_id) AS max_mbh_id
    FROM member_bmr_history
    WHERE mbs_id IS NOT NULL
    GROUP BY mbs_id
    HAVING COUNT(*) > 1
) dup ON dup.mbs_id = h.mbs_id
WHERE h.mbh_id <> dup.max_mbh_id;


-- ============================================================================
-- STEP 2 — Backup ตารางทั้งหมดก่อนลบ (ต้องรันก่อน DELETE เสมอ)
-- ============================================================================
-- CREATE TABLE ... AS SELECT คัดลอกเฉพาะข้อมูล+ชนิดคอลัมน์ ไม่คัดลอก index/key/auto_increment
-- flag ของตารางต้นทาง — พอสำหรับกู้คืนข้อมูล ไม่เหมาะเป็นตารางใช้งานจริงทดแทน

CREATE TABLE member_bmr_history_backup_20260905 AS
SELECT * FROM member_bmr_history;

-- ตรวจว่า backup ได้จำนวนแถวเท่าต้นฉบับก่อนไปต่อ (ต้องเท่ากับ COUNT(*) ของ member_bmr_history)
SELECT
    (SELECT COUNT(*) FROM member_bmr_history) AS จำนวนแถวต้นฉบับ,
    (SELECT COUNT(*) FROM member_bmr_history_backup_20260905) AS จำนวนแถวใน_backup;


-- ============================================================================
-- STEP 3 — DELETE แถวผี (เงื่อนไขต้องตรงกับ STEP 1 เป๊ะ)
-- ============================================================================
-- ผลลัพธ์ "Rows matched" ที่ MySQL รายงานหลังรัน ต้องเท่ากับตัวเลขจาก STEP 1c เป๊ะ
-- ถ้าไม่เท่ากัน — หยุดทันที อย่ารันต่อ ให้ตรวจสอบก่อนว่าเกิดอะไรขึ้น (มีคนแก้ข้อมูลระหว่างนี้?)

DELETE h FROM member_bmr_history h
JOIN (
    SELECT mbs_id, MAX(mbh_id) AS max_mbh_id
    FROM member_bmr_history
    WHERE mbs_id IS NOT NULL
    GROUP BY mbs_id
    HAVING COUNT(*) > 1
) dup ON dup.mbs_id = h.mbs_id
WHERE h.mbh_id <> dup.max_mbh_id;


-- ============================================================================
-- STEP 4 — SELECT ตรวจสอบหลังลบ
-- ============================================================================

-- 4a) จำนวนแถวคงเหลือต่อ mb_id (เทียบกับก่อนลบเพื่อดูว่าลดลงตามที่คาดจาก STEP 1b)
SELECT
    mb_id,
    COUNT(*) AS จำนวนแถวคงเหลือ
FROM member_bmr_history
GROUP BY mb_id
ORDER BY mb_id;

-- 4b) ต้องไม่มี mbs_id ซ้ำอีกต่อไป — query นี้ต้องคืนแถวว่าง (0 rows) เท่านั้นถึงจะถือว่าสำเร็จ
SELECT
    mbs_id,
    COUNT(*) AS จำนวนแถวที่ยังซ้ำ
FROM member_bmr_history
WHERE mbs_id IS NOT NULL
GROUP BY mbs_id
HAVING COUNT(*) > 1;


-- ============================================================================
-- ROLLBACK (ใช้เฉพาะกรณีฉุกเฉิน ถ้าพบว่าลบผิดหลัง STEP 3) — ห้ามรันถ้าไม่จำเป็นจริงๆ
-- ============================================================================
-- TRUNCATE TABLE member_bmr_history;
-- INSERT INTO member_bmr_history
-- SELECT * FROM member_bmr_history_backup_20260905;
--
-- หลัง rollback ให้รัน STEP 4a/4b ซ้ำเพื่อยืนยันว่าข้อมูลกลับมาครบเหมือนก่อน STEP 3

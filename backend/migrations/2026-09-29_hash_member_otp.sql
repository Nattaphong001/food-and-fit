-- แก้ mb_otp จากเก็บ plaintext เป็นเก็บ bcrypt hash (security audit 2026-09-29)
--
-- เหตุผล: mb_otp (varchar(6)) เดิมเก็บรหัส OTP ดิบตรงๆ — ถ้า DB หลุด (backup, SQL injection,
-- insider) ผู้โจมตีได้รหัส OTP ที่ยังไม่หมดอายุไปใช้ยืนยันอีเมล/รีเซ็ตรหัสผ่านได้ทันที ไม่ต้องเดา
-- แก้ให้ hash ด้วย bcrypt เหมือน mb_password_hash (ช้าพอที่จะกัน brute-force offline ได้จริงในช่วง
-- อายุ OTP 5-10 นาที ต่างจาก SHA-256 ธรรมดาที่ไล่ครบ 1,000,000 ค่าได้ในเสี้ยววินาที)
--
-- varchar(6) เก็บ bcrypt hash (~60 ตัวอักษร) ไม่พอ ต้องขยายคอลัมน์ก่อน
-- ล้างค่า OTP ที่ค้างอยู่ (plaintext เดิม) ทิ้งไปด้วย — ผู้ใช้ที่กำลังรอยืนยัน/รีเซ็ตอยู่พอดีต้องขอรหัส
-- ใหม่ 1 ครั้ง (กระทบน้อย เพราะ OTP อายุแค่ 5-10 นาทีอยู่แล้ว)

ALTER TABLE member_profile
  MODIFY COLUMN mb_otp varchar(60) DEFAULT NULL COMMENT 'bcrypt hash ของรหัส OTP (เดิมเก็บ plaintext แก้ 2026-09-29)';

UPDATE member_profile SET mb_otp = NULL, mb_otp_expired = NULL WHERE mb_otp IS NOT NULL AND mb_otp != '';

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-29_hash_member_otp.sql', 'รันจริงวันนี้ — ขยาย mb_otp เป็น varchar(60) เก็บ bcrypt hash, ล้าง OTP ค้างเก่า');

-- Rollback (จะย้อนกลับไปเก็บ plaintext ไม่แนะนำ แต่ทำได้ถ้าจำเป็น):
-- ALTER TABLE member_profile MODIFY COLUMN mb_otp varchar(6) DEFAULT NULL;
-- UPDATE member_profile SET mb_otp = NULL, mb_otp_expired = NULL;
-- DELETE FROM schema_migrations WHERE filename = '2026-09-29_hash_member_otp.sql';

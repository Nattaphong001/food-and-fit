-- V4 / spec item 5: กันชื่อซ้ำในตารางแม่ระดับ DB (เดิมเช็คแค่ client-side ทำให้ race condition
-- กดพร้อมกันสร้างชื่อซ้ำได้ 2 แถว) — เช็คแล้วว่าตอนที่รัน (2026-08-23) ไม่มีชื่อซ้ำอยู่ในข้อมูลเดิม
-- จึงเพิ่ม UNIQUE KEY ได้โดยไม่ต้อง dedupe ก่อน
-- Applied to live DB on 2026-08-23.

ALTER TABLE weight_exercises      ADD UNIQUE KEY uq_wet_name (wet_name);
ALTER TABLE cardio                ADD UNIQUE KEY uq_cdo_name (cdo_name);
ALTER TABLE cardio_category       ADD UNIQUE KEY uq_cdc_name (cdc_name);
ALTER TABLE muscle_group          ADD UNIQUE KEY uq_mug_name (mug_name);
ALTER TABLE nutrition_category    ADD UNIQUE KEY uq_nttc_name (nttc_name);
ALTER TABLE nutrition             ADD UNIQUE KEY uq_ntt_food_name (ntt_food_name);
ALTER TABLE workout_plan_template ADD UNIQUE KEY uq_wpt_name (wpt_name);

-- ข้อ 3.7: กันผูกท่าฝึก-กล้ามเนื้อซ้ำคู่เดิม (Constraint ที่ขาด ตามสเปก)
ALTER TABLE exercise_muscle_details ADD UNIQUE KEY uq_wet_mug (wet_id, mug_id);

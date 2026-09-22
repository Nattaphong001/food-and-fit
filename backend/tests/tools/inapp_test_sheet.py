"""สร้างชีทข้อมูลทดสอบสำหรับทดสอบด้วยมือผ่านแอป + ยิง API ด้วยข้อมูลเดียวกัน (เวลารวมประมาณการ) เก็บผลระบบไว้เทียบ
ต้องรัน backend พอร์ต 8082 ก่อน (PORT=8082 go run main.go) — ค่าที่ควรได้เขียนมือ ไม่ดึงจากโค้ดระบบ"""
import datetime, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2e_weight_algorithm_steps as base  # ใช้ call/sql/EX ร่วมกัน (ไม่รันเทสต์เดิมตอน import)

EMAIL, PWD, KG = "qa-inapp-20260920@foodandfit.test", "InappSheet#2026Test", 70.0
SET_SECONDS = 40  # เวลายกต่อเซตที่ใช้ประมาณ T: T ≈ 3×40 + พักครั้งที่ 1 + พักครั้งที่ 2
OUT = os.path.join(base.OUT_DIR, "INAPP_TEST_SHEET.md")

# id, เงื่อนไขที่ทดสอบ, wet, reps ต่อเซต, [พัก1, พัก2], น้ำหนักยก, MET ต่อเซตที่ควรได้
CASES = [
    ("T1", "แรงต้าน ข้อ 1: Reps < 8 → หนัก", 30, [6, 6, 6], [20, 20], 30, [6.0, 6.0, 6.0]),
    ("T2", "แรงต้าน ข้อ 1 ชนะ Compound (ลำดับความสำคัญ)", 26, [6, 6, 6], [20, 20], 40, [6.0, 6.0, 6.0]),
    ("T3", "แรงต้าน ข้อ 2: ท่า Compound (พักสั้น)", 26, [10, 10, 10], [20, 20], 40, [5.0, 5.0, 5.0]),
    ("T4", "แรงต้าน ข้อ 2: Compound พักนาน > 90 ยังปานกลาง", 26, [10, 10, 10], [105, 105], 40, [5.0, 5.0, 5.0]),
    ("T5", "แรงต้าน ข้อ 2: Isolation พัก 60–90", 30, [10, 10, 10], [75, 75], 30, [5.0, 5.0, 5.0]),
    ("T6", "แรงต้าน ข้อ 3: ไม่เข้าเงื่อนไขใดๆ (Reps ≥ 8 + Isolation + พักนอก 60–90) → เบา", 30, [10, 10, 10], [20, 20], 30, [3.5, 3.5, 3.5]),
    ("T7", "ขอบ: Reps 8 พอดี ไม่ใช่หนัก → ตกข้อ 3", 30, [8, 8, 8], [20, 20], 30, [3.5, 3.5, 3.5]),
    ("T8", "น้ำหนักตัว ข้อ 1: ท่าหน้าท้อง แม้พักสั้น", 45, [15, 15, 15], [10, 10], 0, [2.8, 2.8, 2.8]),
    ("T9", "น้ำหนักตัว ข้อ 1: ท่าหน้าท้องอีกท่า พัก 60", 35, [10, 10, 10], [60, 60], 0, [2.8, 2.8, 2.8]),
    ("T10", "น้ำหนักตัว ข้อ 2: พัก < 30 → หนัก (Reps 5 ไม่ทำให้เป็น 6.0)", 8, [5, 5, 5], [15, 15], 0, [8.0, 8.0, 8.0]),
    ("T11", "น้ำหนักตัว ข้อ 3: พัก 30–90 → ปานกลาง", 8, [8, 8, 8], [45, 45], 0, [3.8, 3.8, 3.8]),
    ("T12", "น้ำหนักตัว ข้อ 4: พัก > 90 → เบา", 8, [8, 8, 8], [105, 105], 0, [3.5, 3.5, 3.5]),
    ("T13", "ผสมหลายระดับ (แรงต้าน) + เซตสุดท้ายใช้พักเฉลี่ย (20+75)/2 = 47.5 → เบา", 30, [6, 10, 10], [20, 75], 30, [6.0, 5.0, 3.5]),
    ("T14", "ผสมหลายระดับ (น้ำหนักตัว) + เซตสุดท้ายใช้พักเฉลี่ย (15+75)/2 = 45 → ปานกลาง", 8, [8, 8, 8], [15, 75], 0, [8.0, 3.8, 3.8]),
]

SHEET = """# ชีทข้อมูลทดสอบด้วยมือผ่านแอป — อัลกอริทึม METs เวทเทรนนิ่ง ({date})

ค่า "ที่ควรได้" คำนวณมือจากสเปกบทที่ 2 · คอลัมน์ "ผลจากระบบ" คือผลที่ผมยิง API ด้วยข้อมูลเดียวกัน (สมาชิกทดสอบ {kg:.0f} กก. เวลารวม T ประมาณการตามตาราง)

## วิธีทดสอบในแอป
1. ตั้งน้ำหนักตัวบัญชีทดสอบให้ทราบค่า (ตารางด้านล่างคิดที่ **{kg:.0f} กก.** ถ้าน้ำหนักต่างให้คูณพลังงานด้วย น้ำหนักจริง ÷ {kg:.0f})
2. เปิดท่าตามตาราง กรอก **Reps และน้ำหนัก** ทุกเซต (ท่าน้ำหนักตัวกรอกน้ำหนัก 0)
3. หลังจบเซตที่ 1 และ 2 ให้กดปุ่ม **พัก** แล้วรอตามเวลาในคอลัมน์ "พักหลังเซต" (จับเวลาด้วยนาฬิกาข้างๆ ให้คลาดไม่เกิน ±5 วินาที) แล้วกด **จบการพัก** เพื่อบันทึกเซตนั้น — ห้ามข้ามปุ่มพัก ไม่งั้นแอปส่งเวลาพัก 0 วินาที
4. เซตที่ 3 (สุดท้าย) กรอกแล้วบันทึกเลย ไม่ต้องรอ แล้วกดจบการฝึก
5. อ่านข้อความหลังบันทึก "เผาผลาญ N kcal" แล้วรัน SQL ในข้อ 4 เพื่อดู MET ที่ระบบใช้จริงและเวลารวม T จริง

> เวลารวม T ของคุณจะไม่เท่าตัวเลขประมาณการ (ผมสมมติยก {set_seconds} วินาทีต่อเซต) จึงเทียบ **MET** เป็นหลัก ส่วนพลังงานให้คำนวณใหม่จาก T จริงด้วยสูตรข้อ 3

## 1. ข้อมูลที่ต้องกรอก

| ID | เงื่อนไขที่ทดสอบ | ท่า | เซตและ Reps | น้ำหนักยก (กก.) | พักหลังเซต 1 → 2 (วินาที) | พักหลังเซต 3 |
|---|---|---|---|---|---|---|
{rows_in}

**ข้อที่ "ไม่เข้าเงื่อนไขใดๆ" คือ T6** — หมวดแรงต้านมี 3 ข้อ (Reps < 8 · Compound หรือพัก 60–90 · ที่เหลือ) T6 ใช้ Leg Extension (Isolation) Reps 10 (ไม่ใช่ < 8) พัก 20 วินาที (ไม่อยู่ 60–90) จึงตกข้อ "ที่เหลือ" = 3.5
หมวดน้ำหนักตัวไม่มีข้อ "ที่เหลือ" — 4 ข้อ (หน้าท้อง · <30 · 30–90 · >90) ครอบคลุมทุกกรณีแล้ว

## 2. ผลที่ควรได้ เทียบผลจากระบบ (ยิง API ด้วยข้อมูลเดียวกัน)

| ID | MET ต่อเซตที่ควรได้ | Session MET ที่ควรได้ | อัตรา kcal/นาที ที่ {kg:.0f} กก. | T ประมาณ (วิ) | พลังงานที่ควรได้ที่ T นี้ | MET ที่ระบบให้ | พลังงานที่ระบบให้ | เทียบ |
|---|---|---|---|---|---|---|---|---|
{rows_out}

## 3. สูตรคำนวณพลังงานจาก T จริงของคุณ
`kcal = (Session MET − 1) × 0.0175 × น้ำหนักตัว(กก.) × T(วินาที) ÷ 60` — อ่าน T จากคอลัมน์ `T_sec` ในข้อ 4 · แอปแสดงผลปัดเป็นจำนวนเต็ม จึงต่างจากค่าจริงได้ไม่เกิน 0.5 kcal

## 4. คำสั่งตรวจผลใน MySQL (หลังทดสอบแต่ละเคส)
`implied_final_met` ควรตรงกับ "Session MET ที่ควรได้" (คลาดได้เล็กน้อยจากการปัดเศษ) · `rests` ต้องลงท้ายด้วย `NULL` (เซตสุดท้าย) และเซตแรกๆ ต้องใกล้เวลาที่คุณรอ

```sql
SET @mb = <mb_id ของบัญชีที่ทดสอบ>;
SET @kg = (SELECT mbs_weight FROM member_body_stats WHERE mb_id = @mb ORDER BY mbs_recorded_date DESC, mbs_id DESC LIMIT 1);
SELECT MAX(r.wtrs_id) AS last_id, e.wet_name, r.wtrs_duration AS T_sec, COUNT(*) AS sets,
       GROUP_CONCAT(r.wtrs_reps ORDER BY r.wtrs_set_no) AS reps,
       GROUP_CONCAT(IFNULL(r.wtrs_rest_seconds,'NULL') ORDER BY r.wtrs_set_no) AS rests,
       ROUND(SUM(r.wtrs_calories),2) AS kcal_saved,
       ROUND(1 + SUM(r.wtrs_calories) / ((r.wtrs_duration/60) * 0.0175 * @kg), 2) AS implied_final_met
FROM weight_training_result r JOIN weight_exercises e ON e.wet_id = r.wet_id
WHERE r.mb_id = @mb
GROUP BY r.wet_id, r.wtrs_date, r.wtrs_duration
ORDER BY last_id DESC LIMIT 14;
```
"""


def nominal_T(rests):
    return 3 * SET_SECONDS + sum(rests)


def run():
    base.sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
    base.call("POST", "/register", {"email": EMAIL, "password": PWD, "full_name": "QA Inapp"})
    otp = base.sql(f"SELECT mb_otp FROM member_profile WHERE mb_email='{EMAIL}'")
    _, b = base.call("POST", "/verify-email", {"email": EMAIL, "otp": otp})
    token = b.get("token") or b.get("data", {}).get("token")
    base.call("PUT", "/member/body-stats", {"gender": 1, "birth_date": "2000-01-01", "weight": KG, "height": 175,
                                            "activity_level": 1.375, "target": 3}, token)
    out = {}
    try:
        for cid, cond, wet, reps, rests, w, mets in CASES:
            T = nominal_T(rests)
            sets = [{"wtrs_set_no": i + 1, "wtrs_reps": reps[i], "wtrs_weight": w, "wtrs_rest_seconds": (rests + [None])[i]} for i in range(3)]
            out[cid] = base.call("POST", "/member/workout-results", {"date": datetime.date.today().isoformat(), "wet_id": wet,
                                                                     "total_duration_seconds": T, "sets": sets}, token)
    finally:
        base.sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
    return out


def main():
    results = run()
    rows_in, rows_out, bad = [], [], 0
    for cid, cond, wet, reps, rests, w, mets in CASES:
        name, prof = base.EX[wet]
        T = nominal_T(rests)
        met = sum(mets) / 3
        kpm = (met - 1) * 0.0175 * KG
        exp_kcal = kpm * T / 60
        st, r = results[cid]
        calc = r.get("calculation", {})
        got_met, got_kcal = calc.get("final_met"), r.get("calories_burned")
        ok = st == 200 and got_met is not None and abs(got_met - met) < 0.001 and abs(got_kcal - exp_kcal) < 0.01
        bad += 0 if ok else 1
        wtxt = "0 (น้ำหนักตัว)" if w == 0 else f"{w}"
        rows_in.append(f"| {cid} | {cond} | {name} ({prof}) | 3 เซต · Reps {'/'.join(map(str, reps))} | {wtxt} | {rests[0]} → {rests[1]} | ไม่ต้องรอ |")
        if st == 200:
            rows_out.append(f"| {cid} | {'/'.join(format(m, 'g') for m in mets)} | {met:.3f} | {kpm:.3f} | {T} | {exp_kcal:.2f} | "
                            f"{got_met:.3f} | {got_kcal:.2f} | {'✅ ตรง' if ok else '❌ ต่าง'} |")
        else:
            rows_out.append(f"| {cid} | {'/'.join(format(m, 'g') for m in mets)} | {met:.3f} | {kpm:.3f} | {T} | {exp_kcal:.2f} | ผิดพลาด {st} | — | ❌ |")
        print(("PASS " if ok else "FAIL ") + cid, got_met, got_kcal, f"(want {met:.3f} / {exp_kcal:.2f})")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(SHEET.format(date=datetime.date.today().isoformat(), kg=KG, set_seconds=SET_SECONDS,
                             rows_in="\n".join(rows_in), rows_out="\n".join(rows_out)))
    print(f"\n{len(CASES) - bad}/{len(CASES)} match; wrote {OUT}")
    return bad


if __name__ == "__main__":
    sys.exit(1 if main() else 0)

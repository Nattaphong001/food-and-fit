"""E2E ตามขั้นของอัลกอริทึมเวทเทรนนิ่ง (Dynamic METs Logic Matrix) — ค่าที่คาดหวังทุกตัวเขียนมือในตารางเคสด้านล่าง
(ไม่เรียกโค้ดของ backend มาคำนวณ) เพื่อเป็นตัวเทียบอิสระ

  python e2e_weight_algorithm_steps.py --plan    # เขียนเฉพาะเอกสารแผนทดสอบ (ไม่ต้องรัน backend)
  python e2e_weight_algorithm_steps.py           # รันจริงกับ backend พอร์ต 8082 + เขียนไฟล์ผล

ต้อง: backend รันที่พอร์ต 8082 (PORT=8082 go run main.go) · สร้างสมาชิกทดสอบ 1 คนแล้วลบทิ้งตอนจบ"""
import datetime, json, os, subprocess, sys, time, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8")

BASE = "http://localhost:8082/api"
MYSQL = ["C:/xampp/mysql/bin/mysql.exe", "-u", "root", "food_and_fit_db", "-N", "-e"]
EMAIL = "qa-steps-20260920@foodandfit.test"
PWD = "StepsCheck#2026Test"
WEIGHT = 70.0
K = lambda kg: 3.5 * kg / 200.0  # kcal ต่อ (MET-1) ต่อนาที
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)  # backend/tests
PLAN_PATH = os.path.join(OUT_DIR, "WEIGHT_ALGORITHM_TEST_PLAN.md")
RESULT_PATH = os.path.join(OUT_DIR, "RESULT_2026-09-20_weight_algorithm_steps.md")

# wet_id -> (ชื่อ, หมวด/ประเภทในระบบ)
EX = {
    1: ("Bench Press", "แรงต้าน · Compound"),
    8: ("Pull-up", "น้ำหนักตัว · Compound"),
    20: ("Dumbbell Curl", "แรงต้าน · Compound"),
    25: ("Dips", "น้ำหนักตัว · Compound"),
    26: ("Back Squat", "แรงต้าน · Compound"),
    30: ("Leg Extension", "แรงต้าน · Isolation"),
    34: ("Plank", "น้ำหนักตัว · Isolation(Abs)"),
    35: ("Hanging Leg Raise", "น้ำหนักตัว · Isolation(Abs)"),
    45: ("Crunch", "น้ำหนักตัว · Isolation(Abs)"),
}
BODYWEIGHT = {8, 25, 34, 35, 45}


class Case:
    def __init__(self, cid, step, desc, wet, reps, rests, T, mets, weights=None, intensity=None, weight_kg=WEIGHT):
        self.cid, self.step, self.desc, self.wet = cid, step, desc, wet
        self.reps, self.rests, self.T, self.mets = reps, rests, T, mets
        n = len(reps)
        self.weights = weights if weights is not None else ([0] * n if wet in BODYWEIGHT else [20] * n)
        self.intensity, self.weight_kg = intensity, weight_kg

    @property
    def session_met(self):
        return sum(self.mets) / len(self.mets)

    @property
    def kcal(self):
        return (self.session_met - 1) * K(self.weight_kg) * self.T / 60.0

    def sets(self):
        return [{"wtrs_set_no": i + 1, "wtrs_reps": self.reps[i], "wtrs_weight": self.weights[i],
                 "wtrs_rest_seconds": self.rests[i]} for i in range(len(self.reps))]


def rep3(reps, rest):  # 3 เซต พักเท่ากัน 2 เซตแรก เซตสุดท้าย NULL (เหมือนที่แอปส่ง)
    return [reps] * 3, [rest, rest, None]


def c3(cid, step, desc, wet, reps, rest, T, met, **kw):
    r, rs = rep3(reps, rest)
    return Case(cid, step, desc, wet, r, rs, T, [met] * 3, **kw)


CASES = []
add = CASES.append

# ── ขั้น 1A: เลือก MET ต่อเซต — หมวดแรงต้าน (Leg Extension = Isolation, Back Squat = Compound) ──
S1A = "1A  MET ต่อเซต: หมวดแรงต้านและอุปกรณ์"
add(c3("R1", S1A, "Reps 7 (<8) → หนัก แม้เป็น Isolation", 30, 7, 120, 600, 6.0))
add(c3("R2", S1A, "Reps 8 พอดี Isolation พัก 120 → ไม่ใช่หนัก ตกข้อ 3", 30, 8, 120, 600, 3.5))
add(c3("R3", S1A, "Compound พัก 120 → ปานกลาง", 26, 10, 120, 600, 5.0))
add(c3("R4", S1A, "Compound พัก 300 → ยังปานกลาง (Compound ชนะพักนาน)", 26, 10, 300, 600, 5.0))
add(c3("R5", S1A, "Isolation พัก 60 (ขอบล่างรวมปลาย) → ปานกลาง", 30, 10, 60, 600, 5.0))
add(c3("R6", S1A, "Isolation พัก 90 (ขอบบนรวมปลาย) → ปานกลาง", 30, 10, 90, 600, 5.0))
add(c3("R7", S1A, "Isolation พัก 75 (กลางช่วง) → ปานกลาง", 30, 10, 75, 600, 5.0))
add(c3("R8", S1A, "Isolation พัก 59 (ต่ำกว่าช่วง) → เบา", 30, 10, 59, 600, 3.5))
add(c3("R9", S1A, "Isolation พัก 91 (สูงกว่าช่วง) → เบา", 30, 10, 91, 600, 3.5))
add(c3("R10", S1A, "Isolation พัก 30 (พักสั้นไม่ทำให้หนักในหมวดนี้) → เบา", 30, 10, 30, 600, 3.5))
add(c3("R11", S1A, "Reps 7 + Compound พัก 20 → หนัก (Reps ชนะ Compound)", 26, 7, 20, 600, 6.0))
add(c3("R12", S1A, "Reps 1 พัก 200 → หนัก", 30, 1, 200, 600, 6.0))

# ── ขั้น 1B: เลือก MET ต่อเซต — หมวดน้ำหนักตัว (Pull-up/Dips = Compound; Crunch/Plank/Hanging Leg Raise = Abs→Isolation) ──
S1B = "1B  MET ต่อเซต: หมวดน้ำหนักตัว/แคลิสเทนิกส์"
add(c3("B1", S1B, "Crunch พัก 10 → 2.8 (ท่าหน้าท้องชนะพักสั้น)", 45, 20, 10, 600, 2.8))
add(c3("B2", S1B, "Crunch พัก 200 → 2.8", 45, 20, 200, 600, 2.8))
add(c3("B3", S1B, "Plank พัก 20 → 2.8", 34, 10, 20, 600, 2.8))
add(c3("B4", S1B, "Hanging Leg Raise พัก 60 → 2.8", 35, 10, 60, 600, 2.8))
add(c3("B5", S1B, "Pull-up พัก 29 (<30) → หนัก", 8, 10, 29, 600, 8.0))
add(c3("B6", S1B, "Pull-up พัก 30 (ขอบล่างของ 30–90) → ปานกลาง", 8, 10, 30, 600, 3.8))
add(c3("B7", S1B, "Pull-up พัก 60 → ปานกลาง", 8, 10, 60, 600, 3.8))
add(c3("B8", S1B, "Pull-up พัก 90 (ขอบบนรวมปลาย) → ปานกลาง", 8, 10, 90, 600, 3.8))
add(c3("B9", S1B, "Pull-up พัก 91 (>90) → เบา", 8, 10, 91, 600, 3.5))
add(c3("B10", S1B, "Pull-up พัก 300 → เบา", 8, 10, 300, 600, 3.5))
add(c3("B11", S1B, "Pull-up Reps 3 พัก 60 → 3.8 (เกณฑ์ Reps<8 ใช้เฉพาะหมวดแรงต้าน)", 8, 3, 60, 600, 3.8))
add(c3("B12", S1B, "Dips พัก 10 → หนัก", 25, 10, 10, 600, 8.0))
add(c3("B13", S1B, "Pull-up Reps 3 พัก 20 → 8.0 (ไม่ใช่ 6.0)", 8, 3, 20, 600, 8.0))

# ── ขั้น 2: เวลาพักของเซตที่ไม่ทราบ (เซตสุดท้าย = NULL) ──
S2 = "2   เวลาพักของเซตที่ไม่ทราบ (เซตสุดท้าย/แถวเก่า)"
add(Case("C1", S2, "เซตสุดท้ายใช้ค่าเฉลี่ยพักของเซตอื่น: (30+90)/2=60 → เซต3 = 5.0", 30, [10, 10, 10], [30, 90, None], 600, [3.5, 5.0, 5.0]))
add(Case("C2", S2, "Pull-up พัก [20,100,NULL] → เฉลี่ย 60 → เซต3 = 3.8", 8, [10, 10, 10], [20, 100, None], 600, [8.0, 3.5, 3.8]))
add(Case("C3", S2, "Pull-up 3 เซต พักไม่ทราบทั้งหมด T=90 → ความหนาแน่น 30 วิ → 3.8", 8, [10] * 3, [None] * 3, 90, [3.8] * 3))
add(Case("C4", S2, "Pull-up 3 เซต พักไม่ทราบทั้งหมด T=60 → ความหนาแน่น 20 วิ → 8.0", 8, [10] * 3, [None] * 3, 60, [8.0] * 3))
add(Case("C5", S2, "Leg Extension พักไม่ทราบ T=540 → 180 วิ/เซต → 3.5", 30, [10] * 3, [None] * 3, 540, [3.5] * 3))
add(Case("C6", S2, "Back Squat พักไม่ทราบ T=540 → Compound → 5.0", 26, [10] * 3, [None] * 3, 540, [5.0] * 3))
add(Case("C7", S2, "เซตเดียว Leg Extension T=120 → ความหนาแน่น 120 วิ → 3.5", 30, [10], [None], 120, [3.5]))
add(Case("C8", S2, "เซตเดียว Pull-up T=45 → ความหนาแน่น 45 วิ → 3.8", 8, [10], [None], 45, [3.8]))
add(Case("C9", S2, "เซตเดียว Leg Extension T=70 → ความหนาแน่น 70 วิ → 5.0", 30, [10], [None], 70, [5.0]))
add(Case("C10", S2, "4 เซต Pull-up พัก [20,20,100,NULL] → เฉลี่ย 46.67 (อยู่ช่วง 30–90) → เซต4 = 3.8", 8, [10] * 4, [20, 20, 100, None], 600, [8.0, 8.0, 3.5, 3.8]))

# ── ขั้น 3: Session MET = ค่าเฉลี่ยของ MET ต่อเซต ──
S3 = "3   Session MET = ค่าเฉลี่ยของทุกเซต"
add(Case("D1", S3, "Leg Extension Reps [5,10,12] พัก [90,75,120] → (6.0+5.0+3.5)/3", 30, [5, 10, 12], [90, 75, 120], 600, [6.0, 5.0, 3.5]))
add(Case("D2", S3, "Pull-up พัก [20,60,120] → (8.0+3.8+3.5)/3", 8, [10] * 3, [20, 60, 120], 600, [8.0, 3.8, 3.5]))
add(Case("D3", S3, "Leg Extension 4 เซต Reps [6,10,10,10] พัก [100,60,90,NULL] → เซต4 พักเฉลี่ย 83.3", 30, [6, 10, 10, 10], [100, 60, 90, None], 600, [6.0, 5.0, 5.0, 5.0]))
add(Case("D4", S3, "Pull-up 5 เซต พัก [10,40,95,29,NULL] → เซต5 พักเฉลี่ย 43.5", 8, [10] * 5, [10, 40, 95, 29, None], 600, [8.0, 3.8, 3.5, 8.0, 3.8]))

# ── ขั้น 5: สูตรพลังงาน (MET−1)×3.5×kg/200×นาที ──
S5 = "5   สูตรพลังงานสุทธิ ACSM"
add(Case("F2a", S5, "น้ำหนักที่ยก 30 กก. (Leg Extension พัก 90) — เทียบกับ F2b", 30, [10] * 3, [90, 90, None], 600, [5.0] * 3, weights=[30] * 3))
add(Case("F2b", S5, "น้ำหนักที่ยก 100 กก. (ที่อื่นเหมือน F2a) → kcal ต้องเท่า F2a", 30, [10] * 3, [90, 90, None], 600, [5.0] * 3, weights=[100] * 3))
add(Case("F3a", S5, "Pull-up พัก 60 T=300 (เวลาครึ่งหนึ่งของ B7)", 8, [10] * 3, [60, 60, None], 300, [3.8] * 3))
add(Case("F3b", S5, "Pull-up พัก 60 T=1200 (เวลา 2 เท่าของ B7) → kcal ต้อง 2 เท่า B7", 8, [10] * 3, [60, 60, None], 1200, [3.8] * 3))

# ── ขั้น 6: การบันทึกลง DB ──
S6 = "6   การกระจาย/บันทึกลง DB"
add(Case("G1", S6, "Dumbbell Curl เซสชันที่ 1 ของวัน 3 เซต → set_no 1-3", 20, [10] * 3, [120, 120, None], 600, [5.0] * 3))
add(Case("G2", S6, "Dumbbell Curl เซสชันที่ 2 ของวัน 2 เซต → set_no ต่อเนื่อง 4-5", 20, [10] * 2, [120, None], 300, [5.0] * 2))

# ── ขั้น 7: ป้ายระดับความหนัก (แสดงผลเท่านั้น ไม่กระทบ kcal) — Bench Press, 1RM ดีที่สุด = 60×(1+10/30) = 80 ──
S7 = "7   ป้ายระดับความหนัก (%1RM) — แสดงผลอย่างเดียว"
H = lambda cid, desc, w, T, lvl: Case(cid, S7, desc, 1, [10] * 3, [120, 120, None], T, [5.0] * 3, weights=[w] * 3, intensity=lvl)
add(H("H0", "ครั้งแรกของท่านี้ (ไม่มีประวัติ 1RM) 60 กก. → กลาง(2)", 60, 600, 2))
add(H("H1", "30 กก. → RI 30/80=0.375 → เบา(1)", 30, 601, 1))
add(H("H2", "48 กก. → RI 0.60 → กลาง(2)", 48, 602, 2))
add(H("H3", "60 กก. → RI 0.75 → หนัก(3)", 60, 603, 3))
add(Case("H4", S7, "น้ำหนัก [30,60,60] → RI เฉลี่ย (0.375+0.75+0.75)/3=0.625 → กลาง(2)", 1, [10] * 3, [120, 120, None], 604, [5.0] * 3, weights=[30, 60, 60], intensity=2))
add(Case("H5", S7, "ท่าน้ำหนักตัว (น้ำหนักที่ยก 0) → กลาง(2)", 25, [10] * 3, [60, 60, None], 605, [3.8] * 3, intensity=2))

# ── ค่าขอบที่ backend รับได้ (ต้องบันทึกสำเร็จ) ──
SA = "A   ค่าขอบที่รับได้"
add(Case("A1", SA, "T=15 วิ ใน 3 เซต (ขั้นต่ำ 5 วิ/เซต พอดี) พักไม่ทราบ → 5 วิ/เซต Leg Extension → 3.5", 30, [10] * 3, [None] * 3, 15, [3.5] * 3))
add(Case("A2", SA, "ผลรวมพัก = T+10 พอดี (55+55=110, T=100) → 3.5", 30, [10] * 3, [55, 55, None], 100, [3.5] * 3))
add(Case("A3", SA, "T=7200 วิ (2 ชม. พอดี) 2 เซต Back Squat พักไม่ทราบ → 5.0", 26, [10] * 2, [None] * 2, 7200, [5.0] * 2))

# ── ค่าที่ต้องถูกปฏิเสธ (400 และไม่เขียน DB) ──
# (id, คำอธิบาย, wet, T, reps, weights, rests)
REJECT = [
    ("V1", "เวลารวมสั้นเกินไป: T=10 วิ กับ 3 เซต (<5 วิ/เซต)", 30, 10, [10] * 3, [20] * 3, [None] * 3),
    ("V2", "เวลารวมเกิน 2 ชม.: T=7300", 30, 7300, [10] * 3, [20] * 3, [30, 30, None]),
    ("V3", "เวลาพักติดลบ", 30, 600, [10] * 3, [20] * 3, [-5, 30, None]),
    ("V4", "เวลาพักของเซตเดียวมากกว่าเวลารวม (500 > 100)", 30, 100, [10] * 2, [20] * 2, [500, None]),
    ("V5", "ผลรวมพักเกินเวลารวม+10 วิ (300 > 210)", 30, 200, [10] * 3, [20] * 3, [150, 150, None]),
    ("V6", "Reps = 0 (เซตเดียว)", 30, 600, [0], [10], [None]),
    ("V7", "Reps = 0 ในบางเซต [10,0,10] — API ปฏิเสธทั้งคำขอ (ไม่ได้กรองทิ้งเงียบๆ)", 30, 600, [10, 0, 10], [20] * 3, [90, 10, None]),
    ("V8", "Reps = 1000 (เพดาน 999)", 30, 600, [1000], [20], [None]),
    ("V9", "น้ำหนักที่ยก 1000 กก. (เพดาน 999.99)", 30, 600, [10], [1000], [None]),
    ("V10", "51 เซต (เพดาน 50)", 30, 3600, [10] * 51, [20] * 51, [None] * 51),
    ("V11", "ไม่มีท่าฝึกนี้ (wet_id=99999)", 99999, 600, [10] * 2, [20] * 2, [30, None]),
]


def fmt_rest(r):
    return "—" if r is None else str(r)


def fmt_list(xs, f=lambda v: str(v)):
    return "[" + ", ".join(f(x) for x in xs) + "]"


def plan_markdown():
    out = []
    steps = []
    for c in CASES:
        if c.step not in steps:
            steps.append(c.step)
    for s in steps:
        out.append(f"### ขั้น {s}\n")
        out.append("| ID | ท่า (หมวด/ประเภท) | Reps ต่อเซต | น้ำหนักยก (กก.) | พักหลังเซต (วิ) | เวลารวม T (วิ) | MET ต่อเซตที่ควรได้ | Session MET | พลังงานรวมที่ควรได้ @70 กก. | หมายเหตุ |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for c in [c for c in CASES if c.step == s]:
            name, prof = EX[c.wet]
            extra = c.desc
            if c.intensity is not None:
                extra += f" · ป้ายที่ควรได้ = {c.intensity}"
            out.append(f"| {c.cid} | {name} ({prof}) | {fmt_list(c.reps)} | {fmt_list(c.weights)} | {fmt_list(c.rests, fmt_rest)} | {c.T} | "
                       f"{fmt_list(c.mets, lambda v: format(v, 'g'))} | {c.session_met:.4f} | {c.kcal:.3f} kcal | {extra} |")
        out.append("")
    out.append("### ขั้น V  ค่าที่ต้องถูกปฏิเสธ (HTTP 400 และไม่มีแถวใหม่ใน DB)\n")
    out.append("| ID | ท่า | Reps | พัก (วิ) | T (วิ) | เหตุผลที่ต้องปฏิเสธ |")
    out.append("|---|---|---|---|---|---|")
    for cid, desc, wet, T, reps, w, rests in REJECT:
        name = EX.get(wet, ("ไม่มีในระบบ", ""))[0]
        r = fmt_list(reps) if len(reps) <= 6 else f"{len(reps)} เซต × {reps[0]}"
        rs = fmt_list(rests, fmt_rest) if len(rests) <= 6 else "ไม่ส่ง"
        out.append(f"| {cid} | {name} | {r} | {rs} | {T} | {desc} |")
    out.append("")
    return "\n".join(out)


# ─────────────────────────── runner ───────────────────────────
results = []  # (id, ok, detail)


def sql(q):
    return subprocess.run(MYSQL + [q], capture_output=True, text=True, encoding="utf-8").stdout.strip()


def call(method, path, body=None, token=None):
    # backend จำกัด 120 คำขอ/นาที/IP (429) — เว้นจังหวะทุกคำขอ และรอแล้วลองใหม่เมื่อโดนจำกัด
    for attempt in range(6):
        time.sleep(0.5)
        st, out = _call_once(method, path, body, token)
        if st != 429:
            return st, out
        time.sleep(20)
    return st, out


def _call_once(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")}


def check(cid, ok, detail):
    results.append((cid, ok, detail))
    print(("PASS " if ok else "FAIL ") + cid + "  " + detail)


def near(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def run():
    sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
    call("POST", "/register", {"email": EMAIL, "password": PWD, "full_name": "QA Steps"})
    otp = sql(f"SELECT mb_otp FROM member_profile WHERE mb_email='{EMAIL}'")
    _, body = call("POST", "/verify-email", {"email": EMAIL, "otp": otp})
    token = body.get("token") or body.get("data", {}).get("token")
    if not token:
        print("NO TOKEN", body)
        sys.exit(1)
    mb_id = sql(f"SELECT mb_id FROM member_profile WHERE mb_email='{EMAIL}'")
    call("PUT", "/member/body-stats", {"gender": 1, "birth_date": "2000-01-01", "weight": WEIGHT, "height": 175,
                                       "activity_level": 1.375, "target": 3}, token)
    today = datetime.date.today().isoformat()
    got_kcal = {}

    def post(wet, T, sets):
        return call("POST", "/member/workout-results", {"date": today, "wet_id": wet, "total_duration_seconds": T, "sets": sets}, token)

    def max_id():
        return int(sql(f"SELECT COALESCE(MAX(wtrs_id),0) FROM weight_training_result WHERE mb_id={mb_id}") or 0)

    seen = set()
    try:
        for c in CASES:
            key = (c.wet, c.T, tuple(c.reps), tuple(c.weights), tuple(c.rests))
            assert key not in seen, f"เคสซ้ำกัน (ติดตัวกันบันทึกซ้ำ): {c.cid}"
            seen.add(key)
            before = max_id()
            st, b = post(c.wet, c.T, c.sets())
            calc = b.get("calculation", {})
            rows = sql(f"SELECT wtrs_set_no, wtrs_rest_seconds, wtrs_duration, wtrs_calories, wtrs_intensity_level, wtrs_date "
                       f"FROM weight_training_result WHERE mb_id={mb_id} AND wtrs_id>{before} ORDER BY wtrs_set_no").splitlines()
            rows = [r.split("\t") for r in rows]
            n = len(c.reps)
            problems = []
            if st != 200:
                problems.append(f"status={st} {b.get('error')}")
            else:
                if not near(calc.get("final_met", -1), c.session_met, 0.001):
                    problems.append(f"final_met={calc.get('final_met')} want {c.session_met:.4f}")
                if not near(calc.get("session_base_met", -1), c.session_met, 0.001):
                    problems.append(f"session_base_met={calc.get('session_base_met')}")
                if not near(b.get("calories_burned", -1), c.kcal, 0.01):
                    problems.append(f"kcal={b.get('calories_burned')} want {c.kcal:.3f}")
                if not near(calc.get("duration_minutes", -1), c.T / 60.0, 0.001):
                    problems.append(f"duration_minutes={calc.get('duration_minutes')}")
                if not near(calc.get("body_weight_kg", -1), c.weight_kg, 0.001):
                    problems.append(f"body_weight_kg={calc.get('body_weight_kg')}")
                if len(rows) != n:
                    problems.append(f"rows={len(rows)} want {n}")
                else:
                    total = sum(float(r[3]) for r in rows)
                    if not near(total, c.kcal, 0.005 * n + 0.005):
                        problems.append(f"SUM(db)={total:.3f} want {c.kcal:.3f}")
                    if not all(r[2] == str(c.T) for r in rows):
                        problems.append("wtrs_duration ไม่เท่ากันทุกแถว")
                    if [r[1] for r in rows] != ["NULL" if x is None else str(x) for x in c.rests]:
                        problems.append(f"rest stored={[r[1] for r in rows]}")
                    if not all(near(r[3], c.kcal / n, 0.006) for r in rows):
                        problems.append("kcal ต่อแถวไม่เท่ากับรวม÷เซต")
                    if not all(r[5] == today for r in rows):
                        problems.append(f"date stored={rows[0][5]}")
                    if c.intensity is not None:
                        if calc.get("intensity_level") != c.intensity or not all(r[4] == str(c.intensity) for r in rows):
                            problems.append(f"intensity api={calc.get('intensity_level')} db={[r[4] for r in rows]} want {c.intensity}")
                    if c.cid == "G2":
                        nos = [r[0] for r in rows]
                        if nos != ["4", "5"]:
                            problems.append(f"set_no={nos} want [4,5]")
                    if c.cid == "G1":
                        nos = [r[0] for r in rows]
                        if nos != ["1", "2", "3"]:
                            problems.append(f"set_no={nos} want [1,2,3]")
            got_kcal[c.cid] = b.get("calories_burned")
            detail = (f"MET={calc.get('final_met')} kcal={b.get('calories_burned')} (want {c.session_met:.4f} / {c.kcal:.3f})"
                      if not problems else "; ".join(problems))
            check(c.cid, not problems, detail)

        # เทียบข้ามเคส
        check("F2", near(got_kcal["F2a"], got_kcal["F2b"], 1e-9), f"น้ำหนักยก 30 vs 100 กก. → {got_kcal['F2a']} vs {got_kcal['F2b']} (ต้องเท่ากัน)")
        b7 = next(c for c in CASES if c.cid == "B7")
        st, b = post(b7.wet, b7.T + 3, b7.sets())  # T ต่างเล็กน้อยเพื่อไม่ชนตัวกันซ้ำ แล้วคำนวณอัตราต่อวินาทีเทียบ
        per_sec_b7 = b.get("calories_burned") / (b7.T + 3)
        per_sec_a = got_kcal["F3a"] / 300
        per_sec_b = got_kcal["F3b"] / 1200
        check("F3", near(per_sec_a, per_sec_b, 1e-6) and near(per_sec_a, per_sec_b7, 1e-6) and near(got_kcal["F3b"], 4 * got_kcal["F3a"], 1e-6),
              f"kcal/วินาที T=300:{per_sec_a:.6f} T=1200:{per_sec_b:.6f} T=603:{per_sec_b7:.6f} · F3b/F3a={got_kcal['F3b'] / got_kcal['F3a']:.4f} (ต้อง 4)")

        # ปฏิเสธ
        for cid, desc, wet, T, reps, w, rests in REJECT:
            before = int(sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}"))
            sets = [{"wtrs_set_no": i + 1, "wtrs_reps": reps[i], "wtrs_weight": w[i], "wtrs_rest_seconds": rests[i]} for i in range(len(reps))]
            st, b = post(wet, T, sets)
            after = int(sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}"))
            check(cid, st == 400 and before == after, f"status={st} rows {before}->{after} · {b.get('error')}")

        # กันบันทึกซ้ำ
        r3 = next(c for c in CASES if c.cid == "R3")
        before = int(sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}"))
        st, b = post(r3.wet, r3.T, r3.sets())
        after = int(sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}"))
        check("X1", st == 200 and b.get("duplicate") is True and near(b.get("calories_burned"), r3.kcal, 0.01) and before == after,
              f"ส่ง R3 ซ้ำเป๊ะ → duplicate={b.get('duplicate')} kcal={b.get('calories_burned')} rows {before}->{after}")
        st, b = post(r3.wet, r3.T + 1, r3.sets())
        check("X2", st == 200 and b.get("duplicate") is not True, f"ส่ง R3 แต่ T+1 → duplicate={b.get('duplicate')} (ต้องบันทึกเป็นเซสชันใหม่)")

        # น้ำหนักตัวเปลี่ยน (ท้ายสุด)
        call("PUT", "/member/body-stats", {"gender": 1, "birth_date": "2000-01-01", "weight": 90.0, "height": 175,
                                           "activity_level": 1.375, "target": 3}, token)
        f1 = Case("F1", S5, "น้ำหนักตัว 90 กก.", 8, [10] * 3, [60, 60, None], 610, [3.8] * 3, weight_kg=90.0)
        st, b = post(f1.wet, f1.T, f1.sets())
        check("F1", st == 200 and near(b.get("calories_burned", -1), f1.kcal, 0.01) and near(b.get("calculation", {}).get("body_weight_kg", -1), 90.0, 0.001),
              f"น้ำหนักตัว 90 กก. Pull-up พัก 60 T=610 → kcal={b.get('calories_burned')} want {f1.kcal:.3f}")
    finally:
        sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
    return len(sql(f"SELECT mb_id FROM member_profile WHERE mb_email='{EMAIL}'")) == 0


if __name__ == "__main__":
    plan = plan_markdown()
    if "--plan" in sys.argv:
        with open(os.path.join(OUT_DIR, "_plan_tables.md"), "w", encoding="utf-8") as f:
            f.write(plan)
        print("wrote _plan_tables.md")
        sys.exit(0)
    cleaned = run()
    fails = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(fails)}/{len(results)} passed; test member deleted={cleaned}")
    with open(RESULT_PATH, "w", encoding="utf-8") as f:
        f.write(f"# ผลทดสอบอัลกอริทึมเวทเทรนนิ่งตามขั้น — {datetime.date.today().isoformat()}\n\n")
        f.write(f"ผ่าน {len(results) - len(fails)}/{len(results)} · สมาชิกทดสอบถูกลบแล้ว={cleaned} · backend พอร์ต 8082 · น้ำหนักตัวทดสอบ {WEIGHT:.0f} กก. (F1 ใช้ 90 กก.)\n\n")
        f.write("| ID | ผล | รายละเอียด (MET จริง / kcal จริง เทียบค่าที่ควรได้) |\n|---|---|---|\n")
        for cid, ok, detail in results:
            f.write(f"| {cid} | {'✅ ผ่าน' if ok else '❌ ไม่ผ่าน'} | {detail} |\n")
    sys.exit(1 if fails else 0)

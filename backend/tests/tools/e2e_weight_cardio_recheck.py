"""E2E recheck: weight-training + cardio calorie flow against a fresh backend (port 8082).
Creates one throwaway member, runs cases, prints PASS/FAIL, leaves member id for cleanup."""
import json, subprocess, sys, threading, urllib.request, urllib.error

BASE = "http://localhost:8082/api"
MYSQL = ["C:/xampp/mysql/bin/mysql.exe", "-u", "root", "food_and_fit_db", "-N", "-e"]
EMAIL = "qa-recheck-20260920@foodandfit.test"
PWD = "Recheck#2026Test"
TODAY = "2026-09-20"
WEIGHT = 70.0
K = 3.5 * WEIGHT / 200.0  # kcal per (MET-1) per minute

results = []


def sql(q):
    return subprocess.run(MYSQL + [q], capture_output=True, text=True, encoding="utf-8").stdout.strip()


def call(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
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


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (("  -> " + detail) if detail else ""))


def near(a, b, tol=0.01):
    return abs(float(a) - float(b)) <= tol


# ---- setup member ----
sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
st, _ = call("POST", "/register", {"email": EMAIL, "password": PWD, "full_name": "QA Recheck"})
print("register", st, _)
otp = sql(f"SELECT mb_otp FROM member_profile WHERE mb_email='{EMAIL}'")
st, body = call("POST", "/verify-email", {"email": EMAIL, "otp": otp})
print("verify", st)
token = body.get("token") or body.get("data", {}).get("token")
if not token:
    print("NO TOKEN", body)
    sys.exit(1)
mb_id = sql(f"SELECT mb_id FROM member_profile WHERE mb_email='{EMAIL}'")
print("mb_id", mb_id)

st, body = call("PUT", "/member/body-stats", {"gender": 1, "birth_date": "2000-01-01", "weight": WEIGHT,
                                              "height": 175, "activity_level": 1.375, "target": 3}, token)
print("body-stats", st)


def session(wet, dur, sets, date=TODAY):
    return call("POST", "/member/workout-results",
                {"date": date, "wet_id": wet, "total_duration_seconds": dur, "sets": sets}, token)


def mk(n, reps, rests, weight=20):
    """rests: list per set; last should be None (as the mobile app sends)."""
    return [{"wtrs_set_no": i + 1, "wtrs_reps": reps, "wtrs_weight": weight, "wtrs_rest_seconds": rests[i]}
            for i in range(n)]


# expected = (MET-1)*K*minutes
cases = [
    ("W1 doc example: Leg Extension(iso, machine) 4x10 rest90 T=960s -> MET5.0 -> 78.40", 30, 960,
     mk(4, 10, [90, 90, 90, None]), 5.0, 960),
    ("W2 compound resistance rest120 (Back Squat) -> MET5.0", 26, 600, mk(3, 10, [120, 120, None]), 5.0, 600),
    ("W3 Reps<8 wins over compound (Bench) -> MET6.0", 1, 900, mk(3, 5, [180, 180, None]), 6.0, 900),
    ("W4 isolation resistance rest45 (Leg Extension) -> MET3.5", 30, 480, mk(3, 12, [45, 45, None]), 3.5, 480),
    ("W5 bodyweight compound rest20 (Pull-up) -> MET8.0", 8, 300, mk(3, 10, [20, 20, None], 0), 8.0, 300),
    ("W6 bodyweight rest60 (Pull-up) -> MET3.8", 8, 420, mk(3, 10, [60, 60, None], 0), 3.8, 420),
    ("W7 bodyweight rest120 (Dips) -> MET3.5", 25, 600, mk(3, 10, [120, 120, None], 0), 3.5, 600),
    ("W8 bodyweight isolation (Crunch) rest30 -> MET2.8", 45, 300, mk(3, 20, [30, 30, None], 0), 2.8, 300),
    ("W9 single set, no rest -> density proxy 120s, isolation -> MET3.5", 30, 120,
     mk(1, 10, [None]), 3.5, 120),
    ("W10 all rest NULL (old client) 3 sets T=540s -> density 180s>90 -> compound Squat MET5.0", 26, 540,
     mk(3, 10, [None, None, None]), 5.0, 540),
    ("W11 boundary rest exactly 60 & 90 (Leg Extension iso) -> MET5.0", 30, 400,
     mk(3, 10, [60, 90, None]), 5.0, 400),
    ("W12 boundary rest 59 (Leg Extension iso) -> MET3.5", 30, 400, mk(3, 10, [59, 59, None]), 3.5, 400),
]
saved_first = None
for name, wet, dur, sets, met, secs in cases:
    st, body = session(wet, dur, sets)
    exp = (met - 1) * K * secs / 60.0
    got = body.get("calories_burned")
    calc = body.get("calculation", {})
    ok = st == 200 and got is not None and near(got, exp) and near(calc.get("final_met", -1), met, 0.001)
    check(name, ok, f"status={st} kcal={got} expected={exp:.3f} final_met={calc.get('final_met')}")
    if name.startswith("W2"):
        saved_first = (wet, dur, sets, body)

# ---- DB persistence checks (W2 session) ----
rows = sql(f"SELECT wtrs_set_no, wtrs_rest_seconds, wtrs_duration, wtrs_calories FROM weight_training_result "
           f"WHERE mb_id={mb_id} AND wet_id=26 AND wtrs_duration=600 ORDER BY wtrs_set_no").splitlines()
parsed = [r.split("\t") for r in rows]
check("D1 W2 stored 3 rows", len(parsed) == 3, str(parsed))
check("D2 last set rest stored NULL, others 120",
      len(parsed) == 3 and parsed[0][1] == "120" and parsed[1][1] == "120" and parsed[2][1] == "NULL", str(parsed))
check("D3 duration same on every row (600)", all(p[2] == "600" for p in parsed))
check("D4 per-set kcal = total/3 (49.00/3=16.33)", all(near(p[3], 49.0 / 3, 0.01) for p in parsed), str(parsed))
sum_cal = sql(f"SELECT SUM(wtrs_calories) FROM weight_training_result WHERE mb_id={mb_id} AND wet_id=26 "
              f"AND wtrs_duration=600")
check("D5 SUM(wtrs_calories) ~ session total 49.00 (rounding <=0.02)", near(sum_cal, 49.0, 0.02), sum_cal)

# ---- duplicate guard ----
before = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
wet, dur, sets, first_body = saved_first
st, body = session(wet, dur, sets)
after = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
check("X1 identical resubmit -> duplicate:true, same kcal, no new rows",
      st == 200 and body.get("duplicate") is True and near(body.get("calories_burned"), 49.0)
      and before == after, f"status={st} dup={body.get('duplicate')} rows {before}->{after}")

# parallel double-tap on a NEW payload
par_sets = mk(2, 9, [75, None])
outs = []


def fire():
    outs.append(session(30, 500, par_sets))


b2 = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
ts = [threading.Thread(target=fire) for _ in range(5)]
[t.start() for t in ts]
[t.join() for t in ts]
a2 = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
dups = sum(1 for s, b in outs if b.get("duplicate") is True)
check("X2 5 parallel identical submits -> exactly 2 new rows, 4 marked duplicate",
      int(a2) - int(b2) == 2 and dups == 4 and all(s == 200 for s, _ in outs),
      f"rows +{int(a2) - int(b2)}, duplicates={dups}, statuses={[s for s, _ in outs]}")

# different payload (different duration) must NOT be treated as duplicate
st, body = session(wet, dur + 1, sets)
check("X3 same sets but different duration -> saved as new session", st == 200 and body.get("duplicate") is not True)

# ---- validation (must be 400 and write nothing) ----
b3 = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
bad = [
    ("V1 total time <5s per set", session(30, 10, mk(3, 10, [30, 30, None]))),
    ("V2 total time > 2h", session(30, 7300, mk(3, 10, [30, 30, None]))),
    ("V3 negative rest", session(30, 600, mk(3, 10, [-5, 30, None]))),
    ("V4 rest > total time", session(30, 100, mk(2, 10, [500, None]))),
    ("V5 reps 0", session(30, 600, [{"wtrs_set_no": 1, "wtrs_reps": 0, "wtrs_weight": 10}])),
    ("V6 reps 1000", session(30, 600, mk(1, 1000, [None]))),
    ("V7 weight 1000kg", session(30, 600, mk(1, 10, [None], 1000))),
    ("V8 51 sets", session(30, 3600, mk(51, 10, [None] * 51))),
    ("V9 unknown exercise", session(99999, 600, mk(2, 10, [30, None]))),
    ("V10 sum(rest) > total+10s", session(30, 200, mk(3, 10, [150, 150, None]))),
]
for name, (st, body) in bad:
    check(name + " -> 400", st == 400, f"status={st} {body.get('error')}")
a3 = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
check("V11 rejected requests wrote no rows", a3 == b3, f"{b3}->{a3}")

# ---- cardio ----
def cardio(cdo, dur, dist=0, extra=None, date=TODAY):
    body = {"date": date, "cdo_id": cdo, "cdors_duration": dur, "cdors_distance": dist}
    body.update(extra or {})
    return call("POST", "/member/cardio-results", body, token)


st, body = cardio(3, 1800, 10)
check("C1 Cycling METs7.0 30min 70kg -> 220.50", st in (200, 201) and near(body.get("calories_burned"), 6 * K * 30),
      f"status={st} kcal={body.get('calories_burned')}")
st, body = cardio(9, 3600, 1.5, {"weight_kg": 200, "mets": 1})
check("C2 Swim METs6.0 60min; client-sent weight/mets ignored -> 367.50",
      st in (200, 201) and near(body.get("calories_burned"), 5 * K * 60),
      f"status={st} kcal={body.get('calories_burned')} calc={body.get('calculation')}")
st, body = cardio(6, 600)
check("C3 Jump rope METs12.3 10min (no distance) -> 138.42",
      st in (200, 201) and near(body.get("calories_burned"), 11.3 * K * 10),
      f"status={st} kcal={body.get('calories_burned')}")
row = sql(f"SELECT cdors_distance FROM cardio_result WHERE mb_id={mb_id} AND cdo_id=6")
check("C4 no-distance activity stores NULL distance", row == "NULL", row)
check("C5 cardio duration 0 -> 400", cardio(3, 0)[0] == 400)
check("C6 unknown cardio id -> 404", cardio(99999, 600)[0] == 404)

# ---- Energy balance sanity: weight+cardio sums appear in analytics source ----
tot_w = sql(f"SELECT ROUND(SUM(wtrs_calories),2) FROM weight_training_result WHERE mb_id={mb_id} AND wtrs_date='{TODAY}'")
tot_c = sql(f"SELECT ROUND(SUM(cdors_calories),2) FROM cardio_result WHERE mb_id={mb_id} AND cdors_date='{TODAY}'")
print("DB totals today: weight", tot_w, "cardio", tot_c)

print()
fails = [r for r in results if not r[1]]
print(f"{len(results) - len(fails)}/{len(results)} passed; member mb_id={mb_id}")
sys.exit(1 if fails else 0)

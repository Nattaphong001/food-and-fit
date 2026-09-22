"""E2E: bodyweight abs exercises (Plank 34, Hanging Leg Raise 35, Crunch 45) must get MET 2.8 for any rest time;
Pull-up (8) / Dips (25) stay on rest-based METs. Needs backend on port 8082. Creates then deletes one throwaway member."""
import json, subprocess, sys, urllib.request, urllib.error

BASE = "http://localhost:8082/api"
MYSQL = ["C:/xampp/mysql/bin/mysql.exe", "-u", "root", "food_and_fit_db", "-N", "-e"]
EMAIL = "qa-abs-20260920@foodandfit.test"
PWD = "AbsCheck#2026Test"
WEIGHT = 70.0
K = 3.5 * WEIGHT / 200.0
results = []


def sql(q):
    return subprocess.run(MYSQL + [q], capture_output=True, text=True, encoding="utf-8").stdout.strip()


def call(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("  -> " + detail if detail else ""))


sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")
call("POST", "/register", {"email": EMAIL, "password": PWD, "full_name": "QA Abs"})
otp = sql(f"SELECT mb_otp FROM member_profile WHERE mb_email='{EMAIL}'")
_, body = call("POST", "/verify-email", {"email": EMAIL, "otp": otp})
token = body.get("token") or body.get("data", {}).get("token")
if not token:
    print("NO TOKEN", body); sys.exit(1)
mb_id = sql(f"SELECT mb_id FROM member_profile WHERE mb_email='{EMAIL}'")
call("PUT", "/member/body-stats", {"gender": 1, "birth_date": "2000-01-01", "weight": WEIGHT, "height": 175,
                                   "activity_level": 1.375, "target": 3}, token)

# (label, wet_id, rest seconds, expected MET) — 3 sets x 10 reps, T=300s, last set rest NULL as the mobile app sends
cases = [
    ("Plank rest20  (was 8.0 when Compound)", 34, 20, 2.8),
    ("Plank rest60  (was 3.8 when Compound)", 34, 60, 2.8),
    ("Plank rest120 (was 3.5 when Compound)", 34, 120, 2.8),
    ("Hanging Leg Raise rest20", 35, 20, 2.8),
    ("Hanging Leg Raise rest60", 35, 60, 2.8),
    ("Crunch rest20", 45, 20, 2.8),
    ("Pull-up rest20 stays 8.0", 8, 20, 8.0),
    ("Pull-up rest60 stays 3.8", 8, 60, 3.8),
    ("Dips rest120 stays 3.5", 25, 120, 3.5),
]
try:
    for i, (name, wet, rest, met) in enumerate(cases):
        dur = 300 + i  # distinct duration per case so the duplicate guard never fires
        sets = [{"wtrs_set_no": n + 1, "wtrs_reps": 10, "wtrs_weight": 0,
                 "wtrs_rest_seconds": rest if n < 2 else None} for n in range(3)]
        st, b = call("POST", "/member/workout-results",
                     {"date": "2026-09-20", "wet_id": wet, "total_duration_seconds": dur, "sets": sets}, token)
        exp = (met - 1) * K * dur / 60.0
        got = b.get("calories_burned")
        ok = st == 200 and got is not None and abs(float(got) - exp) <= 0.01 \
            and abs(float(b.get("calculation", {}).get("final_met", -1)) - met) <= 0.001
        check(f"{name} -> MET {met}", ok, f"status={st} kcal={got} expected={exp:.3f} final_met={b.get('calculation', {}).get('final_met')}")
        stored = sql(f"SELECT ROUND(SUM(wtrs_calories),2) FROM weight_training_result WHERE mb_id={mb_id} AND wet_id={wet} AND wtrs_duration={dur}")
        check(f"  stored SUM(wtrs_calories) matches ({name})", abs(float(stored or -1) - exp) <= 0.02, f"db={stored}")
finally:
    sql(f"DELETE FROM member_profile WHERE mb_email='{EMAIL}'")

print(f"\n{sum(results)}/{len(results)} passed; test member deleted")
sys.exit(0 if all(results) else 1)

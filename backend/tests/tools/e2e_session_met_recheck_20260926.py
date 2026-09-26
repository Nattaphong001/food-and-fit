"""E2E recheck 2026-09-26: Session MET + Effort Ratio weight-training formula, cardio formula,
and the 3 anti-gaming fixes added this session (per-set duration cap, abnormal-1RM-jump warning,
duplicate-submission guard). Runs against the real backend on port 8081 + real MySQL.
Creates one throwaway member, runs cases, prints PASS/FAIL, cleans up the member row at the end."""
import json, subprocess, sys, urllib.request, urllib.error

BASE = "http://localhost:8081/api"
MYSQL = ["C:/xampp/mysql/bin/mysql.exe", "-u", "root", "food_and_fit_db", "-N", "-e"]
EMAIL = "qa-session-met-20260926@foodandfit.test"
PWD = "Recheck#2026Test"
TODAY = "2026-09-26"
WEIGHT = 70.0
K = 3.5 * WEIGHT / 200.0  # kcal per (MET-1) per minute, ACSM coefficient

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
st, _ = call("POST", "/register", {"email": EMAIL, "password": PWD, "full_name": "QA SessionMET"})
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
print("body-stats", st, body.get("warnings"))


def session(wet, dur, sets, date=TODAY):
    return call("POST", "/member/workout-results",
                {"date": date, "wet_id": wet, "total_duration_seconds": dur, "sets": sets}, token)


def mk(n, reps, weight=20):
    return [{"wtrs_set_no": i + 1, "wtrs_reps": reps, "wtrs_weight": weight} for i in range(n)]


# wet_id 1 = Bench Press (equipment 1, barbell) · wet_id 8 = Pull-up (equipment 5, bodyweight)

# ---- W1: bodyweight always MET 3.0 regardless of reps ----
st, body = session(8, 300, mk(3, 10, weight=0))
exp = (3.0 - 1) * K * 5.0
calc = body.get("calculation", {})
check("W1 bodyweight (Pull-up) 3x10 -> MET 3.0 always",
      st == 200 and near(body.get("calories_burned"), exp) and calc.get("session_met") == 3.0,
      f"status={st} kcal={body.get('calories_burned')} expected={exp:.3f} met={calc.get('session_met')}")

# ---- W2: first time training this exercise, no history, low reps (<=7) -> heavy fallback MET 6.0 ----
st, body = session(1, 300, mk(3, 5, weight=60))
exp = (6.0 - 1) * K * 5.0
calc = body.get("calculation", {})
check("W2 no-history low-reps(5) fallback -> MET 6.0 (heavy)",
      st == 200 and near(body.get("calories_burned"), exp) and calc.get("session_met") == 6.0,
      f"status={st} kcal={body.get('calories_burned')} expected={exp:.3f} met={calc.get('session_met')}")
# after this session, Best 1RM history now exists for wet_id=1 (weight 60 x 5 reps -> Epley est)

# ---- W3: now has history, moderate effort (low weight relative to best 1RM) -> MET 3.5 ----
st, body = session(1, 300, mk(3, 10, weight=20))
exp = (3.5 - 1) * K * 5.0
calc = body.get("calculation", {})
check("W3 with-history low-effort (20kgx10 vs best1rm~70) -> MET 3.5 (moderate)",
      st == 200 and near(body.get("calories_burned"), exp) and calc.get("session_met") == 3.5,
      f"status={st} kcal={body.get('calories_burned')} expected={exp:.3f} met={calc.get('session_met')} "
      f"1rm_used={calc.get('one_rep_max_used')}")

# ---- W4: with history, near-max effort (ER >= 0.90) -> MET 6.0 heavy ----
# best 1RM so far ~ max(60*(1+5/30), 20*(1+10/30)) = max(70.0, 26.67) = 70.0
# to get ER>=0.90 need weight*(1+reps/30) >= 63 -> e.g. weight=58, reps=5 -> 58*(1+5/30)=67.67 ER=0.967
st, body = session(1, 300, mk(3, 5, weight=58))
calc = body.get("calculation", {})
check("W4 with-history near-max effort (58kgx5, ER>=0.90) -> MET 6.0 (heavy)",
      st == 200 and calc.get("session_met") == 6.0,
      f"status={st} kcal={body.get('calories_burned')} met={calc.get('session_met')} 1rm_used={calc.get('one_rep_max_used')}")

# ---- V1 (new): per-set duration cap - 3 sets, duration > 3*600=1800s must reject ----
st, body = session(1, 1801, mk(3, 10, weight=20))
check("V1 NEW per-set cap: 3 sets @ 1801s (>600s/set) -> 400", st == 400, f"status={st} err={body.get('error')}")

st, body = session(1, 1800, mk(3, 10, weight=20))
check("V2 NEW per-set cap boundary: 3 sets @ 1800s (=600s/set) -> 200 (accepted)",
      st == 200, f"status={st} body={body}")

# ---- W5 (new): abnormal 1RM jump warning, non-blocking ----
# current best1rm ~70 (from W2). 58kg x reps=10 -> est=58*(1+10/30)=77.33, still < 70*1.2=84 -> no warning
# use 90kg x 5 reps -> est=90*(1+5/30)=105.0 >> 70*1.2=84 -> should warn but still save (200)
st, body = session(1, 300, mk(1, 5, weight=90))
warns = body.get("warnings") or []
check("W5 NEW abnormal-1RM-jump warning present, request still saved (200)",
      st == 200 and len(warns) > 0, f"status={st} warnings={warns}")

st, body = session(1, 300, mk(1, 5, weight=25))
warns2 = body.get("warnings") or []
check("W6 normal weight -> no warning", st == 200 and len(warns2) == 0, f"status={st} warnings={warns2}")

# ---- X1: duplicate guard still works ----
before = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
st, body = session(8, 300, mk(3, 10, weight=0))
after = sql(f"SELECT COUNT(*) FROM weight_training_result WHERE mb_id={mb_id}")
check("X1 identical resubmit of W1 payload -> duplicate:true, no new rows",
      st == 200 and body.get("duplicate") is True and before == after,
      f"status={st} dup={body.get('duplicate')} rows {before}->{after}")

# ---- cardio: unchanged formula, sanity check ----
def cardio(cdo, dur, dist=0, date=TODAY):
    return call("POST", "/member/cardio-results",
                {"date": date, "cdo_id": cdo, "cdors_duration": dur, "cdors_distance": dist}, token)


st, body = cardio(3, 1800, 5.0)  # cdo_id=3, METs=7.0 per earlier DB query
exp = (7.0 - 1) * K * 30.0
check("C1 cardio cdo_id=3 (MET 7.0) 30min -> matches ACSM formula",
      st in (200, 201) and near(body.get("calories_burned"), exp),
      f"status={st} kcal={body.get('calories_burned')} expected={exp:.3f}")

st, body = cardio(3, 59)
check("C2 cardio duration 59s (<60 min) -> 400", st == 400, f"status={st}")

print()
fails = [r for r in results if not r[1]]
print(f"{len(results) - len(fails)}/{len(results)} passed; member mb_id={mb_id}")
if not fails:
    sql(f"DELETE FROM member_profile WHERE mb_id={mb_id}")
    print("cleanup: test member deleted")
else:
    print(f"NOT cleaning up mb_id={mb_id} (kept for debugging failures)")
sys.exit(1 if fails else 0)

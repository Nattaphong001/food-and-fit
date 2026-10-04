package controllers

// ทดสอบ SaveWorkoutResult ครบทุกเงื่อนไขของข้อมูลเข้า/ชนิดท่า/แหล่ง 1RM อ้างอิง + ช่องโหว่ที่ตรวจพบ (2026-10-04)
// ใช้ฐานทดสอบ food_and_fit_test เดียวกับ workout_save_integration_test.go (ตัวช่วย newFixture/post/wset ใช้ร่วมกัน)
//
// ส่วนที่ 4 = ช่องโหว่ที่ตรวจพบ 2026-10-04 และแก้แล้ว (test คู่กับการแก้) · ส่วนที่ 5 = ข้อจำกัดที่ยังอยู่ ล็อกพฤติกรรมปัจจุบันไว้

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/gin-gonic/gin"
)

// insertExercise เพิ่มท่าทดสอบ — equipment 1-5 (5 = Bodyweight), timed = ท่าค้างเวลา (ไม่มีช่องจำนวนครั้ง)
func (f *fixture) insertExercise(t *testing.T, name string, equipment int, timed bool, difficulty int) uint {
	t.Helper()
	if err := f.db.Exec("INSERT INTO weight_exercises (wet_name, wet_description, wet_technique, wet_equipment, wet_is_timed, wet_difficulty, wet_exercise_type) VALUES (?, '', '', ?, ?, ?, 1)",
		name, equipment, timed, difficulty).Error; err != nil {
		t.Fatal(err)
	}
	var id uint
	f.db.Raw("SELECT LAST_INSERT_ID()").Scan(&id)
	return id
}

// insertHistory ใส่ประวัติ (PR) ของท่านี้เมื่อ 5 วันก่อน
func (f *fixture) insertHistory(t *testing.T, wetID uint, weight float64, reps int) {
	t.Helper()
	if err := f.db.Exec("INSERT INTO weight_training_result (wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_work_seconds, wtrs_rest_seconds, wtrs_calories, mb_id, wet_id) VALUES (DATE_SUB(CURDATE(), INTERVAL 5 DAY), 1, ?, ?, 40, 80, 10, ?, ?)",
		weight, reps, f.memberID, wetID).Error; err != nil {
		t.Fatal(err)
	}
}

// insertOtherMember เพิ่มสมาชิกอีกคน (ตรวจการแยกข้อมูลระหว่างสมาชิก)
func (f *fixture) insertOtherMember(t *testing.T, email string) int {
	t.Helper()
	if err := f.db.Exec("INSERT INTO member_profile (mb_full_name, mb_email, mb_password_hash) VALUES ('คนอื่น', ?, 'x')", email).Error; err != nil {
		t.Fatal(err)
	}
	var id int
	f.db.Raw("SELECT LAST_INSERT_ID()").Scan(&id)
	return id
}

func metsOf(body map[string]any) []float64 {
	calc, _ := body["calculation"].(map[string]any)
	raw, _ := calc["mets_per_set"].([]any)
	out := make([]float64, len(raw))
	for i, v := range raw {
		out[i], _ = v.(float64)
	}
	return out
}

func sourceOf(body map[string]any) string {
	calc, _ := body["calculation"].(map[string]any)
	s, _ := calc["reference_source"].(string)
	return s
}

func (s setIn) withRest(r int) setIn { s["wtrs_rest_seconds"] = r; return s }

// reqN สร้างคำขอ n เซต (ค่าเริ่มต้น เซตละ work 40 + rest 80 วิ) หรือกำหนด work/rest เอง
func reqN(f *fixture, wetID uint, n int, workRest ...int) map[string]any {
	work, rest := 40, 80
	if len(workRest) == 2 {
		work, rest = workRest[0], workRest[1]
	}
	sets := make([]setIn, n)
	for i := range sets {
		sets[i] = wset(i+1, 5, 50, work, rest, nil)
	}
	return f.weightReq(wetID, sets...)
}

// ── 1. ข้อมูลเข้าไม่ถูกต้อง → 400 และต้องไม่เขียน DB ──

func TestSaveWorkoutResult_InvalidInput_Rejected(t *testing.T) {
	f := newFixture(t, 70)
	timedID := f.insertExercise(t, "Plank test", 5, true, 1)
	good := func() setIn { return wset(1, 5, 80, 40, 80, nil) }
	with := func(k string, v any) setIn { s := good(); s[k] = v; return s }
	req := func(wetID uint, sets ...setIn) map[string]any { return f.weightReq(wetID, sets...) }

	cases := []struct {
		name string
		body any
	}{
		{"ไม่มี sets", map[string]any{"date": today(), "wet_id": f.barbellID}},
		{"sets ว่าง", req(f.barbellID)},
		{"ไม่มี wet_id", map[string]any{"date": today(), "sets": []setIn{good()}}},
		{"wet_id = 0", req(0, good())},
		{"ไม่มี date", map[string]any{"wet_id": f.barbellID, "sets": []setIn{good()}}},
		{"ท่าที่ไม่มีในระบบ", req(999999, good())},
		{"wtrs_set_no = 0", req(f.barbellID, with("wtrs_set_no", 0))},
		{"reps ติดลบ", req(f.barbellID, with("wtrs_reps", -1))},
		{"reps = 0 ท่าอุปกรณ์", req(f.barbellID, with("wtrs_reps", 0))},
		{"reps = 1000", req(f.barbellID, with("wtrs_reps", 1000))},
		{"reps เป็นทศนิยม", req(f.barbellID, with("wtrs_reps", 5.5))},
		{"น้ำหนักติดลบ", req(f.barbellID, with("wtrs_weight", -5))},
		{"น้ำหนัก 1000", req(f.barbellID, with("wtrs_weight", 1000))},
		{"work_seconds = 0", req(f.barbellID, with("wtrs_work_seconds", 0))},
		{"work_seconds ติดลบ", req(f.barbellID, with("wtrs_work_seconds", -10))},
		{"rest_seconds ติดลบ", req(f.barbellID, with("wtrs_rest_seconds", -1))},
		{"เซตเดียวยาวเกิน 600 วิ", req(f.barbellID, with("wtrs_work_seconds", 601).withRest(0))},
		{"เวลารวมสั้นกว่า 5 วิ/เซต", req(f.barbellID, with("wtrs_work_seconds", 4).withRest(0))},
		{"บอดี้เวทส่งน้ำหนักมา", req(f.bodyID, wset(1, 10, 20, 40, 80, nil))},
		{"ท่าค้างเวลาส่ง reps มา", req(timedID, wset(1, 10, 0, 40, 80, nil))},
		{"ท่าค้างเวลาส่งน้ำหนักมา", req(timedID, wset(1, 0, 20, 40, 80, nil))},
		{"เกิน 50 เซต", reqN(f, f.barbellID, 51)},
		{"เวลารวมเกิน 7200 วิ", reqN(f, f.barbellID, 13, 600, 0)},
		{"wet_id เป็นข้อความ", map[string]any{"date": today(), "wet_id": "abc", "sets": []setIn{good()}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, body := f.post("/workout-results", tc.body)
			if code != http.StatusBadRequest {
				t.Fatalf("got %d %v, want 400", code, body)
			}
			if errText(body) == "" {
				t.Errorf("ต้องมีข้อความ error")
			}
			if n := f.countRows("weight_training_result"); n != 0 {
				t.Errorf("ต้องไม่เขียน DB เมื่อ 400 แต่มี %d แถว", n)
			}
		})
	}
}

func TestSaveWorkoutResult_MalformedJSON_Rejected(t *testing.T) {
	f := newFixture(t, 70)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/workout-results", bytes.NewReader([]byte(`{"date":`)))
	r.Header.Set("Content-Type", "application/json")
	f.router().ServeHTTP(w, r)
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

func TestSaveWorkoutResult_NoUser_Unauthorized(t *testing.T) {
	f := newFixture(t, 70)
	r := gin.New() // ไม่มี middleware ใส่ user_id
	r.POST("/workout-results", SaveWorkoutResult)
	raw, _ := json.Marshal(f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil)))
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/workout-results", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
	if n := f.countRows("weight_training_result"); n != 0 {
		t.Errorf("rows = %d, want 0", n)
	}
}

// ── 2. ชนิดท่า × METs (น้ำหนักตัว 70 กก. → 1.225 kcal/นาที ต่อ 1 Net MET, เซตละ 120 วิ) ──

func TestSaveWorkoutResult_ExerciseTypes_Mets(t *testing.T) {
	f := newFixture(t, 70)
	timed1 := f.insertExercise(t, "Plank test", 5, true, 1)
	timed3 := f.insertExercise(t, "Hollow hold test", 5, true, 3)
	body2 := f.insertExercise(t, "Push-up test", 5, false, 2)
	body3 := f.insertExercise(t, "Pull-up test", 5, false, 3)
	weightedTimed := f.insertExercise(t, "Weighted hold test", 2, true, 2) // อุปกรณ์ + ค้างเวลา (ไม่พบใน seed จริง)

	cases := []struct {
		name     string
		wetID    uint
		set      setIn
		wantMets float64
		wantKcal float64
	}{
		{"บอดี้เวท ความยาก 1", f.bodyID, wset(1, 10, 0, 40, 80, nil), 2.8, 4.41},
		{"บอดี้เวท ความยาก 2", body2, wset(1, 10, 0, 40, 80, nil), 3.8, 6.86},
		{"บอดี้เวท ความยาก 3", body3, wset(1, 10, 0, 40, 80, nil), 3.8, 6.86},
		{"ค้างเวลา ความยาก 1", timed1, wset(1, 0, 0, 40, 80, nil), 2.8, 4.41},
		{"ค้างเวลา ความยาก 3", timed3, wset(1, 0, 0, 40, 80, nil), 3.8, 6.86},
		// ท่าอุปกรณ์ที่เป็นแบบค้างเวลา: น้ำหนักที่ใส่ไม่มีผลต่อ METs (ไม่มี reps → ไม่มี 1RM) ได้ METs บอดี้เวทตามความยาก
		{"อุปกรณ์+ค้างเวลา น้ำหนัก 30 (ข้อจำกัด: น้ำหนักไม่มีผล)", weightedTimed, wset(1, 0, 30, 40, 80, nil), 3.8, 6.86},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			code, body := f.post("/workout-results", f.weightReq(tc.wetID, tc.set))
			if code != http.StatusOK {
				t.Fatalf("got %d %v", code, body)
			}
			if m := metsOf(body); len(m) != 1 || m[0] != tc.wantMets {
				t.Errorf("mets = %v, want [%v]", m, tc.wantMets)
			}
			if sourceOf(body) != "not_applicable" {
				t.Errorf("reference_source = %s, want not_applicable", sourceOf(body))
			}
			if k := body["calories_burned"].(float64); !near(k, tc.wantKcal) {
				t.Errorf("calories = %v, want %v", k, tc.wantKcal)
			}
			if e := body["estimated_1rm"].(float64); tc.set["wtrs_reps"] == 0 && e != 0 {
				t.Errorf("estimated_1rm = %v, want 0 (ไม่มี reps)", e)
			}
		})
	}
}

// ท่าอุปกรณ์แต่กรอกน้ำหนัก 0 (ระบบไม่บล็อก) → METs 3.0 ต่ำกว่า 3.5 ของยกเบาที่มีน้ำหนัก
func TestSaveWorkoutResult_EquipmentZeroWeight_Mets3(t *testing.T) {
	f := newFixture(t, 70)
	f.insertHistory(t, f.barbellID, 75, 10) // PR 100
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 10, 0, 40, 80, nil), wset(2, 10, 20, 40, 80, nil)))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	if m := metsOf(body); m[0] != 3.0 || m[1] != 3.5 {
		t.Errorf("mets = %v, want [3 3.5]", m)
	}
}

// ── 3. แหล่ง 1RM อ้างอิง × ขอบ 70% ผ่าน endpoint จริง ──

func TestSaveWorkoutResult_History_70PercentBoundary(t *testing.T) {
	f := newFixture(t, 70)
	f.insertHistory(t, f.barbellID, 75, 10) // Epley: 75 × (1+10/30) = 100.00
	cases := []struct {
		weight float64
		reps   int
		want   float64
	}{{69.99, 5, 3.5}, {70, 5, 6.0}, {70.01, 5, 6.0}, {100, 5, 6.0}, {150, 3, 6.0}, {50, 20, 3.5}, {90, 21, 3.5}}
	for _, tc := range cases {
		// ล้างของวันนี้ทุกรอบ กันเพดานรายวัน/เลขเซต/fingerprint ชนกัน (ประวัติ 5 วันก่อนยังอยู่)
		f.db.Exec("DELETE FROM weight_training_result WHERE mb_id = ? AND wtrs_date = CURDATE()", f.memberID)
		code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, tc.reps, tc.weight, 40, 80, nil)))
		if code != http.StatusOK {
			t.Fatalf("%v×%d: got %d %v", tc.weight, tc.reps, code, body)
		}
		if m := metsOf(body); m[0] != tc.want || sourceOf(body) != "history" {
			t.Errorf("%v×%d: mets=%v src=%s, want %v/history", tc.weight, tc.reps, m, sourceOf(body), tc.want)
		}
	}
}

// ไม่มี PR + ยืนยันแต่ทุกเซต reps > 20 → ไม่มีตัวอ้างอิง (none) ทุกเซต 3.5
func TestSaveWorkoutResult_FirstSession_FlaggedButOver20Reps_None(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 25, 30, 40, 80, ptr(true))))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	if sourceOf(body) != "none" || metsOf(body)[0] != 3.5 {
		t.Errorf("src=%s mets=%v, want none/3.5", sourceOf(body), metsOf(body))
	}
}

// PR ของเซสชันนี้ยังไม่มีผลกับตัวเอง แต่มีผลกับเซสชันถัดไป (ดึง PR ก่อนบันทึกเสมอ)
func TestSaveWorkoutResult_PRCarriesToNextSession(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(true))))
	if code != http.StatusOK || sourceOf(body) != "session" {
		t.Fatalf("session 1: %d src=%s", code, sourceOf(body))
	}
	// 80×5 → e1RM 93.33 · เซสชัน 2: 66×5 = 70.7% → 6.0 · 60×5 = 64.3% → 3.5
	code, body = f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 66, 40, 80, ptr(false)), wset(2, 5, 60, 40, 80, ptr(false))))
	if code != http.StatusOK || sourceOf(body) != "history" {
		t.Fatalf("session 2: %d src=%s", code, sourceOf(body))
	}
	if m := metsOf(body); m[0] != 6.0 || m[1] != 3.5 {
		t.Errorf("mets = %v, want [6 3.5]", m)
	}
}

// เลขเซตต่อเนื่องทั้งวัน ไม่ใช้เลขจาก client (client ส่ง 1,1 ก็ต้องได้ 1,2 แล้ว 3,4)
func TestSaveWorkoutResult_SetNumbersContinueAcrossRounds(t *testing.T) {
	f := newFixture(t, 70)
	f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil), wset(1, 5, 80, 41, 80, nil)))
	f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 6, 80, 40, 80, nil), wset(1, 6, 80, 41, 80, nil)))
	var nos []int
	f.db.Raw("SELECT wtrs_set_no FROM weight_training_result WHERE mb_id = ? ORDER BY wtrs_id", f.memberID).Scan(&nos)
	if len(nos) != 4 || nos[0] != 1 || nos[1] != 2 || nos[2] != 3 || nos[3] != 4 {
		t.Errorf("set_no = %v, want [1 2 3 4]", nos)
	}
}

// date ในคำขอไม่มีผล — เซิร์ฟเวอร์บันทึกเป็นวันนี้เสมอ (กันบันทึกย้อนหลัง/ล่วงหน้าเพื่อเลี่ยงเพดานรายวัน)
func TestSaveWorkoutResult_DateFieldIgnored_SavedAsToday(t *testing.T) {
	f := newFixture(t, 70)
	req := f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil))
	req["date"] = "1999-01-01"
	if code, body := f.post("/workout-results", req); code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	var n int64
	f.db.Raw("SELECT COUNT(*) FROM weight_training_result WHERE mb_id = ? AND wtrs_date = CURDATE()", f.memberID).Scan(&n)
	if n != 1 {
		t.Errorf("แถวของวันนี้ = %d, want 1", n)
	}
}

// เตือน (ไม่ block) เมื่อ e1RM กระโดด > 120% ของ PR เดิม — ขอบ 140 (PR 116.67 × 1.2)
func TestSaveWorkoutResult_AbnormalJumpWarning(t *testing.T) {
	f := newFixture(t, 70)
	f.insertHistory(t, f.barbellID, 100, 5)                                                           // 116.67
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 10, 100, 40, 80, nil))) // 133.33 ไม่เตือน
	if code != http.StatusOK || len(body["warnings"].([]any)) != 0 {
		t.Fatalf("100×10: %d warnings=%v, want ไม่เตือน", code, body["warnings"])
	}
	code, body = f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 10, 120, 40, 80, nil))) // 160 เตือน แต่ยังบันทึก
	if code != http.StatusOK || len(body["warnings"].([]any)) != 1 {
		t.Fatalf("120×10: %d warnings=%v, want 1 คำเตือน (ไม่ block)", code, body["warnings"])
	}
	if n := f.countRows("weight_training_result"); n != 3 {
		t.Errorf("rows = %d, want 3 (1 ประวัติ + 2 เซสชัน)", n)
	}
}

// ผู้ใช้แต่ละคนแยกกัน: PR ของคนอื่นต้องไม่เป็นตัวอ้างอิงของเรา
func TestSaveWorkoutResult_HistoryIsPerMember(t *testing.T) {
	f := newFixture(t, 70)
	otherID := f.insertOtherMember(t, "other2@test.local")
	f.db.Exec("INSERT INTO weight_training_result (wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_work_seconds, wtrs_rest_seconds, wtrs_calories, mb_id, wet_id) VALUES (DATE_SUB(CURDATE(), INTERVAL 5 DAY), 1, 300, 1, 40, 80, 10, ?, ?)", otherID, f.barbellID)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(true))))
	if code != http.StatusOK || sourceOf(body) != "session" {
		t.Errorf("got %d src=%s, want session (ไม่ใช้ PR ของคนอื่น)", code, sourceOf(body))
	}
}

// ── 4. ช่องโหว่ที่ตรวจพบ 2026-10-04 และแก้แล้ว (test คู่กับการแก้) ──

// wsch_id ต้องเป็นตารางฝึกของสมาชิกคนนี้เอง: ของคนอื่น/ที่ไม่มีอยู่จริง → 400 ไม่เขียน DB (เดิม: ของคนอื่นได้ 200 ผูกข้ามบัญชีได้,
// ที่ไม่มีจริงได้ 500 จาก FK) และต้องไม่ทิ้ง fingerprint ค้าง — ส่งซ้ำแบบถูกต้องต้องบันทึกได้ ส่วน wsch_id ของตัวเองต้องผ่านและถูกเก็บ
func TestSaveWorkoutResult_ScheduleID_MustBeOwn(t *testing.T) {
	f := newFixture(t, 70)
	otherID := f.insertOtherMember(t, "other@test.local")
	insertSchedule := func(mbID int) uint {
		if err := f.db.Exec("INSERT INTO workout_schedules (wsch_plan_name, wsch_order, mb_id, wet_id) VALUES ('แผนทดสอบ', 1, ?, ?)", mbID, f.barbellID).Error; err != nil {
			t.Fatal(err)
		}
		var id uint
		f.db.Raw("SELECT LAST_INSERT_ID()").Scan(&id)
		return id
	}
	otherWsch, ownWsch := insertSchedule(otherID), insertSchedule(f.memberID)

	for name, wsch := range map[string]uint{"ของคนอื่น": otherWsch, "ที่ไม่มีอยู่จริง": 987654, "เป็น 0": 0} {
		req := f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil))
		req["wsch_id"] = wsch
		if code, body := f.post("/workout-results", req); code != http.StatusBadRequest {
			t.Errorf("wsch_id %s: got %d %v, want 400", name, code, body)
		}
	}
	if n := f.countRows("weight_training_result"); n != 0 {
		t.Fatalf("rows = %d หลังถูกปฏิเสธ, want 0", n)
	}
	req := f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil))
	req["wsch_id"] = ownWsch
	if code, body := f.post("/workout-results", req); code != http.StatusOK || body["duplicate"] == true {
		t.Fatalf("wsch_id ของตัวเอง: got %d duplicate=%v, want 200", code, body["duplicate"])
	}
	var linked uint
	f.db.Raw("SELECT wsch_id FROM weight_training_result WHERE mb_id = ?", f.memberID).Scan(&linked)
	if linked != ownWsch {
		t.Errorf("wsch_id ที่บันทึก = %d, want %d", linked, ownWsch)
	}
}

// int overflow: rest = MaxInt64 สองเซต + เซตปกติ 600 วิ (เดิมผ่าน validation ได้ 200 และเก็บ kcal ติดลบ -9999.99 ต่อแถว)
// ตอนนี้ต้อง 400 และไม่เขียน DB — ทั้งแบบ rest และแบบ work ล้น
func TestSaveWorkoutResult_IntOverflow_Rejected(t *testing.T) {
	f := newFixture(t, 70)
	mx := json.Number("9223372036854775807")
	for name, field := range map[string]string{"rest ล้น": "wtrs_rest_seconds", "work ล้น": "wtrs_work_seconds"} {
		a := setIn{"wtrs_set_no": 1, "wtrs_reps": 5, "wtrs_weight": 50, "wtrs_work_seconds": 1, "wtrs_rest_seconds": 1}
		b := setIn{"wtrs_set_no": 2, "wtrs_reps": 5, "wtrs_weight": 50, "wtrs_work_seconds": 1, "wtrs_rest_seconds": 1}
		a[field], b[field] = mx, mx
		c := setIn{"wtrs_set_no": 3, "wtrs_reps": 5, "wtrs_weight": 50, "wtrs_work_seconds": 600}
		code, body := f.post("/workout-results", map[string]any{"date": today(), "wet_id": f.barbellID, "sets": []setIn{a, b, c}})
		if code != http.StatusBadRequest {
			t.Errorf("%s: got %d %v, want 400", name, code, body)
		}
	}
	if n := f.countRows("weight_training_result"); n != 0 {
		t.Errorf("rows = %d, want 0", n)
	}
	if sum := f.sumCalories("weight_training_result", "wtrs_calories"); sum < 0 {
		t.Errorf("SUM(wtrs_calories) = %v ต้องไม่ติดลบ", sum)
	}
}

// เพดานเวลาสะสมต่อท่าต่อวัน (7200 วิ) ต้องคงอยู่แม้ส่งพร้อมกันหลายคำขอ (เดิม: ส่ง 24 คำขอพร้อมกัน บันทึกได้ 9,000-12,000 วิ
// เพราะนับ SUM แล้วค่อย insert โดยไม่มี lock) ตอนนี้ล็อกแถวสมาชิกใน transaction — และเลขเซตต้องไม่ซ้ำ
func TestSaveWorkoutResult_DailyCap_HoldsUnderParallelRequests(t *testing.T) {
	f := newFixture(t, 70)
	const parallel = 24 // เซสชันละ 600 วิ → เพดาน 7200 รับได้แค่ 12 คำขอ
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok := 0
	for i := 0; i < parallel; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			w := float64(40 + i)
			code, _ := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, w, 300, 0, nil), wset(2, 5, w, 300, 0, nil)))
			if code == http.StatusOK {
				mu.Lock()
				ok++
				mu.Unlock()
			}
		}(i)
	}
	wg.Wait()
	var total int
	f.db.Raw("SELECT COALESCE(SUM(wtrs_work_seconds + COALESCE(wtrs_rest_seconds, 0)), 0) FROM weight_training_result WHERE mb_id = ?", f.memberID).Scan(&total)
	if total > 7200 {
		t.Errorf("เวลาสะสม %d เกินเพดาน 7200 (race condition)", total)
	}
	if ok != 12 || total != 7200 {
		t.Errorf("สำเร็จ %d คำขอ เวลา %d วิ — คาดว่า 12 คำขอ 7200 วิพอดี (ที่เหลือต้องโดนปฏิเสธ)", ok, total)
	}
	var distinct, rows int64
	f.db.Raw("SELECT COUNT(DISTINCT wtrs_set_no), COUNT(*) FROM weight_training_result WHERE mb_id = ?", f.memberID).Row().Scan(&distinct, &rows)
	if distinct != rows {
		t.Errorf("เลขเซตซ้ำ: %d ค่าไม่ซ้ำจาก %d แถว", distinct, rows)
	}
}

// เพดานจำนวนเซตสะสมต่อท่าต่อวัน 255 (wtrs_set_no เป็น TINYINT UNSIGNED) — เดิมเกิน 255 แล้วถูกตัดเป็น 255 ซ้ำเงียบๆ
// ตอนนี้ 250 + 10 = 260 → 400 · 250 + 5 = 255 พอดี → 200 เลขเซตไม่ซ้ำ
func TestSaveWorkoutResult_DailySetCountCap(t *testing.T) {
	f := newFixture(t, 70)
	for i := 0; i < 250; i++ {
		if err := f.db.Exec("INSERT INTO weight_training_result (wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_work_seconds, wtrs_rest_seconds, wtrs_calories, mb_id, wet_id) VALUES (CURDATE(), ?, 50, 5, 5, 0, 0.1, ?, ?)", i+1, f.memberID, f.barbellID).Error; err != nil {
			t.Fatal(err)
		}
	}
	mk := func(n int) []setIn {
		sets := make([]setIn, n)
		for i := range sets {
			sets[i] = wset(i+1, 5, 50, 5, 0, nil)
		}
		return sets
	}
	if code, body := f.post("/workout-results", f.weightReq(f.barbellID, mk(10)...)); code != http.StatusBadRequest || !strings.Contains(errText(body), "เซต") {
		t.Fatalf("250 + 10: got %d %v, want 400 เรื่องจำนวนเซต", code, body)
	}
	if n := f.countRows("weight_training_result"); n != 250 {
		t.Fatalf("rows = %d หลังถูกปฏิเสธ, want 250", n)
	}
	if code, body := f.post("/workout-results", f.weightReq(f.barbellID, mk(5)...)); code != http.StatusOK {
		t.Fatalf("250 + 5: got %d %v, want 200", code, body)
	}
	var distinct, rows, maxNo int64
	f.db.Raw("SELECT COUNT(DISTINCT wtrs_set_no), COUNT(*), MAX(wtrs_set_no) FROM weight_training_result WHERE mb_id = ?", f.memberID).Row().Scan(&distinct, &rows, &maxNo)
	if distinct != 255 || rows != 255 || maxNo != 255 {
		t.Errorf("distinct=%d rows=%d max=%d, want 255/255/255", distinct, rows, maxNo)
	}
}

// ผู้ใช้แก้คำตอบ near_failure แล้วบันทึกใหม่ภายใน 60 วิ ต้องไม่ถูกตอบเป็น duplicate (เดิมได้ผลเดิม คำตอบใหม่ไม่ถูกใช้)
// ส่วนคำขอเดิมเป๊ะยังเป็น duplicate (ครอบด้วย TestSaveWorkoutResult_Duplicate_NotDoubleCounted)
func TestSaveWorkoutResult_ChangedNearFailureIsNotDuplicate(t *testing.T) {
	f := newFixture(t, 70)
	code, first := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(false))))
	if code != http.StatusOK || sourceOf(first) != "session_declined" {
		t.Fatalf("first: %d src=%s", code, sourceOf(first))
	}
	code, second := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(true))))
	if code != http.StatusOK || second["duplicate"] == true {
		t.Errorf("second: %d duplicate=%v, want 200 และไม่ใช่ duplicate", code, second["duplicate"])
	}
	if n := f.countRows("weight_training_result"); n != 2 {
		t.Errorf("rows = %d, want 2 (บันทึกทั้ง 2 คำขอ)", n)
	}
}

// ── 5. ข้อจำกัดที่ยังอยู่ (ไม่ใช่ช่องโหว่ที่แก้ได้ด้วยโค้ดล้วน — ต้องเปิดเผยในเล่ม) ──

// Limitation (ง) (ต้องเปิดเผยในเล่ม): PR ปนเปื้อน — เซตเดียวที่กรอกผิด/โกง (500 กก. × 1) ถูกนับเป็น PR ถาวร
// GetBestOneRepMax เอา e1RM สูงสุดจากทุกแถวโดยไม่สน near_failure/ความสมเหตุสมผล และเตือน (warnings) เฉพาะเมื่อ "มี PR เดิมแล้ว"
// เซตแรกสุดของท่าจึงไม่ถูกเตือนเลย → เซสชันจริงต่อๆ ไปทุกเซตได้ 3.5 จนกว่าผู้ใช้จะลบประวัติ (DeleteWorkoutResult)
func TestLimitation_PoisonedPR_DeflatesAllLaterSessions(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 1, 500, 40, 80, nil)))
	if code != http.StatusOK || len(body["warnings"].([]any)) != 0 {
		t.Fatalf("เซตแรก: %d warnings=%v — คาดว่าไม่มีคำเตือน (ไม่มี PR ให้เทียบ)", code, body["warnings"])
	}
	code, body = f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 100, 40, 80, nil))) // 100×5 จริง ควรเป็นเซตหนัก
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	if sourceOf(body) != "history" || metsOf(body)[0] != 3.5 {
		t.Errorf("src=%s mets=%v — คาดว่าอิง PR ปนเปื้อน (516.67) ได้ 3.5", sourceOf(body), metsOf(body))
	}
}

// ── 6. คาร์ดิโอ: กันบันทึกซ้ำ + เพดานรายวันภายใต้คำขอพร้อมกัน (เพิ่ม 2026-10-04) ──

func (f *fixture) cardioReqDist(seconds int, distance float64) map[string]any {
	return map[string]any{"date": today(), "cdo_id": f.cardioID, "cdors_duration": seconds, "cdors_distance": distance}
}

// คำขอเดิมเป๊ะซ้ำ (กดรัว/ลองใหม่หลังเน็ตหลุด) → ตอบผลเดิม duplicate ไม่เพิ่มแถว/พลังงาน (เดิมคาร์ดิโอไม่มีระบบนี้ ได้ 2 แถว)
func TestSaveCardioResult_Duplicate_NotDoubleCounted(t *testing.T) {
	f := newFixture(t, 70)
	req := f.cardioReqDist(1800, 5)
	code, first := f.post("/cardio-results", req)
	if code != http.StatusCreated {
		t.Fatalf("first: %d %v", code, first)
	}
	code, second := f.post("/cardio-results", req)
	if code != http.StatusCreated || second["duplicate"] != true {
		t.Fatalf("second: %d %v, want 201 duplicate", code, second)
	}
	if second["calories_burned"] != first["calories_burned"] {
		t.Errorf("duplicate ต้องได้พลังงานเดิม %v ได้ %v", first["calories_burned"], second["calories_burned"])
	}
	if n := f.countRows("cardio_result"); n != 1 {
		t.Errorf("rows = %d, want 1", n)
	}
}

// คำขอที่ต่างกัน (ระยะทางต่าง) ไม่ใช่ duplicate — ต้องบันทึกทั้งคู่ และคำขอที่ถูกปฏิเสธต้องไม่ทิ้ง fingerprint ค้าง
func TestSaveCardioResult_DifferentRequestsBothSaved_RejectedDoesNotLinger(t *testing.T) {
	f := newFixture(t, 70)
	if code, body := f.post("/cardio-results", f.cardioReqDist(1800, 5)); code != http.StatusCreated {
		t.Fatalf("a: %d %v", code, body)
	}
	if code, body := f.post("/cardio-results", f.cardioReqDist(1800, 6)); code != http.StatusCreated || body["duplicate"] == true {
		t.Fatalf("b: %d duplicate=%v, want 201 ไม่ใช่ duplicate", code, body["duplicate"])
	}
	// ชนเพดานรายวัน (28800 วิ): ปฏิเสธ แล้วลดเวลาลงส่งใหม่ต้องผ่านได้ (ไม่ถูกจำว่าซ้ำ)
	f.db.Exec("DELETE FROM cardio_result WHERE mb_id = ?", f.memberID)
	f.db.Exec("INSERT INTO cardio_result (cdors_date, cdors_duration, cdors_distance, cdors_calories, mb_id, cdo_id) VALUES (CURDATE(), 21600, 5, 100, ?, ?)", f.memberID, f.cardioID)
	if code, _ := f.post("/cardio-results", f.cardioReqDist(10800, 7)); code != http.StatusBadRequest {
		t.Fatalf("เกินเพดานรายวัน: got %d, want 400", code)
	}
	if code, body := f.post("/cardio-results", f.cardioReqDist(7200, 7)); code != http.StatusCreated || body["duplicate"] == true {
		t.Errorf("ลดเวลาแล้วส่งใหม่: %d duplicate=%v, want 201", code, body["duplicate"])
	}
}

// เพดานเวลาคาร์ดิโอสะสมต่อวัน (28800 วิ) ต้องคงอยู่เมื่อส่งพร้อมกัน — 20 คำขอ × 3600 วิ (ระยะทางต่างกันเพื่อไม่ชน fingerprint)
// รับได้ 8 คำขอพอดี
func TestSaveCardioResult_DailyCap_HoldsUnderParallelRequests(t *testing.T) {
	f := newFixture(t, 70)
	const parallel = 20
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok := 0
	for i := 0; i < parallel; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			code, _ := f.post("/cardio-results", f.cardioReqDist(3600, float64(1+i)))
			if code == http.StatusCreated {
				mu.Lock()
				ok++
				mu.Unlock()
			}
		}(i)
	}
	wg.Wait()
	var total int
	f.db.Raw("SELECT COALESCE(SUM(cdors_duration), 0) FROM cardio_result WHERE mb_id = ?", f.memberID).Scan(&total)
	if total > 28800 {
		t.Errorf("เวลาสะสม %d เกินเพดาน 28800 (race condition)", total)
	}
	if ok != 8 || total != 28800 {
		t.Errorf("สำเร็จ %d คำขอ เวลา %d วิ — คาดว่า 8 คำขอ 28800 วิพอดี", ok, total)
	}
}

// พลังงานคาร์ดิโอที่คำนวณได้เกินที่ DECIMAL(6,2) เก็บได้ (9999.99) ต้อง 400 ไม่ตัดค่าเงียบๆ (เดิมตอบ 13,230 แต่ DB เก็บ 9999.99)
// น้ำหนักตัว 300 กก. (ค่าสูงสุดที่ ValidateWeight รับ) × METs 8.0 × 6 ชม. = 13,230 · ลดเหลือ 3 ชม. = 6,615 ต้องผ่าน และไม่ถูกจำว่าซ้ำ
func TestSaveCardioResult_CaloriesOverColumn_Rejected(t *testing.T) {
	f := newFixture(t, 300)
	code, body := f.post("/cardio-results", f.cardioReqDist(21600, 5))
	if code != http.StatusBadRequest || !strings.Contains(errText(body), "พลังงาน") {
		t.Fatalf("got %d %v, want 400 เรื่องพลังงานเกินขอบเขต", code, body)
	}
	if n := f.countRows("cardio_result"); n != 0 {
		t.Fatalf("rows = %d หลังถูกปฏิเสธ, want 0", n)
	}
	code, body = f.post("/cardio-results", f.cardioReqDist(10800, 5))
	if code != http.StatusCreated || body["duplicate"] == true || !near(body["calories_burned"].(float64), 6615) {
		t.Errorf("3 ชม.: got %d duplicate=%v kcal=%v, want 201 / 6615", code, body["duplicate"], body["calories_burned"])
	}
	if got := f.sumCalories("cardio_result", "cdors_calories"); !near(got, 6615) {
		t.Errorf("SUM ใน DB = %v ต้องตรงกับที่ตอบกลับ (6615)", got)
	}
}

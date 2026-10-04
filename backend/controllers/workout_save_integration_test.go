package controllers

// ทดสอบระดับ controller ของ SaveWorkoutResult / SaveCardioResult กับ MySQL จริง (ฐานทดสอบแยก — ห้ามใช้ food_and_fit_db)
//
// เตรียมฐานทดสอบ (ครั้งเดียว):
//   mysql -u root -e "CREATE DATABASE food_and_fit_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
//   mysql -u root food_and_fit_test < migrations/schema.sql
// ตัวแปรสภาพแวดล้อม (ไม่บังคับ): TEST_DB_USER (root) · TEST_DB_PASS ("") · TEST_DB_HOST (127.0.0.1) ·
// TEST_DB_PORT (3306) · TEST_DB_NAME (food_and_fit_test — ต้องมีคำว่า test)
// เชื่อมต่อไม่ได้ → t.Skip (ไม่ทำให้ go test ล้ม) · แต่ละเทสต์ล้างตารางที่ใช้เองก่อนรัน

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"food_and_fit_api/config"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func init() {
	// ตรงกับ main.go: เวลาของแอปตรึงเป็น Asia/Bangkok
	time.Local = time.FixedZone("Asia/Bangkok", 7*3600)
	gin.SetMode(gin.TestMode)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// openTestDB เชื่อมฐานทดสอบ + ล้างตารางที่ใช้ แล้วตั้ง config.DB (ตัว handler ใช้ตัวแปร global นี้)
func openTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	name := envOr("TEST_DB_NAME", "food_and_fit_test")
	if name == "food_and_fit_db" || !strings.Contains(name, "test") {
		t.Fatalf("ปฏิเสธรันกับฐาน %q — ต้องเป็นฐานทดสอบที่ชื่อมีคำว่า test", name)
	}
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local&timeout=3s",
		envOr("TEST_DB_USER", "root"), os.Getenv("TEST_DB_PASS"),
		envOr("TEST_DB_HOST", "127.0.0.1"), envOr("TEST_DB_PORT", "3306"), name)
	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		t.Skipf("เชื่อมฐานทดสอบ %s ไม่ได้ (ข้าม): %v", name, err)
	}
	for _, tbl := range []string{"weight_training_result", "cardio_result", "member_body_stats", "member_profile", "weight_exercises", "cardio", "cardio_category"} {
		if err := db.Exec("DELETE FROM " + tbl).Error; err != nil {
			t.Fatalf("ล้าง %s ไม่สำเร็จ (schema ครบหรือยัง?): %v", tbl, err)
		}
	}
	config.DB = db
	return db
}

type fixture struct {
	db        *gorm.DB
	memberID  int
	barbellID uint // ท่าอุปกรณ์ (wet_equipment=1)
	bodyID    uint // ท่าบอดี้เวท (wet_equipment=5)
	cardioID  uint // METs 8.0 มีระยะทาง
}

// newFixture สร้างสมาชิก 1 คน (หนัก weight กก. ถ้า weight>0) + ท่า/คาร์ดิโอตัวอย่าง
func newFixture(t *testing.T, weight float64) *fixture {
	t.Helper()
	db := openTestDB(t)
	f := &fixture{db: db}
	mustExec := func(q string, args ...any) {
		if err := db.Exec(q, args...).Error; err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	mustExec("INSERT INTO member_profile (mb_full_name, mb_email, mb_password_hash) VALUES ('ทดสอบ', 'it@test.local', 'x')")
	db.Raw("SELECT LAST_INSERT_ID()").Scan(&f.memberID)
	if weight > 0 {
		mustExec("INSERT INTO member_body_stats (mb_id, mbs_height, mbs_weight, mbs_activity_level, mbs_target, mbs_recorded_date) VALUES (?, 170, ?, 1.2, 3, NOW())", f.memberID, weight)
	}
	mustExec("INSERT INTO weight_exercises (wet_name, wet_equipment, wet_is_timed, wet_difficulty, wet_exercise_type) VALUES ('Barbell test', 1, 0, 1, 1)")
	db.Raw("SELECT LAST_INSERT_ID()").Scan(&f.barbellID)
	mustExec("INSERT INTO weight_exercises (wet_name, wet_equipment, wet_is_timed, wet_difficulty, wet_exercise_type) VALUES ('Bodyweight test', 5, 0, 1, 1)")
	db.Raw("SELECT LAST_INSERT_ID()").Scan(&f.bodyID)
	mustExec("INSERT INTO cardio_category (cdc_name) VALUES ('test')")
	var cdc uint
	db.Raw("SELECT LAST_INSERT_ID()").Scan(&cdc)
	mustExec("INSERT INTO cardio (cdo_name, cdo_mets, cdc_id, cdo_has_distance) VALUES ('Run test', 8.0, ?, 1)", cdc)
	db.Raw("SELECT LAST_INSERT_ID()").Scan(&f.cardioID)
	return f
}

func (f *fixture) router() *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set("user_id", f.memberID); c.Next() })
	r.POST("/workout-results", SaveWorkoutResult)
	r.POST("/cardio-results", SaveCardioResult)
	return r
}

func (f *fixture) post(path string, body any) (int, map[string]any) {
	raw, _ := json.Marshal(body)
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	f.router().ServeHTTP(w, req)
	var out map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

func today() string { return time.Now().Format("2006-01-02") }

type setIn map[string]any

func wset(no, reps int, weight float64, work, rest int, nearFailure *bool) setIn {
	s := setIn{"wtrs_set_no": no, "wtrs_reps": reps, "wtrs_weight": weight, "wtrs_work_seconds": work, "wtrs_rest_seconds": rest}
	if nearFailure != nil {
		s["near_failure"] = *nearFailure
	}
	return s
}

func ptr[T any](v T) *T { return &v }

func (f *fixture) weightReq(wetID uint, sets ...setIn) map[string]any {
	return map[string]any{"date": today(), "wet_id": wetID, "sets": sets}
}

func (f *fixture) countRows(table string) int64 {
	var n int64
	f.db.Raw(fmt.Sprintf("SELECT COUNT(*) FROM %s WHERE mb_id = ?", table), f.memberID).Scan(&n)
	return n
}

func (f *fixture) sumCalories(table, col string) float64 {
	var s float64
	f.db.Raw(fmt.Sprintf("SELECT COALESCE(SUM(%s),0) FROM %s WHERE mb_id = ?", col, table), f.memberID).Scan(&s)
	return s
}

func near(a, b float64) bool { d := a - b; return d < 0.005 && d > -0.005 }

func errText(body map[string]any) string { s, _ := body["error"].(string); return s }

// insertTodayWeightSeconds ใส่แถวเวทของวันนี้ให้เวลารวม (work+rest) ตรงตามต้องการ โดยแบ่งเป็นเซต 600 วิ
func (f *fixture) insertTodayWeightSeconds(t *testing.T, wetID uint, totalSeconds int) {
	t.Helper()
	for no := 1; totalSeconds > 0; no++ {
		chunk := 600
		if totalSeconds < chunk {
			chunk = totalSeconds
		}
		if err := f.db.Exec("INSERT INTO weight_training_result (wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_work_seconds, wtrs_rest_seconds, wtrs_calories, mb_id, wet_id) VALUES (CURDATE(), ?, 50, 5, ?, 0, 10, ?, ?)",
			no, chunk, f.memberID, wetID).Error; err != nil {
			t.Fatal(err)
		}
		totalSeconds -= chunk
	}
}

// ── เวทเทรนนิ่ง ──

func TestSaveWorkoutResult_NoBodyStats_Rejected(t *testing.T) {
	f := newFixture(t, 0)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil)))
	if code != http.StatusBadRequest || !strings.Contains(errText(body), "น้ำหนักตัว") {
		t.Fatalf("got %d %v, want 400 เรื่องน้ำหนักตัว", code, body)
	}
	if n := f.countRows("weight_training_result"); n != 0 {
		t.Errorf("ต้องไม่บันทึกแถวเมื่อไม่มีน้ำหนักตัว แต่มี %d แถว", n)
	}
}

// เซสชันแรกไม่มี PR: ตัวอ้างอิง = e1RM ของเซตที่ตอบ "ใช่" (80×5 → 93.33) · เซต 1 = 85.7% → 6.0 · เซต 2 (50×10) = 53.6% → 3.5
func TestSaveWorkoutResult_FirstSession_UsesNearFailureReference(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID,
		wset(1, 5, 80, 40, 80, ptr(true)), wset(2, 10, 50, 40, 80, ptr(false))))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	calc := body["calculation"].(map[string]any)
	if calc["reference_source"] != "session" {
		t.Errorf("reference_source = %v, want session", calc["reference_source"])
	}
	mets := calc["mets_per_set"].([]any)
	if mets[0].(float64) != 6.0 || mets[1].(float64) != 3.5 {
		t.Errorf("mets_per_set = %v, want [6 3.5]", mets)
	}
	// (6−1)×1.225×2 = 12.25 · (3.5−1)×1.225×2 = 6.125 → 6.13
	if got := body["calories_burned"].(float64); !near(got, 18.38) {
		t.Errorf("calories_burned = %v, want 18.38", got)
	}
	// SUM(wtrs_calories) ใน DB ต้องเท่ากับที่ตอบกลับ และเก็บครบ 2 แถว
	if got := f.sumCalories("weight_training_result", "wtrs_calories"); !near(got, body["calories_burned"].(float64)) {
		t.Errorf("SUM ใน DB = %v ไม่ตรงกับ calories_burned", got)
	}
	if n := f.countRows("weight_training_result"); n != 2 {
		t.Errorf("rows = %d, want 2", n)
	}
	// คำตอบรายเซตต้องถูกเก็บลง DB ตามลำดับเซต (1 = หมดแรงแล้ว, 0 = ยังยกได้อีก) ไว้ตรวจ/คิดมือย้อนหลัง
	var stored []*bool
	f.db.Raw("SELECT wtrs_near_failure FROM weight_training_result WHERE mb_id = ? ORDER BY wtrs_set_no", f.memberID).Scan(&stored)
	if len(stored) != 2 || stored[0] == nil || !*stored[0] || stored[1] == nil || *stored[1] {
		t.Errorf("wtrs_near_failure ใน DB = %v, want [true false]", stored)
	}
}

// ไม่ส่ง near_failure (ท่ามี PR/ไม่ได้ถาม) → เก็บเป็น NULL ไม่ใช่ 0
func TestSaveWorkoutResult_NotAsked_StoresNullNearFailure(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, nil)))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	var nullCount int64
	f.db.Raw("SELECT COUNT(*) FROM weight_training_result WHERE mb_id = ? AND wtrs_near_failure IS NULL", f.memberID).Scan(&nullCount)
	if nullCount != 1 {
		t.Errorf("แถวที่ wtrs_near_failure เป็น NULL = %d, want 1", nullCount)
	}
}

// ผู้ใช้ไม่ตอบ "ใช่" ทุกเซตตอนไม่มี PR → session_declined ทุกเซตได้ 3.5
func TestSaveWorkoutResult_FirstSession_DeclinedGivesEnduranceMets(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 100, 40, 80, ptr(false))))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	calc := body["calculation"].(map[string]any)
	if calc["reference_source"] != "session_declined" || calc["mets_per_set"].([]any)[0].(float64) != 3.5 {
		t.Errorf("calc = %v, want session_declined / 3.5", calc)
	}
}

// มี PR จากประวัติ: ใช้ PR เสมอ ไม่สนใจ near_failure (PR 100×5 → 116.67 · 80 กก. = 68.6% → 3.5 แม้ตอบ "ใช่")
func TestSaveWorkoutResult_WithHistory_IgnoresNearFailure(t *testing.T) {
	f := newFixture(t, 70)
	if err := f.db.Exec("INSERT INTO weight_training_result (wtrs_date, wtrs_set_no, wtrs_weight, wtrs_reps, wtrs_work_seconds, wtrs_rest_seconds, wtrs_calories, mb_id, wet_id) VALUES (DATE_SUB(CURDATE(), INTERVAL 5 DAY), 1, 100, 5, 40, 80, 10, ?, ?)", f.memberID, f.barbellID).Error; err != nil {
		t.Fatal(err)
	}
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(true))))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	calc := body["calculation"].(map[string]any)
	if calc["reference_source"] != "history" || !near(calc["reference_1rm"].(float64), 116.67) || calc["mets_per_set"].([]any)[0].(float64) != 3.5 {
		t.Errorf("calc = %v, want history / 116.67 / 3.5", calc)
	}
}

// ท่าบอดี้เวท ความยาก 1: METs 2.8 (02024) ไม่ใช้ 1RM — (2.8−1)×1.225×2 = 4.41
func TestSaveWorkoutResult_Bodyweight_FixedMets(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.bodyID, wset(1, 10, 0, 40, 80, ptr(true))))
	if code != http.StatusOK {
		t.Fatalf("got %d %v", code, body)
	}
	calc := body["calculation"].(map[string]any)
	if calc["reference_source"] != "not_applicable" || calc["mets_per_set"].([]any)[0].(float64) != 2.8 || !near(body["calories_burned"].(float64), 4.41) {
		t.Errorf("calc = %v kcal=%v, want not_applicable / 2.8 / 4.41", calc, body["calories_burned"])
	}
}

// เซตเดียวยาวเกิน 10 นาที (work+rest) ถูกปฏิเสธ แม้เวลารวมไม่เกินเพดานเซสชัน
func TestSaveWorkoutResult_PerSetCap_Rejected(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 700, 0, nil), wset(2, 5, 80, 10, 0, nil)))
	if code != http.StatusBadRequest {
		t.Fatalf("got %d %v, want 400", code, body)
	}
	if n := f.countRows("weight_training_result"); n != 0 {
		t.Errorf("rows = %d, want 0", n)
	}
}

// เพดานเวลาสะสมต่อท่าต่อวัน 2 ชม. (7200 วิ): ของเดิมวันนี้ 7100 → ขอเพิ่ม 110 ไม่ผ่าน · ขอเพิ่ม 100 ผ่าน
func TestSaveWorkoutResult_DailyCap(t *testing.T) {
	f := newFixture(t, 70)
	f.insertTodayWeightSeconds(t, f.barbellID, 7100)
	code, body := f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 60, 50, nil))) // 110 → 7210
	if code != http.StatusBadRequest || !strings.Contains(errText(body), "วันนี้") {
		t.Fatalf("got %d %v, want 400 เพดานรายวัน", code, body)
	}
	code, body = f.post("/workout-results", f.weightReq(f.barbellID, wset(1, 5, 80, 60, 40, nil))) // 100 → 7200 พอดี
	if code != http.StatusOK {
		t.Fatalf("got %d %v, want 200", code, body)
	}
}

// ส่งคำขอเหมือนเดิมซ้ำ → ตอบ duplicate และไม่เพิ่มแถว/พลังงาน
func TestSaveWorkoutResult_Duplicate_NotDoubleCounted(t *testing.T) {
	f := newFixture(t, 70)
	req := f.weightReq(f.barbellID, wset(1, 5, 80, 40, 80, ptr(true)))
	if code, body := f.post("/workout-results", req); code != http.StatusOK {
		t.Fatalf("first: %d %v", code, body)
	}
	before := f.sumCalories("weight_training_result", "wtrs_calories")
	code, body := f.post("/workout-results", req)
	if code != http.StatusOK || body["duplicate"] != true {
		t.Fatalf("second: %d %v, want 200 duplicate", code, body)
	}
	if n := f.countRows("weight_training_result"); n != 1 || !near(f.sumCalories("weight_training_result", "wtrs_calories"), before) {
		t.Errorf("rows=%d kcal=%v (before %v) — ต้องไม่นับซ้ำ", n, f.sumCalories("weight_training_result", "wtrs_calories"), before)
	}
}

// ── คาร์ดิโอ ──

func (f *fixture) cardioReq(date string, seconds int) map[string]any {
	return map[string]any{"date": date, "cdo_id": f.cardioID, "cdors_duration": seconds, "cdors_distance": 5.0}
}

func TestSaveCardioResult_NoBodyStats_Rejected(t *testing.T) {
	f := newFixture(t, 0)
	code, body := f.post("/cardio-results", f.cardioReq(today(), 1800))
	if code != http.StatusBadRequest || !strings.Contains(errText(body), "น้ำหนักตัว") {
		t.Fatalf("got %d %v, want 400 เรื่องน้ำหนักตัว", code, body)
	}
	if n := f.countRows("cardio_result"); n != 0 {
		t.Errorf("rows = %d, want 0", n)
	}
}

// (8−1)×3.5×70/200×30 นาที = 257.25
func TestSaveCardioResult_Happy_Calories(t *testing.T) {
	f := newFixture(t, 70)
	code, body := f.post("/cardio-results", f.cardioReq(today(), 1800))
	if code != http.StatusCreated {
		t.Fatalf("got %d %v", code, body)
	}
	if got := body["calories_burned"].(float64); !near(got, 257.25) {
		t.Errorf("calories_burned = %v, want 257.25", got)
	}
	if got := f.sumCalories("cardio_result", "cdors_calories"); !near(got, 257.25) {
		t.Errorf("DB = %v, want 257.25", got)
	}
}

func TestSaveCardioResult_DateWindow(t *testing.T) {
	f := newFixture(t, 70)
	now := time.Now()
	cases := []struct {
		name string
		date string
		want int
	}{
		{"เมื่อวาน (ข้ามเที่ยงคืน)", now.AddDate(0, 0, -1).Format("2006-01-02"), http.StatusCreated},
		{"ย้อนหลัง 2 วัน", now.AddDate(0, 0, -2).Format("2006-01-02"), http.StatusBadRequest},
		{"พรุ่งนี้", now.AddDate(0, 0, 1).Format("2006-01-02"), http.StatusBadRequest},
		{"รูปแบบผิด", "02/10/2026", http.StatusBadRequest},
	}
	for _, tc := range cases {
		if code, body := f.post("/cardio-results", f.cardioReq(tc.date, 600)); code != tc.want {
			t.Errorf("%s: got %d %v, want %d", tc.name, code, body, tc.want)
		}
	}
	if n := f.countRows("cardio_result"); n != 1 {
		t.Errorf("rows = %d, want 1 (เฉพาะเมื่อวาน)", n)
	}
}

func TestSaveCardioResult_SessionCap(t *testing.T) {
	f := newFixture(t, 70)
	if code, _ := f.post("/cardio-results", f.cardioReq(today(), 21601)); code != http.StatusBadRequest {
		t.Errorf("21601 วิ: got %d, want 400", code)
	}
	if code, body := f.post("/cardio-results", f.cardioReq(today(), 21600)); code != http.StatusCreated {
		t.Errorf("21600 วิ: got %d %v, want 201", code, body)
	}
}

// เพดานสะสมต่อวัน 8 ชม. (28800 วิ) รวมทุกกิจกรรม
func TestSaveCardioResult_DailyCap(t *testing.T) {
	f := newFixture(t, 70)
	if err := f.db.Exec("INSERT INTO cardio_result (cdors_date, cdors_duration, cdors_calories, mb_id, cdo_id) VALUES (CURDATE(), 20000, 100, ?, ?), (CURDATE(), 8000, 100, ?, ?)", f.memberID, f.cardioID, f.memberID, f.cardioID).Error; err != nil {
		t.Fatal(err)
	}
	if code, body := f.post("/cardio-results", f.cardioReq(today(), 900)); code != http.StatusBadRequest || !strings.Contains(errText(body), "วันนี้") {
		t.Fatalf("900 วิ (รวม 28900): got %d %v, want 400", code, body)
	}
	if code, body := f.post("/cardio-results", f.cardioReq(today(), 800)); code != http.StatusCreated {
		t.Fatalf("800 วิ (รวม 28800): got %d %v, want 201", code, body)
	}
}

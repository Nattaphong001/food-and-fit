package helpers

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"gorm.io/gorm"
)

// ครอบคลุมทั้ง 5 ค่ามาตรฐานที่ต้องผ่าน + ค่ากลางๆ ที่ต้อง reject (D9)
func TestValidateActivityLevel(t *testing.T) {
	cases := []struct {
		name  string
		level float64
		want  bool
	}{
		{"sedentary 1.2", 1.2, true},
		{"light 1.375", 1.375, true},
		{"moderate 1.55", 1.55, true},
		{"active 1.725", 1.725, true},
		{"very active 1.9", 1.9, true},
		{"epsilon tolerance 1.3750001", 1.3750001, true},
		{"mid value 1.6 rejected", 1.6, false},
		{"mid value 1.3 rejected", 1.3, false},
		{"below range 1.0 rejected", 1.0, false},
		{"above range 2.0 rejected", 2.0, false},
		{"zero rejected", 0, false},
		{"negative rejected", -1.2, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateActivityLevel(tc.level)
			if ok != tc.want {
				t.Errorf("ValidateActivityLevel(%v) = (%v, %q), want ok=%v", tc.level, ok, msg, tc.want)
			}
			if !tc.want && msg == "" {
				t.Errorf("ValidateActivityLevel(%v) rejected without error message", tc.level)
			}
			if tc.want && msg != "" {
				t.Errorf("ValidateActivityLevel(%v) accepted but returned message %q", tc.level, msg)
			}
		})
	}
}

// ValidateWeightSession: ขอบของเวลารวม (Σ work + rest)/เวลารายเซต/เซต — ต้อง reject ค่าที่ทำให้ kcal เพี้ยนหรือชน DB
func TestValidateWeightSession(t *testing.T) {
	rest := func(v int) *int { return &v }
	sets := func(n, reps, work int, restSec *int) []WeightSetCheck {
		out := make([]WeightSetCheck, n)
		for i := range out {
			out[i] = WeightSetCheck{Reps: reps, WeightKg: 40, WorkSeconds: work, RestSeconds: restSec}
		}
		return out
	}

	cases := []struct {
		name string
		sets []WeightSetCheck
		want bool
	}{
		{"ปกติ 3 เซต ทำ 60 พัก 120 (รวม 540)", sets(3, 10, 60, rest(120)), true},
		{"ไม่มีเวลาพัก", sets(3, 10, 60, nil), true},
		{"ไม่มีเซต", nil, false},
		{"เซตเกิน 50", sets(51, 10, 60, nil), false},
		{"เซต 50 พอดี", sets(50, 10, 60, nil), true},
		{"เวลาสั้นกว่า 5 วิ/เซต (3 เซต 12 วิ)", sets(3, 10, 4, nil), false},
		{"เวลา 5 วิ/เซตพอดี (3 เซต 15 วิ)", sets(3, 10, 5, nil), true},
		{"เวลาทำเซต 0", sets(1, 10, 0, nil), false},
		{"เวลาทำเซตติดลบ", sets(1, 10, -60, nil), false},
		{"เวลารวม 7200 วิ พอดี (12 เซต ทำ 480 พัก 120)", sets(12, 10, 480, rest(120)), true},
		{"เวลารวม 7212 วิ", sets(12, 10, 481, rest(120)), false},
		{"เวลารวม 600 วิ/เซตพอดี (3 เซต)", sets(3, 10, 600, nil), true},
		{"เวลารวมยาวผิดปกติเทียบจำนวนเซต (3 เซต 610 วิ/เซต)", sets(3, 10, 610, nil), false},
		{"พักติดลบ", sets(3, 10, 60, rest(-1)), false},
		{"Reps 0", sets(3, 0, 60, nil), false},
		{"Reps 999", sets(3, 999, 60, nil), true},
		{"Reps 1000", sets(3, 1000, 60, nil), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateWeightSession(tc.sets, true, true)
			if ok != tc.want {
				t.Errorf("ValidateWeightSession(%s) = (%v, %q), want ok=%v", tc.name, ok, msg, tc.want)
			}
			if !ok && msg == "" {
				t.Errorf("ต้องมีข้อความบอกเหตุผลเมื่อ reject")
			}
		})
	}

	t.Run("WeightSessionTotalSeconds รวม work + rest (nil นับ 0)", func(t *testing.T) {
		got := WeightSessionTotalSeconds([]WeightSetCheck{
			{WorkSeconds: 50, RestSeconds: rest(60)}, {WorkSeconds: 40, RestSeconds: rest(70)}, {WorkSeconds: 30},
		})
		if got != 250 {
			t.Errorf("got %d, want 250", got)
		}
	})

	t.Run("น้ำหนักที่ยก", func(t *testing.T) {
		for _, tc := range []struct {
			kg   float64
			want bool
		}{{0, true}, {999.99, true}, {1000, false}, {-1, false}} {
			ok, _ := ValidateWeightSession([]WeightSetCheck{{Reps: 10, WeightKg: tc.kg, WorkSeconds: 60}}, true, true)
			if ok != tc.want {
				t.Errorf("weight %.2f → ok=%v, want %v", tc.kg, ok, tc.want)
			}
		}
	})

	t.Run("ท่าบอดี้เวทนับครั้งได้ (Pull-up ฯลฯ: hasWeight=false, hasReps=true)", func(t *testing.T) {
		for _, tc := range []struct {
			name string
			set  WeightSetCheck
			want bool
		}{
			{"ไม่มีน้ำหนัก มีจำนวนครั้ง", WeightSetCheck{Reps: 10, WeightKg: 0, WorkSeconds: 60}, true},
			{"ส่งน้ำหนักมา", WeightSetCheck{Reps: 10, WeightKg: 10, WorkSeconds: 60}, false},
			{"Reps 0", WeightSetCheck{Reps: 0, WeightKg: 0, WorkSeconds: 60}, false},
		} {
			ok, _ := ValidateWeightSession([]WeightSetCheck{tc.set, tc.set, tc.set}, false, true)
			if ok != tc.want {
				t.Errorf("%s → ok=%v, want %v", tc.name, ok, tc.want)
			}
		}
	})

	t.Run("ท่าค้างเวลา (Plank: hasWeight=false, hasReps=false)", func(t *testing.T) {
		for _, tc := range []struct {
			name string
			set  WeightSetCheck
			want bool
		}{
			{"ไม่มีน้ำหนักและจำนวนครั้ง", WeightSetCheck{Reps: 0, WeightKg: 0, WorkSeconds: 60}, true},
			{"ส่งจำนวนครั้งมา", WeightSetCheck{Reps: 10, WeightKg: 0, WorkSeconds: 60}, false},
			{"ส่งน้ำหนักมา", WeightSetCheck{Reps: 0, WeightKg: 10, WorkSeconds: 60}, false},
		} {
			ok, _ := ValidateWeightSession([]WeightSetCheck{tc.set, tc.set, tc.set}, false, false)
			if ok != tc.want {
				t.Errorf("%s → ok=%v, want %v", tc.name, ok, tc.want)
			}
		}
	})
}

// ValidateCardioResult: ขอบของเวลา (60-21600 วิ) และระยะทาง (0-999.99 กม. เฉพาะกิจกรรมที่มีระยะทาง)
func TestValidateCardioResult(t *testing.T) {
	cases := []struct {
		name        string
		duration    int
		distance    float64
		hasDistance bool
		want        bool
	}{
		{"ปกติ 30 นาที มีระยะทาง", 1800, 5.0, true, true},
		{"ปกติ 30 นาที ไม่มีระยะทาง (เช่น เวทบอลออกกำลัง)", 1800, 0, false, true},
		{"เวลาต่ำกว่า 60 วิ", 59, 0, false, false},
		{"เวลา 60 วิพอดี (ขั้นต่ำ)", 60, 0, false, true},
		{"เวลา 21600 วิพอดี (เพดาน 6 ชม.)", 21600, 0, false, true},
		{"เวลา 21601 วิ", 21601, 0, false, false},
		{"เวลาเกินเพดาน 36001 วิ", 36001, 0, false, false},
		{"เวลา 0", 0, 0, false, false},
		{"เวลาติดลบ", -60, 0, false, false},
		{"ระยะทางติดลบ (มีระยะทาง)", 1800, -1, true, false},
		{"ระยะทาง 0 พอดี (มีระยะทาง — วิ่งอยู่กับที่)", 1800, 0, true, true},
		{"ระยะทาง 999.99 พอดี (เพดานคอลัมน์ DECIMAL(5,2))", 1800, 999.99, true, true},
		{"ระยะทางเกินเพดาน 1000", 1800, 1000, true, false},
		{"ระยะทางติดลบแต่ hasDistance=false ไม่ตรวจ (ไม่มีผลต่อ DB)", 1800, -1, false, true},
		{"ระยะทางเกินเพดานแต่ hasDistance=false ไม่ตรวจ", 1800, 5000, false, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateCardioResult(tc.duration, tc.distance, tc.hasDistance)
			if ok != tc.want {
				t.Errorf("ValidateCardioResult(%d, %.2f, %v) = (%v, %q), want ok=%v", tc.duration, tc.distance, tc.hasDistance, ok, msg, tc.want)
			}
			if !ok && msg == "" {
				t.Errorf("ต้องมีข้อความบอกเหตุผลเมื่อ reject")
			}
		})
	}
}

// wtrs_active_seconds (WorkSeconds) ถูกตัดออกจาก WeightSetCheck แล้ว (2026-09-29, DROP column DB
// จริง) — ไม่เคยเข้าสูตรคำนวณพลังงานเลยตั้งแต่ Two-Compartment Energy Model ถูกยกเลิก (2026-09-22)
// ทดสอบ TestValidateWeightSession_WorkSeconds เดิมถูกลบไปพร้อมกัน (ดู git history ถ้าต้องการดูของเดิม)

// เพดานเวลา "ต่อเซต" ต้องเป็นต่อเซตจริง ไม่ใช่ค่าเฉลี่ย — เซตเดียวยาวผิดปกติต้องถูก reject แม้เซตอื่นสั้น
func TestValidateWeightSession_PerSetCapIsPerSet(t *testing.T) {
	build := func(longSetSeconds int) []WeightSetCheck {
		sets := make([]WeightSetCheck, 0, 50)
		for i := 0; i < 49; i++ {
			sets = append(sets, WeightSetCheck{Reps: 5, WeightKg: 50, WorkSeconds: WeightSessionMinSecondsPerSet})
		}
		return append(sets, WeightSetCheck{Reps: 5, WeightKg: 50, WorkSeconds: longSetSeconds})
	}
	if ok, _ := ValidateWeightSession(build(WeightSessionMaxSecondsPerSet), true, true); !ok {
		t.Error("เซตยาว 600 วิพอดี ต้องผ่าน")
	}
	if ok, msg := ValidateWeightSession(build(WeightSessionMaxSecondsPerSet+1), true, true); ok || msg == "" {
		t.Errorf("เซตยาว 601 วิ ต้อง reject พร้อมข้อความ (ok=%v msg=%q)", ok, msg)
	}
	// work + rest ของเซตเดียวรวมกันเกินเพดาน
	rest := 300
	if ok, _ := ValidateWeightSession([]WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: 400, RestSeconds: &rest}}, true, true); ok {
		t.Error("work 400 + rest 300 = 700 วิ ต้อง reject")
	}
}

// เพดานเวลาสะสมต่อท่าต่อวัน กันส่งซ้ำ/แบ่งส่งหลายคำขอ
func TestValidateDailyWeightSeconds(t *testing.T) {
	cases := []struct {
		name          string
		existing, new int
		want          bool
	}{
		{"วันแรก ไม่มีของเดิม", 0, 1800, true},
		{"รวมเท่าเพดานพอดี", 3600, 3600, true},
		{"รวมเกินเพดาน 1 วิ", 3600, 3601, false},
		{"ส่งซ้ำจนสะสมเกิน", 7000, 300, false},
		{"มีของเดิมเต็มเพดานแล้ว", WeightSessionMaxSeconds, 1, false},
	}
	for _, tc := range cases {
		ok, msg := ValidateDailyWeightSeconds(tc.existing, tc.new)
		if ok != tc.want || (!ok && msg == "") {
			t.Errorf("%s: got (%v, %q), want ok=%v", tc.name, ok, msg, tc.want)
		}
	}
}

// ResolveBodyWeight: ห้ามมี fallback — ไม่มีข้อมูล/น้ำหนักผิด/DB error ต้องได้ error ไม่ใช่ค่าเดา
func TestResolveBodyWeight(t *testing.T) {
	cases := []struct {
		name       string
		weight     float64
		err        error
		wantWeight float64
		wantStatus int
	}{
		{"มีข้อมูล", 72.5, nil, 72.5, 0},
		{"ไม่มีแถวน้ำหนักตัว", 0, gorm.ErrRecordNotFound, 0, http.StatusBadRequest},
		{"DB error อื่น", 0, errors.New("connection refused"), 0, http.StatusInternalServerError},
		{"DB error แต่ได้ค่าค้าง", 80, errors.New("timeout"), 0, http.StatusInternalServerError},
		{"น้ำหนัก 0", 0, nil, 0, http.StatusBadRequest},
		{"น้ำหนักติดลบ", -5, nil, 0, http.StatusBadRequest},
	}
	for _, tc := range cases {
		w, status, msg := ResolveBodyWeight(tc.weight, tc.err)
		if w != tc.wantWeight || status != tc.wantStatus {
			t.Errorf("%s: got (%v, %d), want (%v, %d)", tc.name, w, status, tc.wantWeight, tc.wantStatus)
		}
		if (status != 0) != (msg != "") {
			t.Errorf("%s: msg = %q ไม่สอดคล้องกับ status %d", tc.name, msg, status)
		}
	}
}

// เพดานสะสมต่อวันต้องไม่ต่ำกว่าเพดานต่อเซสชัน และเพดานต่อเซตต้องไม่เกินเพดานต่อเซสชัน (กันตั้งค่าขัดกันเอง)
func TestWeightCaps_Consistent(t *testing.T) {
	if WeightDailyMaxSecondsPerExercise < WeightSessionMaxSeconds {
		t.Errorf("daily cap %d < session cap %d", WeightDailyMaxSecondsPerExercise, WeightSessionMaxSeconds)
	}
	if WeightSessionMaxSecondsPerSet > WeightSessionMaxSeconds {
		t.Errorf("per-set cap %d > session cap %d", WeightSessionMaxSecondsPerSet, WeightSessionMaxSeconds)
	}
	// เซสชันเต็มเพดานในวันแรกต้องบันทึกได้
	if ok, _ := ValidateDailyWeightSeconds(0, WeightSessionMaxSeconds); !ok {
		t.Error("เซสชันเต็มเพดานในวันที่ไม่มีของเดิมต้องผ่าน")
	}
}

func TestValidateDailyCardioSeconds(t *testing.T) {
	cases := []struct {
		name          string
		existing, new int
		want          bool
	}{
		{"วันแรก", 0, 3600, true},
		{"วิ่งเช้า + ปั่นเย็น", 5400, 7200, true},
		{"รวมเท่าเพดานพอดี", 14400, 14400, true},
		{"เกินเพดาน 1 วิ", 14400, 14401, false},
		{"ส่งซ้ำจนสะสมเกิน", 28000, 900, false},
	}
	for _, tc := range cases {
		ok, msg := ValidateDailyCardioSeconds(tc.existing, tc.new)
		if ok != tc.want || (!ok && msg == "") {
			t.Errorf("%s: got (%v, %q), want ok=%v", tc.name, ok, msg, tc.want)
		}
	}
}

func TestCardioCaps_Consistent(t *testing.T) {
	if CardioMaxSecondsPerDay < CardioMaxSecondsPerSession {
		t.Errorf("daily cap %d < session cap %d", CardioMaxSecondsPerDay, CardioMaxSecondsPerSession)
	}
	if ok, _ := ValidateDailyCardioSeconds(0, CardioMaxSecondsPerSession); !ok {
		t.Error("ครั้งเดียวเต็มเพดานในวันแรกต้องผ่าน")
	}
}

func TestValidateCardioDate(t *testing.T) {
	now := time.Date(2026, 10, 2, 15, 30, 0, 0, time.Local)
	cases := []struct {
		name string
		date string
		want bool
	}{
		{"วันนี้", "2026-10-02", true},
		{"เมื่อวาน (ข้ามเที่ยงคืน)", "2026-10-01", true},
		{"ย้อนหลัง 2 วัน (ไม่มีบันทึกย้อนหลัง)", "2026-09-30", false},
		{"พรุ่งนี้", "2026-10-03", false},
		{"อนาคตไกล", "2030-01-01", false},
		{"รูปแบบผิด", "02/10/2026", false},
		{"มีเวลาปน", "2026-10-02T10:00:00", false},
		{"ว่าง", "", false},
		{"วันที่ไม่มีจริง", "2026-02-30", false},
	}
	for _, tc := range cases {
		ok, msg := ValidateCardioDate(tc.date, now)
		if ok != tc.want || (!ok && msg == "") {
			t.Errorf("%s: got (%v, %q), want ok=%v", tc.name, ok, msg, tc.want)
		}
	}
}

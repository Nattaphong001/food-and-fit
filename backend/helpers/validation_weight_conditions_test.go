package helpers

// ทดสอบ ValidateWeightSession ครบทุกขอบ/ทุกชนิดท่า + ช่องโหว่ที่ตรวจพบ 2026-10-04 (เสริม validation_test.go)
// ชื่อขึ้นต้น TestVuln_ = ล็อกพฤติกรรมปัจจุบันที่ผิด ถ้าแก้แล้ว test จะล้ม → กลับ assertion

import (
	"math"
	"testing"
)

func restPtr(v int) *int { return &v }

// ขอบทีละค่า (ท่าอุปกรณ์: hasWeight=true hasReps=true) — ขอบล่าง/บน และค่าเลยขอบ 1 หน่วย
func TestValidateWeightSession_Boundaries(t *testing.T) {
	one := func(reps int, kg float64, work int, rest *int) []WeightSetCheck {
		return []WeightSetCheck{{Reps: reps, WeightKg: kg, WorkSeconds: work, RestSeconds: rest}}
	}
	n := func(count, work int) []WeightSetCheck {
		out := make([]WeightSetCheck, count)
		for i := range out {
			out[i] = WeightSetCheck{Reps: 5, WeightKg: 50, WorkSeconds: work}
		}
		return out
	}
	cases := []struct {
		name string
		sets []WeightSetCheck
		want bool
	}{
		{"reps 1", one(1, 50, 60, nil), true},
		{"reps 0", one(0, 50, 60, nil), false},
		{"reps 999", one(999, 50, 60, nil), true},
		{"reps 1000", one(1000, 50, 60, nil), false},
		{"น้ำหนัก 0 (ท่าอุปกรณ์ไม่บล็อก)", one(5, 0, 60, nil), true},
		{"น้ำหนัก 0.01", one(5, 0.01, 60, nil), true},
		{"น้ำหนัก 999.99", one(5, 999.99, 60, nil), true},
		{"น้ำหนัก 1000", one(5, 1000, 60, nil), false},
		{"น้ำหนัก -0.01", one(5, -0.01, 60, nil), false},
		{"+Inf", one(5, math.Inf(1), 60, nil), false},
		{"-Inf", one(5, math.Inf(-1), 60, nil), false},
		{"เซตเดียว 5 วิพอดี", one(5, 50, 5, nil), true},
		{"เซตเดียว 4 วิ", one(5, 50, 4, nil), false},
		{"ทำ 600 พัก 0", one(5, 50, 600, restPtr(0)), true},
		{"ทำ 1 พัก 599 (รวม 600)", one(5, 50, 1, restPtr(599)), true},
		{"ทำ 1 พัก 600 (รวม 601)", one(5, 50, 1, restPtr(600)), false},
		{"ทำ 601 ไม่มีพัก", one(5, 50, 601, nil), false},
		{"พัก 0 วิ", one(5, 50, 60, restPtr(0)), true},
		{"พัก -1", one(5, 50, 60, restPtr(-1)), false},
		{"50 เซต", n(50, 60), true},
		{"51 เซต", n(51, 5), false},
		{"รวม 7200 วิพอดี (12 เซต × 600)", n(12, 600), true},
		{"รวม 7201 วิ (11 เซต × 600 + 601)", append(n(11, 600), WeightSetCheck{Reps: 5, WeightKg: 50, WorkSeconds: 601}), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateWeightSession(tc.sets, true, true)
			if ok != tc.want {
				t.Errorf("got (%v, %q), want ok=%v", ok, msg, tc.want)
			}
			if !ok && msg == "" {
				t.Errorf("ต้องมีข้อความเหตุผล")
			}
		})
	}
}

// ครบ 4 ชนิดท่า (hasWeight × hasReps) × ส่ง/ไม่ส่ง น้ำหนัก และ reps — กติกา 2 ข้อไม่ทับซ้อน
func TestValidateWeightSession_ExerciseTypeMatrix(t *testing.T) {
	for _, hw := range []bool{false, true} {
		for _, hr := range []bool{false, true} {
			for _, reps := range []int{0, 5} {
				for _, kg := range []float64{0, 20} {
					set := []WeightSetCheck{{Reps: reps, WeightKg: kg, WorkSeconds: 60}}
					want := (hr == (reps != 0)) && (hw || kg == 0)
					if ok, _ := ValidateWeightSession(set, hw, hr); ok != want {
						t.Errorf("hasWeight=%v hasReps=%v reps=%d kg=%v: ok=%v want %v", hw, hr, reps, kg, ok, want)
					}
				}
			}
		}
	}
}

// ลำดับตรวจ: เซตว่างต้องไม่ panic (ตรวจก่อนวนเซต) และเซตแรกผิดต้องปฏิเสธแม้เซตหลังถูก
func TestValidateWeightSession_EmptyAndMixed(t *testing.T) {
	if ok, _ := ValidateWeightSession(nil, true, true); ok {
		t.Errorf("เซตว่างต้องไม่ผ่าน")
	}
	if ok, _ := ValidateWeightSession([]WeightSetCheck{}, false, false); ok {
		t.Errorf("เซตว่างต้องไม่ผ่าน (ท่าค้างเวลา)")
	}
	mixed := []WeightSetCheck{{Reps: 0, WeightKg: 50, WorkSeconds: 60}, {Reps: 5, WeightKg: 50, WorkSeconds: 60}}
	if ok, _ := ValidateWeightSession(mixed, true, true); ok {
		t.Errorf("เซตแรกผิด (reps 0) ต้องปฏิเสธทั้งคำขอ")
	}
}

// แก้แล้ว 2026-10-04 (เดิมช่องโหว่ V1): int64 overflow — เดิมเพดานต่อเซตและเวลารวมคำนวณจาก work + rest ตรงๆ rest = MaxInt64
// ทำให้ผลบวกวนเป็นลบ หลุดทั้ง "≤ 600 วิ/เซต" และเวลารวม ตอนนี้ตรวจเพดานรายฟิลด์ก่อนบวก
func TestValidateWeightSession_IntOverflowRejected(t *testing.T) {
	mx := math.MaxInt64
	t.Run("rest = MaxInt64 สองเซต + เซตปกติ 600 วิ (เวลารวมยังวนกลับเป็น 600 แต่ต้องถูกปฏิเสธเพราะรายฟิลด์)", func(t *testing.T) {
		sets := []WeightSetCheck{
			{Reps: 5, WeightKg: 50, WorkSeconds: 1, RestSeconds: &mx},
			{Reps: 5, WeightKg: 50, WorkSeconds: 1, RestSeconds: &mx},
			{Reps: 5, WeightKg: 50, WorkSeconds: 600},
		}
		if got := WeightSessionTotalSeconds(sets); got != 600 {
			t.Errorf("เวลารวม = %d, คาดว่าวนกลับเป็น 600 (ฟังก์ชันรวมเวลาไม่เปลี่ยน)", got)
		}
		if ok, _ := ValidateWeightSession(sets, true, true); ok {
			t.Errorf("ต้องถูกปฏิเสธ")
		}
	})
	t.Run("work = MaxInt64 + rest 1", func(t *testing.T) {
		sets := []WeightSetCheck{
			{Reps: 5, WeightKg: 50, WorkSeconds: mx, RestSeconds: restPtr(1)},
			{Reps: 5, WeightKg: 50, WorkSeconds: mx, RestSeconds: restPtr(1)},
			{Reps: 5, WeightKg: 50, WorkSeconds: 600},
		}
		if ok, _ := ValidateWeightSession(sets, true, true); ok {
			t.Errorf("ต้องถูกปฏิเสธ")
		}
	})
	t.Run("ค่าติดลบมหาศาล", func(t *testing.T) {
		sets := []WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: math.MinInt64}, {Reps: 5, WeightKg: 50, WorkSeconds: 600}}
		if ok, _ := ValidateWeightSession(sets, true, true); ok {
			t.Errorf("ต้องถูกปฏิเสธ")
		}
	})
	t.Run("ขอบรายฟิลด์: work 600 / rest 600 ฟิลด์เดียวไม่เกินเพดาน", func(t *testing.T) {
		if ok, _ := ValidateWeightSession([]WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: 600}}, true, true); !ok {
			t.Errorf("work 600 ต้องผ่าน")
		}
		if ok, _ := ValidateWeightSession([]WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: 1, RestSeconds: restPtr(600)}}, true, true); ok {
			t.Errorf("work 1 + rest 600 = 601 ต้องไม่ผ่าน")
		}
	})
}

// แก้แล้ว 2026-10-04 (เดิม V1b): NaN เคยผ่านเพราะ "< 0" กับ "> เพดาน" เป็นเท็จทั้งคู่
func TestValidateWeightSession_NaNWeightRejected(t *testing.T) {
	sets := []WeightSetCheck{{Reps: 5, WeightKg: math.NaN(), WorkSeconds: 60}}
	if ok, msg := ValidateWeightSession(sets, true, true); ok || msg == "" {
		t.Errorf("NaN ต้องถูกปฏิเสธพร้อมข้อความ (ok=%v msg=%q)", ok, msg)
	}
}

// เพดานจำนวนเซตสะสมต่อท่าต่อวัน = 255 (ให้ wtrs_set_no ไม่ล้น TINYINT UNSIGNED)
func TestValidateDailyWeightSets(t *testing.T) {
	for _, tc := range []struct {
		existing, add int
		want          bool
	}{{0, 1, true}, {0, 50, true}, {205, 50, true}, {205, 51, false}, {250, 5, true}, {250, 6, false}, {255, 1, false}, {255, 0, true}} {
		if ok, msg := ValidateDailyWeightSets(tc.existing, tc.add); ok != tc.want || (!ok && msg == "") {
			t.Errorf("existing=%d add=%d: got (%v, %q), want %v", tc.existing, tc.add, ok, msg, tc.want)
		}
	}
	if WeightDailyMaxSetsPerExercise != 255 {
		t.Errorf("เพดานต้องตรง TINYINT UNSIGNED = 255")
	}
}

// ผู้ใช้แก้คำตอบ near_failure แล้วบันทึกใหม่ต้องได้คีย์ใหม่ (เดิมช่องโหว่ V5: ได้ผลเดิม duplicate)
func TestWeightSessionFingerprint_IncludesNearFailure(t *testing.T) {
	yes, no := true, false
	mk := func(nf *bool) string {
		return WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 80, WorkSeconds: 40, NearFailure: nf}})
	}
	if mk(nil) == mk(&yes) || mk(nil) == mk(&no) || mk(&yes) == mk(&no) {
		t.Errorf("nil/true/false ต้องได้คีย์ต่างกันทั้ง 3 แบบ")
	}
	if mk(&yes) != mk(&yes) {
		t.Errorf("ค่าเดียวกันต้องได้คีย์เดียวกัน")
	}
}

func TestCardioFingerprint(t *testing.T) {
	base := CardioFingerprint(1, 2, "2026-10-04", 1800, 5)
	if base != CardioFingerprint(1, 2, "2026-10-04", 1800, 5) {
		t.Errorf("ข้อมูลเดียวกันต้องได้คีย์เดียวกัน")
	}
	if base != CardioFingerprint(1, 2, "2026-10-04", 1800, 5.001) {
		t.Errorf("ระยะทางต่างต่ำกว่า 0.005 กม. ควรถือเป็นคำขอเดียวกัน (ปัด 2 ตำแหน่ง)")
	}
	for name, other := range map[string]string{
		"สมาชิกต่าง":  CardioFingerprint(2, 2, "2026-10-04", 1800, 5),
		"กิจกรรมต่าง": CardioFingerprint(1, 3, "2026-10-04", 1800, 5),
		"วันที่ต่าง":  CardioFingerprint(1, 2, "2026-10-03", 1800, 5),
		"เวลาต่าง":    CardioFingerprint(1, 2, "2026-10-04", 1801, 5),
		"ระยะทางต่าง": CardioFingerprint(1, 2, "2026-10-04", 1800, 5.01),
	} {
		if other == base {
			t.Errorf("%s ต้องได้คีย์ต่างกัน", name)
		}
	}
	// คีย์คาร์ดิโอต้องไม่ชนกับคีย์เวทแม้ตัวเลขชุดเดียวกัน (คนละ store แต่กันไว้เผื่อแชร์)
	if base == WeightSessionFingerprint(1, 2, nil) {
		t.Errorf("คีย์คาร์ดิโอกับเวทต้องไม่ชนกัน")
	}
}

// fingerprint ปัดน้ำหนัก 2 ตำแหน่ง: 80.001 กับ 80.004 ถือเป็นคำขอเดียวกัน (กันซ้ำได้ตามต้องการ) แต่ near_failure ไม่อยู่ในคีย์
// (ดู controllers.TestVuln_FingerprintIgnoresNearFailure) — ที่นี่ล็อกว่าคีย์ไม่ขึ้นกับฟิลด์ที่ไม่ได้ส่งเข้ามา
func TestWeightSessionFingerprint_RoundsWeightTo2Decimals(t *testing.T) {
	a := WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 80.001, WorkSeconds: 40}})
	b := WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 80.004, WorkSeconds: 40}})
	c := WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 80.01, WorkSeconds: 40}})
	if a != b {
		t.Errorf("80.001 กับ 80.004 ควรได้คีย์เดียวกัน")
	}
	if a == c {
		t.Errorf("80.001 กับ 80.01 ต้องได้คีย์ต่างกัน")
	}
}

// เวลาพัก nil กับ 0 ต้องได้คีย์ต่างกัน (nil = ไม่เคยพัก, 0 = พัก 0 วิ) และลำดับเซตมีผล
func TestWeightSessionFingerprint_NilVsZeroRestAndOrder(t *testing.T) {
	nilRest := WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: 40}})
	zeroRest := WeightSessionFingerprint(1, 5, []WeightSetCheck{{Reps: 5, WeightKg: 50, WorkSeconds: 40, RestSeconds: restPtr(0)}})
	if nilRest == zeroRest {
		t.Errorf("nil กับ 0 ต้องต่างกัน")
	}
	s1, s2 := WeightSetCheck{Reps: 5, WeightKg: 50, WorkSeconds: 40}, WeightSetCheck{Reps: 6, WeightKg: 50, WorkSeconds: 40}
	if WeightSessionFingerprint(1, 5, []WeightSetCheck{s1, s2}) == WeightSessionFingerprint(1, 5, []WeightSetCheck{s2, s1}) {
		t.Errorf("ลำดับเซตต่างกันต้องได้คีย์ต่างกัน")
	}
}

// พลังงานต่อแถวต้องไม่เกินที่ DECIMAL(6,2) เก็บได้ — ขอบ 9999.99 และค่าผิดปกติ
func TestValidateCaloriesFitColumn(t *testing.T) {
	for _, tc := range []struct {
		kcal float64
		want bool
	}{{0, true}, {123.45, true}, {9999.99, true}, {10000, false}, {21358, false}, {-0.01, false}, {math.NaN(), false}, {math.Inf(1), false}} {
		if ok, msg := ValidateCaloriesFitColumn(tc.kcal); ok != tc.want || (!ok && msg == "") {
			t.Errorf("kcal=%v: got (%v, %q), want %v", tc.kcal, ok, msg, tc.want)
		}
	}
}

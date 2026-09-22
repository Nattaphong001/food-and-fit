package helpers

import "testing"

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

// ValidateWeightSession: ขอบของเวลารวม/เวลาพัก/เซต — ต้อง reject ค่าที่ทำให้ kcal เพี้ยนหรือชน DB
func TestValidateWeightSession(t *testing.T) {
	rest := func(v int) *int { return &v }
	sets := func(n, reps int, restSec *int) []WeightSetCheck {
		out := make([]WeightSetCheck, n)
		for i := range out {
			out[i] = WeightSetCheck{Reps: reps, WeightKg: 40, RestSeconds: restSec}
		}
		return out
	}

	cases := []struct {
		name     string
		duration int
		sets     []WeightSetCheck
		want     bool
	}{
		{"ปกติ 3 เซต 9 นาที พัก 120", 540, sets(3, 10, rest(120)), true},
		{"ไม่มีเวลาพัก (client เก่า)", 540, sets(3, 10, nil), true},
		{"ไม่มีเซต", 540, nil, false},
		{"เซตเกิน 50", 7200, sets(51, 10, nil), false},
		{"เซต 50 พอดี", 7200, sets(50, 10, nil), true},
		{"เวลาสั้นกว่า 5 วิ/เซต (3 เซต 14 วิ)", 14, sets(3, 10, nil), false},
		{"เวลา 5 วิ/เซตพอดี (3 เซต 15 วิ)", 15, sets(3, 10, nil), true},
		{"เวลา 0", 0, sets(1, 10, nil), false},
		{"เวลาติดลบ", -60, sets(1, 10, nil), false},
		{"เวลารวม 7200 วิ พอดี (2 ชม.)", 7200, sets(3, 10, rest(120)), true},
		{"เวลารวม 7201 วิ", 7201, sets(3, 10, rest(120)), false},
		{"เวลารวมเกินคอลัมน์ SMALLINT", 70000, sets(3, 10, nil), false},
		{"พักติดลบ", 540, sets(3, 10, rest(-1)), false},
		{"พักเซตเดียวมากกว่าเวลารวม", 540, sets(1, 10, rest(541)), false},
		{"ผลรวมพักเกินเวลารวมเกินค่าเผื่อ (3×190 = 570 > 540+10)", 540, sets(3, 10, rest(190)), false},
		{"ผลรวมพักเกินเวลารวมแต่อยู่ในค่าเผื่อ (3×183 = 549 ≤ 550)", 540, sets(3, 10, rest(183)), true},
		{"Reps 0", 540, sets(3, 0, nil), false},
		{"Reps 999", 540, sets(3, 999, nil), true},
		{"Reps 1000", 540, sets(3, 1000, nil), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateWeightSession(tc.duration, tc.sets)
			if ok != tc.want {
				t.Errorf("ValidateWeightSession(%d, ...) = (%v, %q), want ok=%v", tc.duration, ok, msg, tc.want)
			}
			if !ok && msg == "" {
				t.Errorf("ต้องมีข้อความบอกเหตุผลเมื่อ reject")
			}
		})
	}

	t.Run("น้ำหนักที่ยก", func(t *testing.T) {
		for _, tc := range []struct {
			kg   float64
			want bool
		}{{0, true}, {999.99, true}, {1000, false}, {-1, false}} {
			ok, _ := ValidateWeightSession(540, []WeightSetCheck{{Reps: 10, WeightKg: tc.kg}})
			if ok != tc.want {
				t.Errorf("weight %.2f → ok=%v, want %v", tc.kg, ok, tc.want)
			}
		}
	})
}

// WorkSeconds (wtrs_active_seconds, เพิ่มกลับมา 2026-09-20) ใช้กฎขอบเขตเดียวกับ RestSeconds
// และผลรวมของทั้งสองต้องไม่เกินเวลารวมของเซสชัน
func TestValidateWeightSession_WorkSeconds(t *testing.T) {
	work := func(v int) *int { return &v }
	withWork := func(reps int, workSec, restSec *int) WeightSetCheck {
		return WeightSetCheck{Reps: reps, WeightKg: 40, WorkSeconds: workSec, RestSeconds: restSec}
	}

	cases := []struct {
		name string
		dur  int
		sets []WeightSetCheck
		want bool
	}{
		{"ไม่มี WorkSeconds (client เก่า)", 300, []WeightSetCheck{{Reps: 10, WeightKg: 40}}, true},
		{"WorkSeconds ปกติ", 300, []WeightSetCheck{withWork(10, work(40), nil)}, true},
		{"WorkSeconds ติดลบ", 300, []WeightSetCheck{withWork(10, work(-1), nil)}, false},
		{"WorkSeconds มากกว่าเวลารวม", 300, []WeightSetCheck{withWork(10, work(301), nil)}, false},
		{"WorkSeconds เท่าเวลารวมพอดี", 300, []WeightSetCheck{withWork(10, work(300), nil)}, true},
		{"ผลรวม Work+Rest เกินเวลารวมเกินค่าเผื่อ", 100, []WeightSetCheck{withWork(10, work(60), func() *int { v := 60; return &v }())}, false},
		{"ผลรวม Work+Rest อยู่ในค่าเผื่อ", 110, []WeightSetCheck{withWork(10, work(60), func() *int { v := 40; return &v }())}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateWeightSession(tc.dur, tc.sets)
			if ok != tc.want {
				t.Errorf("ValidateWeightSession(%d, ...) = (%v, %q), want ok=%v", tc.dur, ok, msg, tc.want)
			}
		})
	}
}

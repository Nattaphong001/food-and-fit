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
		{"เวลารวม 7200 วิ พอดี (2 ชม., 12 เซตพอสำหรับเพดานต่อเซต)", 7200, sets(12, 10, rest(120)), true},
		{"เวลารวม 7201 วิ", 7201, sets(12, 10, rest(120)), false},
		{"เวลารวมเกินคอลัมน์ SMALLINT", 70000, sets(3, 10, nil), false},
		{"เวลารวมยาวผิดปกติเทียบจำนวนเซต (3 เซต 610 วิ/เซต)", 1830, sets(3, 10, nil), false},
		{"เวลารวม 600 วิ/เซตพอดี (3 เซต)", 1800, sets(3, 10, nil), true},
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
			ok, msg := ValidateWeightSession(tc.duration, tc.sets, false)
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
			ok, _ := ValidateWeightSession(540, []WeightSetCheck{{Reps: 10, WeightKg: tc.kg}}, false)
			if ok != tc.want {
				t.Errorf("weight %.2f → ok=%v, want %v", tc.kg, ok, tc.want)
			}
		}
	})

	t.Run("ท่าบอดี้เวท", func(t *testing.T) {
		for _, tc := range []struct {
			name string
			set  WeightSetCheck
			want bool
		}{
			{"ไม่มีน้ำหนักและจำนวนครั้ง", WeightSetCheck{Reps: 0, WeightKg: 0}, true},
			{"ส่งจำนวนครั้งมา", WeightSetCheck{Reps: 10, WeightKg: 0}, false},
			{"ส่งน้ำหนักมา", WeightSetCheck{Reps: 0, WeightKg: 10}, false},
		} {
			ok, _ := ValidateWeightSession(540, []WeightSetCheck{tc.set, tc.set, tc.set}, true)
			if ok != tc.want {
				t.Errorf("%s → ok=%v, want %v", tc.name, ok, tc.want)
			}
		}
	})
}

// ValidateCardioResult: ขอบของเวลา (60-36000 วิ) และระยะทาง (0-999.99 กม. เฉพาะกิจกรรมที่มีระยะทาง)
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
		{"เวลา 36000 วิพอดี (เพดาน 600 นาที)", 36000, 0, false, true},
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

package services

import (
	"strings"
	"testing"
	"time"

	"food_and_fit_api/models"
)

// ─────────────────────────────────────────────────────────────────────────
// AgeFromBirthDate (ตัวเดียวที่คำนวณอายุ — CalculateAge เดิมถูกลบแล้ว 2026-09-19)
// ─────────────────────────────────────────────────────────────────────────

func TestAgeFromBirthDate_BirthdayAlreadyPassedThisYear(t *testing.T) {
	// 25 ปีกับอีก 1 วันที่แล้ว — รับประกันว่า "ถึงวันเกิดปีนี้แล้ว" เสมอไม่ว่ารันวันไหน จึงต้องได้ 25 เป๊ะ
	birth := time.Now().AddDate(-25, 0, -1)
	if got := AgeFromBirthDate(birth); got != 25 {
		t.Errorf("AgeFromBirthDate(%s) = %d, want 25", birth.Format("2006-01-02"), got)
	}
}

func TestAgeFromBirthDate_BirthdayNotYetThisYear(t *testing.T) {
	// 25 ปีลบ 1 วัน = พรุ่งนี้ครบ 25 → วันนี้ยังต้องเป็น 24
	birth := time.Now().AddDate(-25, 0, 1)
	if got := AgeFromBirthDate(birth); got != 24 {
		t.Errorf("AgeFromBirthDate(%s) = %d, want 24", birth.Format("2006-01-02"), got)
	}
}

// AgeOn เทียบเดือน+วัน ไม่ใช่ YearDay — เคสรอบวันเกิดข้ามปีอธิกสุรทิน (วันที่ตายตัว ไม่พึ่ง time.Now)
func TestAgeOn_LeapYearBoundaries(t *testing.T) {
	d := func(y int, m time.Month, day int) time.Time {
		return time.Date(y, m, day, 0, 0, 0, 0, time.UTC)
	}
	cases := []struct {
		name  string
		birth time.Time
		on    time.Time
		want  int
	}{
		// เคสที่ YearDay เดิมพลาด: เกิดปีอธิกสุรทิน (1 มี.ค. = วันที่ 61) เทียบปีปกติ (1 มี.ค. = วันที่ 60)
		{"เกิด 1 มี.ค. 2000 ครบ 25 ใน 1 มี.ค. 2025", d(2000, time.March, 1), d(2025, time.March, 1), 25},
		{"เกิด 1 มี.ค. 2000 ก่อนครบ 25 ใน 28 ก.พ. 2025", d(2000, time.March, 1), d(2025, time.February, 28), 24},
		// เคสกลับกัน YearDay เดิมนับเกินวัน: เกิดปีปกติ (1 มี.ค. = วันที่ 60) เทียบปีอธิกสุรทิน (29 ก.พ. = วันที่ 60)
		{"เกิด 1 มี.ค. 2001 ยังไม่ครบ 23 ใน 29 ก.พ. 2024", d(2001, time.March, 1), d(2024, time.February, 29), 22},
		{"เกิด 1 มี.ค. 2001 ครบ 23 ใน 1 มี.ค. 2024", d(2001, time.March, 1), d(2024, time.March, 1), 23},
		// เกิด 29 ก.พ. — ปีปกติถือครบรอบวันที่ 1 มี.ค.
		{"เกิด 29 ก.พ. 2000 ยังไม่ครบ 25 ใน 28 ก.พ. 2025", d(2000, time.February, 29), d(2025, time.February, 28), 24},
		{"เกิด 29 ก.พ. 2000 ครบ 25 ใน 1 มี.ค. 2025", d(2000, time.February, 29), d(2025, time.March, 1), 25},
		{"เกิด 29 ก.พ. 2000 ครบ 24 ใน 29 ก.พ. 2024", d(2000, time.February, 29), d(2024, time.February, 29), 24},
		// วันเกิดตรงวัน / วันก่อนหน้า / ปลายปี
		{"วันเกิดตรงวัน", d(1999, time.July, 15), d(2025, time.July, 15), 26},
		{"ก่อนวันเกิด 1 วัน", d(1999, time.July, 15), d(2025, time.July, 14), 25},
		{"เกิด 31 ธ.ค. ยังไม่ครบใน 30 ธ.ค.", d(1999, time.December, 31), d(2025, time.December, 30), 25},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := AgeOn(c.birth, c.on); got != c.want {
				t.Errorf("AgeOn(%s, %s) = %d, want %d", c.birth.Format("2006-01-02"), c.on.Format("2006-01-02"), got, c.want)
			}
		})
	}
}

// ─────────────────────────────────────────────────────────────────────────
// NetEnergyKcal / CalculateCardioCalories — สูตร ACSM (METs−1)×3.5×kg/200×นาที
// ─────────────────────────────────────────────────────────────────────────

func TestNetEnergyKcal(t *testing.T) {
	cases := []struct {
		name          string
		mets, kg, min float64
		want          float64
	}{
		// ตัวอย่างใน FORMULAS.md B2: จ๊อกกิ้ง METs 8.3, 30 นาที, 70 กก. → 268.275
		{"จ๊อกกิ้ง 8.3 METs 30 นาที 70 กก.", 8.3, 70, 30, 268.275},
		{"Squat 5.0 METs 40 นาที 70 กก. (WorkedExamples)", 5.0, 70, 40, 196.0},
		{"METs = 1 (พักนิ่ง) ได้ 0", 1.0, 70, 30, 0},
		{"METs < 1 clamp เป็น 0 ไม่ติดลบ", 0.5, 70, 30, 0},
		{"เวลา 0 ได้ 0", 8.0, 70, 0, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := NetEnergyKcal(tc.mets, tc.kg, tc.min); !almostEqual(got, tc.want, 0.001) {
				t.Errorf("NetEnergyKcal(%.1f, %.0f, %.0f) = %.4f, want %.4f", tc.mets, tc.kg, tc.min, got, tc.want)
			}
		})
	}
}

// cdors_duration เก็บเป็นวินาที (ตั้งแต่ 2026-09-14) — 1800 วินาที = 30 นาที ต้องได้ค่าเท่ากับ NetEnergyKcal 30 นาที
func TestCalculateCardioCalories_DurationInSeconds(t *testing.T) {
	got := CalculateCardioCalories(8.3, 70, 30*60)
	if !almostEqual(got, 268.275, 0.001) {
		t.Errorf("CalculateCardioCalories(8.3, 70, 1800s) = %.4f, want 268.275", got)
	}
	// ว่ายน้ำ 6.0 METs (METs ต่ำสุดของตาราง cardio) 45 นาที 65 กก. = 5×1.13750×45 = 255.9375
	if got := CalculateCardioCalories(6.0, 65, 45*60); !almostEqual(got, 255.9375, 0.001) {
		t.Errorf("CalculateCardioCalories(6.0, 65, 2700s) = %.4f, want 255.9375", got)
	}
}

// ─────────────────────────────────────────────────────────────────────────
// CalculateNutrientTotals — ค่าต่อหน่วย × จำนวนหน่วยที่กิน ครบทั้ง 4 ค่า
// ─────────────────────────────────────────────────────────────────────────

func TestCalculateNutrientTotals(t *testing.T) {
	food := models.Nutrition{NttCalories: 100, NttProtein: 10, NttCarbs: 20, NttFat: 5}
	got := CalculateNutrientTotals(food, 2.5) // ตัวอย่างใน FORMULAS.md A3
	want := NutrientTotals{Calories: 250, Protein: 25, Carb: 50, Fat: 12.5}
	if got != want {
		t.Errorf("CalculateNutrientTotals(qty 2.5) = %+v, want %+v", got, want)
	}
}

// ─────────────────────────────────────────────────────────────────────────
// SQL ที่ประกอบจาก constant ของ Go — placeholder ต้องถูกแทนครบและได้ค่าที่ถูกต้อง
// ─────────────────────────────────────────────────────────────────────────

func TestDailySumBetweenSQL_ConstantsSubstituted(t *testing.T) {
	if strings.Contains(dailySumBetweenSQL, "{{") {
		t.Fatalf("SQL ยังมี placeholder ที่ไม่ถูกแทน: %s", dailySumBetweenSQL)
	}
	for _, want := range []string{"1500) * 1.2)", "2000) as target_tdee"} {
		if !strings.Contains(dailySumBetweenSQL, want) {
			t.Errorf("SQL ไม่มีส่วน %q (SedentaryCoefficient/Fallback constant ไม่ตรงกับที่คาด)", want)
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────
// CalculateBaselineExpenditure — Baseline = BMR × 1.2 (Sedentary, IOM 2548) ห้ามแก้ตัวเลข
// ─────────────────────────────────────────────────────────────────────────

func TestCalculateBaselineExpenditure(t *testing.T) {
	cases := []struct {
		bmr  float64
		want float64
	}{
		{1500, 1800},
		{1673.75, 2008.5},
		{0, 0},
	}
	for _, tc := range cases {
		if got := CalculateBaselineExpenditure(tc.bmr); !almostEqual(got, tc.want, 0.001) {
			t.Errorf("CalculateBaselineExpenditure(%.2f) = %.4f, want %.4f", tc.bmr, got, tc.want)
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────
// EstimateOneRepMax — Epley: weight × (1 + reps/30) (บทที่ 2 ข้อ 2.1.4.13) ห้ามแก้ตัวเลข
// ─────────────────────────────────────────────────────────────────────────

func TestEstimateOneRepMax(t *testing.T) {
	cases := []struct {
		weightKg float64
		reps     int
		want     float64
	}{
		{100, 5, 116.67},  // 100 * (1 + 5/30) = 116.666... -> 116.67
		{60, 10, 80},       // 60 * (1 + 10/30) = 80
		{0, 8, 0},          // ท่า bodyweight น้ำหนัก 0
		{100, 0, 100},      // reps=0 -> ไม่คูณเพิ่ม (นอกช่วงแม่นยำ 2-10 แต่สูตรยังคำนวณได้)
	}
	for _, tc := range cases {
		if got := EstimateOneRepMax(tc.weightKg, tc.reps); !almostEqual(got, tc.want, 0.005) {
			t.Errorf("EstimateOneRepMax(%.1f, %d) = %.2f, want %.2f", tc.weightKg, tc.reps, got, tc.want)
		}
	}
}

// ─────────────────────────────────────────────────────────────────────────
// CalculateGoals — BMI/BMR(Mifflin-St Jeor)/TDEE/Target ตามบทที่ 2 ข้อ 7 (root CLAUDE.md)
// ห้ามแก้ตัวเลข: ลดน้ำหนัก -20% (clamp ไม่ต่ำกว่า BMR), เพิ่มน้ำหนัก +15%, รักษาน้ำหนัก = TDEE
// ─────────────────────────────────────────────────────────────────────────

func TestCalculateGoals_Male_WeightLoss(t *testing.T) {
	bmi, bmr, tdee, target := CalculateGoals(70, 175, 25, 1, 1.55, 1)
	if !almostEqual(bmi, 22.86, 0.01) {
		t.Errorf("bmi = %.2f, want 22.86", bmi)
	}
	if !almostEqual(bmr, 1673.75, 0.01) {
		t.Errorf("bmr = %.2f, want 1673.75", bmr)
	}
	if !almostEqual(tdee, 2594.31, 0.01) {
		t.Errorf("tdee = %.2f, want 2594.31", tdee)
	}
	if !almostEqual(target, 2075.45, 0.01) {
		t.Errorf("target = %.2f, want 2075.45 (TDEE-20%%, ไม่ต่ำกว่า BMR)", target)
	}
}

func TestCalculateGoals_Female_WeightGain(t *testing.T) {
	bmi, bmr, tdee, target := CalculateGoals(55, 160, 30, 2, 1.2, 2)
	if !almostEqual(bmi, 21.48, 0.01) {
		t.Errorf("bmi = %.2f, want 21.48", bmi)
	}
	if !almostEqual(bmr, 1239, 0.01) {
		t.Errorf("bmr = %.2f, want 1239 (สูตรหญิง -161)", bmr)
	}
	if !almostEqual(tdee, 1486.8, 0.01) {
		t.Errorf("tdee = %.2f, want 1486.8", tdee)
	}
	if !almostEqual(target, 1709.82, 0.01) {
		t.Errorf("target = %.2f, want 1709.82 (TDEE+15%%)", target)
	}
}

func TestCalculateGoals_Maintain_EqualsTdee(t *testing.T) {
	_, _, tdee, target := CalculateGoals(65, 170, 28, 1, 1.375, 3)
	if !almostEqual(target, tdee, 0.001) {
		t.Errorf("target (รักษาน้ำหนัก) = %.2f, want เท่ากับ tdee %.2f", target, tdee)
	}
}

// เคสสำคัญ: ลดน้ำหนักแบบ deficit 20% ต่ำกว่า BMR ต้อง clamp กลับไปที่ BMR เสมอ (กฎเหล็กข้อ 8.3)
func TestCalculateGoals_WeightLoss_ClampsToBmr(t *testing.T) {
	_, bmr, tdee, target := CalculateGoals(50, 180, 60, 1, 1.2, 1)
	if !almostEqual(bmr, 1330, 0.01) {
		t.Errorf("bmr = %.2f, want 1330", bmr)
	}
	deficit := tdee - (tdee * 0.20)
	if deficit >= bmr {
		t.Fatalf("เคสทดสอบนี้ต้องออกแบบให้ deficit (%.2f) ต่ำกว่า bmr (%.2f) เพื่อทดสอบ clamp จริง", deficit, bmr)
	}
	if !almostEqual(target, bmr, 0.01) {
		t.Errorf("target = %.2f, want เท่ากับ bmr %.2f (clamp กันต่ำกว่า BMR)", target, bmr)
	}
}

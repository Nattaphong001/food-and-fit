package services

import "testing"

// ทดสอบพลังงานเวทเทรนนิ่ง — Dynamic METs รายเซตตาม %1RM เทียบ 1RM อ้างอิง (บทที่ 2 ข้อ 2.1.4.12
// ตารางที่ 2.3, ดู ../../CLAUDE.md ข้อ 7[B-1])
// หนักตัว 70 kg ทุกเคส → 3.5 × 70 / 200 = 1.225 kcal/นาที ต่อ 1 Net MET

func TestWeightSetMets(t *testing.T) {
	cases := []struct {
		name               string
		weightKg           float64
		reps               int
		reference1RM       float64
		hasWeight, hasReps bool
		want               float64
	}{
		{"บอดี้เวท (ไม่มีน้ำหนัก)", 0, 10, 0, false, true, MetsBodyweight},
		{"ท่าค้างเวลา (ไม่มีจำนวนครั้ง)", 0, 0, 0, false, false, MetsBodyweight},
		{"ท่าอุปกรณ์แต่กรอกน้ำหนัก 0", 0, 10, 100, true, true, MetsBodyweight},
		{"reps > 20 เกินขอบเขต 1RM", 40, 25, 100, true, true, MetsEndurance},
		{"ไม่มี 1RM อ้างอิง", 60, 10, 0, true, true, MetsEndurance},
		{"65% ความทนทาน", 65, 15, 100, true, true, MetsEndurance},
		{"69.9% ยังต่ำกว่าเกณฑ์", 69.9, 12, 100, true, true, MetsEndurance},
		{"70% พอดี = หนัก", 70, 10, 100, true, true, MetsHeavy},
		{"80% ช่องว่างตาราง 80-85% = หนัก", 82, 6, 100, true, true, MetsHeavy},
		{"110% ทำสถิติใหม่ ปัดเป็น 100%", 110, 3, 100, true, true, MetsHeavy},
		{"40% ต่ำกว่า 60% = ความทนทาน", 40, 20, 100, true, true, MetsEndurance},
	}
	for _, tc := range cases {
		if got := WeightSetMets(tc.weightKg, tc.reps, tc.reference1RM, tc.hasWeight, tc.hasReps); got != tc.want {
			t.Errorf("%s: WeightSetMets = %v, want %v", tc.name, got, tc.want)
		}
	}
}

// เคสบั๊กหลัก: ยกหนักกับยกเบา เวลาเท่ากัน ต้องได้พลังงานต่างกัน
func TestCalculateWeightTrainingCalories_HeavyBurnsMoreThanLightSameTime(t *testing.T) {
	heavy := []WeightSetEnergyInput{{90, 5, 120}, {90, 5, 120}, {90, 5, 120}} // 90% → 6.0
	light := []WeightSetEnergyInput{{50, 5, 120}, {50, 5, 120}, {50, 5, 120}} // 50% → 3.5

	_, _, heavyTotal := CalculateWeightTrainingCalories(heavy, 100, 70, true, true)
	_, _, lightTotal := CalculateWeightTrainingCalories(light, 100, 70, true, true)

	// หนัก: (6−1) × 1.225 × 2 นาที = 12.25 ต่อเซต × 3 = 36.75
	if !almostEqual(heavyTotal, 36.75, 0.001) {
		t.Errorf("heavy total = %v, want 36.75", heavyTotal)
	}
	// เบา: (3.5−1) × 1.225 × 2 = 6.125 → ปัด 6.13 ต่อเซต × 3 = 18.39
	if !almostEqual(lightTotal, 18.39, 0.001) {
		t.Errorf("light total = %v, want 18.39", lightTotal)
	}
	if heavyTotal <= lightTotal {
		t.Fatalf("ยกหนักต้องได้พลังงานมากกว่ายกเบาที่เวลาเท่ากัน: heavy=%v light=%v", heavyTotal, lightTotal)
	}
}

// แต่ละเซตได้ METs/เวลาของตัวเอง ไม่หารเท่ากัน และผลรวมรายเซต = total (SUM(wtrs_calories) ถูกต้อง)
func TestCalculateWeightTrainingCalories_PerSetMetsAndTime(t *testing.T) {
	sets := []WeightSetEnergyInput{
		{90, 3, 140},  // 90% → 6.0 → 5 × 1.225 × 140/60 = 14.29
		{65, 15, 120}, // 65% → 3.5 → 2.5 × 1.225 × 2 = 6.125 → 6.13
	}
	kcal, mets, total := CalculateWeightTrainingCalories(sets, 100, 70, true, true)
	if mets[0] != MetsHeavy || mets[1] != MetsEndurance {
		t.Errorf("mets = %v, want [6 3.5]", mets)
	}
	if !almostEqual(kcal[0], 14.29, 0.001) || !almostEqual(kcal[1], 6.13, 0.001) {
		t.Errorf("kcal = %v, want [14.29 6.13]", kcal)
	}
	if !almostEqual(total, kcal[0]+kcal[1], 0.0001) {
		t.Errorf("total %v ต้องเท่ากับผลรวมรายเซต %v", total, kcal[0]+kcal[1])
	}
}

func TestCalculateWeightTrainingCalories_Bodyweight(t *testing.T) {
	// Pull-up 3 เซต เซตละ 60 วิ → 3.0 → 2 × 1.225 × 1 = 2.45 ต่อเซต
	sets := []WeightSetEnergyInput{{0, 10, 60}, {0, 8, 60}, {0, 6, 60}}
	_, mets, total := CalculateWeightTrainingCalories(sets, 0, 70, false, true)
	for _, m := range mets {
		if m != MetsBodyweight {
			t.Fatalf("บอดี้เวทต้องได้ METs 3.0 ทุกเซต ได้ %v", mets)
		}
	}
	if !almostEqual(total, 7.35, 0.001) {
		t.Errorf("total = %v, want 7.35", total)
	}
}

func TestCalculateWeightTrainingCalories_EmptySets(t *testing.T) {
	kcal, mets, total := CalculateWeightTrainingCalories(nil, 100, 70, true, true)
	if len(kcal) != 0 || len(mets) != 0 || total != 0 {
		t.Fatalf("เซสชันว่างต้องได้ค่าศูนย์ทั้งหมด ได้ %v %v %v", kcal, mets, total)
	}
}

// Fallback ไม่มีประวัติ: 1RM อ้างอิง = e1RM สูงสุดของเซสชันนี้ (Dual-Formula)
func TestSessionBestOneRepMax(t *testing.T) {
	sets := []WeightSetEnergyInput{
		{80, 5, 60},  // Epley 80 × (1 + 5/30) = 93.33
		{60, 12, 60}, // Desgorces ≈ 81.61
		{40, 25, 60}, // reps > 20 ประเมินไม่ได้
	}
	if got := SessionBestOneRepMax(sets); !almostEqual(got, 93.33, 0.005) {
		t.Errorf("SessionBestOneRepMax = %v, want 93.33", got)
	}
	if got := SessionBestOneRepMax([]WeightSetEnergyInput{{40, 25, 60}, {0, 10, 60}}); got != 0 {
		t.Errorf("ไม่มีเซตประเมินได้ต้องได้ 0 ได้ %v", got)
	}
}

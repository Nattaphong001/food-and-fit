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
	heavy := []WeightSetEnergyInput{{90, 5, 120, false}, {90, 5, 120, false}, {90, 5, 120, false}} // 90% → 6.0
	light := []WeightSetEnergyInput{{50, 5, 120, false}, {50, 5, 120, false}, {50, 5, 120, false}} // 50% → 3.5

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
		{90, 3, 140, false},  // 90% → 6.0 → 5 × 1.225 × 140/60 = 14.29
		{65, 15, 120, false}, // 65% → 3.5 → 2.5 × 1.225 × 2 = 6.125 → 6.13
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
	sets := []WeightSetEnergyInput{{0, 10, 60, false}, {0, 8, 60, false}, {0, 6, 60, false}}
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

// ไม่มีตัวอ้างอิงเลย (reference1RM = 0): ทุกเซตที่มีน้ำหนักได้ 3.5 ท่าที่ไม่มีน้ำหนักยังได้ 3.0
func TestCalculateWeightTrainingCalories_NoReference(t *testing.T) {
	sets := []WeightSetEnergyInput{{90, 3, 120, false}, {30, 10, 120, false}, {0, 8, 120, false}}
	_, mets, _ := CalculateWeightTrainingCalories(sets, 0, 70, true, true)
	if mets[0] != MetsEndurance || mets[1] != MetsEndurance {
		t.Errorf("ไม่มีตัวอ้างอิง ทุกเซตที่มีน้ำหนักต้อง 3.5 ได้ %v", mets)
	}
	if mets[2] != MetsBodyweight {
		t.Errorf("เซตน้ำหนัก 0 ต้อง 3.0 ได้ %v", mets[2])
	}
}

func TestSessionReferenceOneRepMax(t *testing.T) {
	cases := []struct {
		name string
		sets []WeightSetEnergyInput
		want float64
	}{
		{"ว่าง", nil, 0},
		{"เซตเดียว 75×10 ยืนยัน (Epley)", []WeightSetEnergyInput{{75, 10, 120, true}}, 100},
		{"เลือกสูงสุดจากเฉพาะเซตที่ยืนยัน", []WeightSetEnergyInput{{80, 5, 120, true}, {50, 10, 120, true}, {90, 3, 120, true}}, 99},
		{"เซตที่ไม่ยืนยันไม่นับ แม้หนักกว่า", []WeightSetEnergyInput{{90, 3, 120, false}, {50, 10, 120, true}}, EstimateOneRepMax(50, 10)},
		{"ไม่มีเซตไหนยืนยัน", []WeightSetEnergyInput{{80, 5, 120, false}, {50, 10, 120, false}}, 0},
		{"11-20 ครั้งใช้ Desgorces", []WeightSetEnergyInput{{60, 15, 120, true}}, EstimateOneRepMax(60, 15)},
		{"ทุกเซต > 20 ครั้ง ไม่มีตัวอ้างอิง", []WeightSetEnergyInput{{40, 25, 120, true}, {30, 30, 120, true}}, 0},
		{"น้ำหนัก 0 ไม่นับ", []WeightSetEnergyInput{{0, 10, 120, true}}, 0},
	}
	for _, tc := range cases {
		if got := SessionReferenceOneRepMax(tc.sets); !almostEqual(got, tc.want, 0.001) {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestResolveReferenceOneRepMax(t *testing.T) {
	flagged := []WeightSetEnergyInput{{80, 5, 120, true}, {50, 10, 120, false}}
	unflagged := []WeightSetEnergyInput{{80, 5, 120, false}, {50, 10, 120, false}}
	long := []WeightSetEnergyInput{{40, 25, 120, true}}
	cases := []struct {
		name       string
		history    float64
		sets       []WeightSetEnergyInput
		hasW, hasR bool
		wantRef    float64
		wantSrc    string
	}{
		{"มี PR ใช้ PR ไม่สนคำตอบ", 120, unflagged, true, true, 120, ReferenceHistory},
		{"ไม่มี PR + มีเซตยืนยัน", 0, flagged, true, true, EstimateOneRepMax(80, 5), ReferenceSession},
		{"ไม่มี PR + ไม่มีเซตยืนยัน", 0, unflagged, true, true, 0, ReferenceSessionDeclined},
		{"ยืนยันแต่ทุกเซต reps > 20", 0, long, true, true, 0, ReferenceNone},
		{"บอดี้เวท", 0, flagged, false, true, 0, ReferenceNotApplicable},
		{"ท่าค้างเวลา", 0, flagged, true, false, 0, ReferenceNotApplicable},
	}
	for _, tc := range cases {
		ref, src := ResolveReferenceOneRepMax(tc.history, tc.sets, tc.hasW, tc.hasR)
		if !almostEqual(ref, tc.wantRef, 0.001) || src != tc.wantSrc {
			t.Errorf("%s: got (%v, %s), want (%v, %s)", tc.name, ref, src, tc.wantRef, tc.wantSrc)
		}
	}
}

// เซสชันแรกไม่มี PR: ตัวอ้างอิง = e1RM ของเซตที่ผู้ใช้ยืนยัน (80×5 และ 90×3 ยืนยัน, 50×10 ไม่ยืนยัน)
// → เซตหนักได้ 6.0 เซตเบาได้ 3.5
func TestCalculateWeightTrainingCalories_FirstSessionUsesSessionReference(t *testing.T) {
	sets := []WeightSetEnergyInput{{80, 5, 120, true}, {50, 10, 120, false}, {90, 3, 120, true}}
	ref := SessionReferenceOneRepMax(sets)
	_, mets, total := CalculateWeightTrainingCalories(sets, ref, 70, true, true)
	if mets[0] != MetsHeavy || mets[1] != MetsEndurance || mets[2] != MetsHeavy {
		t.Errorf("mets = %v, want [6 3.5 6]", mets)
	}
	if !almostEqual(total, 12.25+6.13+12.25, 0.001) {
		t.Errorf("total = %v, want 30.63", total)
	}
}

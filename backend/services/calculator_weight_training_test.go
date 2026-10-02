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

// ── ตรวจช่องโหว่ของสูตร (2026-10-02) ──
// เคสที่ชื่อขึ้นต้น Limitation = ข้อจำกัดที่ทราบและเปิดเผยในเล่มแล้ว (CLAUDE.md ข้อ 7[B-1] ข้อจำกัด ก/ข)
// test ล็อกพฤติกรรมปัจจุบันไว้ ถ้าแก้ช่องโหว่แล้วต้องปรับ test ตาม

// มี PR แล้ว → คำตอบ near_failure ต้องไม่มีผล (กันผู้ใช้ตอบ "ใช่" เพื่อดันตัวอ้างอิงเอง)
func TestResolveReferenceOneRepMax_HistoryIgnoresNearFailure(t *testing.T) {
	sets := []WeightSetEnergyInput{{200, 1, 60, true}}
	ref, src := ResolveReferenceOneRepMax(100, sets, true, true)
	if ref != 100 || src != ReferenceHistory {
		t.Errorf("got (%v, %s), want (100, history)", ref, src)
	}
}

// ขอบ 70%: 69.99 → 3.5, 70.00 → 6.0 และขอบ reps 20/21
func TestWeightSetMets_Boundaries(t *testing.T) {
	if got := WeightSetMets(69.99, 10, 100, true, true); got != MetsEndurance {
		t.Errorf("69.99%% = %v, want %v", got, MetsEndurance)
	}
	if got := WeightSetMets(70, 10, 100, true, true); got != MetsHeavy {
		t.Errorf("70%% = %v, want %v", got, MetsHeavy)
	}
	if got := WeightSetMets(90, 20, 100, true, true); got != MetsHeavy {
		t.Errorf("reps 20 ยังเข้าสมการ = %v, want %v", got, MetsHeavy)
	}
	if got := WeightSetMets(90, 21, 100, true, true); got != MetsEndurance {
		t.Errorf("reps 21 = %v, want %v", got, MetsEndurance)
	}
}

// ผลรวมต้องเท่ากับผลบวกของ kcal รายเซตที่ปัดแล้ว (SUM(wtrs_calories) ใน DB ต้องตรง calories_burned)
func TestCalculateWeightTrainingCalories_TotalEqualsSumOfRoundedRows(t *testing.T) {
	sets := []WeightSetEnergyInput{{50, 5, 37, false}, {50, 5, 41, false}, {50, 5, 43, false}, {95, 3, 59, false}}
	kcal, _, total := CalculateWeightTrainingCalories(sets, 100, 73.3, true, true)
	sum := 0.0
	for _, k := range kcal {
		sum += k
	}
	if !almostEqual(total, sum, 0.005) {
		t.Errorf("total = %v, sum รายเซต = %v", total, sum)
	}
}

// ค่าผิดปกติต้องไม่ทำให้ติดลบ/NaN
func TestCalculateWeightTrainingCalories_NoNegativeOrZeroInputs(t *testing.T) {
	sets := []WeightSetEnergyInput{{80, 5, 0, false}, {80, 5, 60, false}}
	kcal, _, total := CalculateWeightTrainingCalories(sets, 100, 0, true, true)
	for i, k := range kcal {
		if k != 0 {
			t.Errorf("น้ำหนักตัว 0 → kcal[%d] = %v, want 0", i, k)
		}
	}
	if total != 0 {
		t.Errorf("total = %v, want 0", total)
	}
	// เซตเวลา 0 วินาที ได้ 0 ไม่ติดลบ
	kcal, _, _ = CalculateWeightTrainingCalories(sets, 100, 70, true, true)
	if kcal[0] != 0 || kcal[1] <= 0 {
		t.Errorf("kcal = %v, want [0, >0]", kcal)
	}
}

// ท่าบอดี้เวท/ค้างเวลา: near_failure และ PR ไม่มีผล ได้ 3.0 คงที่
func TestResolveReferenceOneRepMax_BodyweightIgnoresEverything(t *testing.T) {
	sets := []WeightSetEnergyInput{{0, 10, 60, true}}
	ref, src := ResolveReferenceOneRepMax(150, sets, false, true)
	if ref != 0 || src != ReferenceNotApplicable {
		t.Errorf("got (%v, %s)", ref, src)
	}
	_, mets, _ := CalculateWeightTrainingCalories(sets, ref, 70, false, true)
	if mets[0] != MetsBodyweight {
		t.Errorf("mets = %v, want 3.0", mets[0])
	}
}

// Limitation (ก): เซสชันแรก ยกเบา 20 กก. × 5 แล้วตอบ "ใช่" → ตัวอ้างอิงต่ำ → เซตหนักถัดมาได้ 6.0
// ระบบตรวจคำตอบของผู้ใช้ไม่ได้ (ตอบเกินจริงได้พลังงานสูงขึ้น)
func TestLimitation_FirstSessionHonorSystemInflatesMets(t *testing.T) {
	honest := []WeightSetEnergyInput{{20, 5, 60, false}, {60, 8, 60, true}}
	lie := []WeightSetEnergyInput{{20, 5, 60, true}, {60, 8, 60, false}}
	_, mHonest, _ := CalculateWeightTrainingCalories(honest, SessionReferenceOneRepMax(honest), 70, true, true)
	_, mLie, _ := CalculateWeightTrainingCalories(lie, SessionReferenceOneRepMax(lie), 70, true, true)
	if mHonest[0] != MetsEndurance {
		t.Errorf("เซตเบา (ตอบตรง) = %v, want 3.5", mHonest[0])
	}
	if mLie[0] != MetsHeavy {
		t.Errorf("เซตเบาที่ตอบ \"ใช่\" ได้ 6.0 ตามที่บันทึกข้อจำกัดไว้ แต่ได้ %v", mLie[0])
	}
}

// Limitation (ข): PR ต่ำจากครั้งแรกที่ยกเบา → ครั้งถัดไปยกปานกลางได้ 6.0 เร็วเกินไป
func TestLimitation_LowPRGivesHeavyMetsTooEarly(t *testing.T) {
	lowPR := EstimateOneRepMax(30, 10) // 40 กก.
	if got := WeightSetMets(60, 8, lowPR, true, true); got != MetsHeavy {
		t.Errorf("got %v, want %v (ล็อกพฤติกรรมที่ทราบ)", got, MetsHeavy)
	}
}

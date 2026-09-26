package services

import (
	"food_and_fit_api/helpers"
	"testing"
)

// ทดสอบ Session MET ตามตาราง 2.2 + Effort Ratio (services/calculator.go ข้อ 5) — ดูตารางเกณฑ์/สูตร
// เต็มที่ ../../CLAUDE.md ข้อ 7[B]

func w(weightKg float64, reps int) helpers.WeightSetCheck {
	return helpers.WeightSetCheck{Reps: reps, WeightKg: weightKg}
}

// ── resolveSessionMET: อุปกรณ์น้ำหนักตัว (wet_equipment = 5) ──

func TestResolveSessionMET_Bodyweight_AlwaysLight(t *testing.T) {
	// อุปกรณ์น้ำหนักตัว → เบา (3.0) เสมอ ไม่สนใจ reps/weight/ประวัติ 1RM เลย (ตาราง 2.2 มีแถวเดียว)
	met, level := resolveSessionMET(WeightTrainingBodyweightEquipment, 100, []helpers.WeightSetCheck{w(0, 20), w(0, 3)})
	if met != metBodyweightGeneral || level != 1 {
		t.Fatalf("ต้องการ (3.0, เบา) ได้ (%v, %d)", met, level)
	}
}

// ── resolveSessionMET: มีประวัติ Best 1RM → ใช้ Effort Ratio ──

func TestResolveSessionMET_WithHistory_HighEffort_Powerlifting(t *testing.T) {
	// พาวเวอร์ลิฟติ้ง: ยกหนักน้อยครั้ง — ER = e1RM/best = (95*(1+3/30))/100 = 104.5/100 = 1.045 >= 0.90
	met, level := resolveSessionMET(1, 100, []helpers.WeightSetCheck{w(95, 3), w(95, 3), w(95, 3)})
	if met != metResistanceHigh || level != 3 {
		t.Fatalf("ต้องการ (6.0, หนัก) ได้ (%v, %d)", met, level)
	}
}

func TestResolveSessionMET_WithHistory_HighEffort_Bodybuilding(t *testing.T) {
	// เพาะกาย: ยกกลางๆ จนหมดแรง — ER = (70*(1+10/30))/100 = 93.33/100 = 0.933 >= 0.90
	// จุดสำคัญ: %1RM ดิบ (70%) ต่ำกว่าเกณฑ์ NSCA เดิม (85%) แต่ Effort Ratio จับได้ว่าเป็นความพยายามสูง
	met, level := resolveSessionMET(2, 100, []helpers.WeightSetCheck{w(70, 10), w(70, 10)})
	if met != metResistanceHigh || level != 3 {
		t.Fatalf("เพาะกาย 70%%1RM x10 จนหมดแรง ต้องการ (6.0, หนัก) ได้ (%v, %d)", met, level)
	}
}

func TestResolveSessionMET_WithHistory_Moderate(t *testing.T) {
	// ยกกลางๆ ยังเหลือแรง — ER = (50*(1+10/30))/80 = 66.67/80 = 0.833 < 0.90
	met, level := resolveSessionMET(1, 80, []helpers.WeightSetCheck{w(50, 10), w(50, 10)})
	if met != metResistanceModerate || level != 2 {
		t.Fatalf("ต้องการ (3.5, ปานกลาง) ได้ (%v, %d)", met, level)
	}
}

func TestResolveSessionMET_WithHistory_IgnoresZeroWeightSets(t *testing.T) {
	// เซตที่น้ำหนักที่ยก = 0 (เช่น assisted/failed set) ต้องไม่ถูกนับเข้า ER เฉลี่ย
	met, level := resolveSessionMET(1, 100, []helpers.WeightSetCheck{w(95, 3), w(0, 0)})
	if met != metResistanceHigh || level != 3 {
		t.Fatalf("เซต weight=0 ต้องถูกข้าม ไม่ดึงค่าเฉลี่ยลง ต้องการ (6.0, หนัก) ได้ (%v, %d)", met, level)
	}
}

// ── resolveSessionMET: ไม่มีประวัติ Best 1RM → ใช้ Reps เฉลี่ยแทน (ทางสำรอง) ──

func TestResolveSessionMET_NoHistory_LowReps_High(t *testing.T) {
	// ครั้งแรกที่ฝึกท่านี้ ไม่มี Best 1RM, Reps เฉลี่ย <= 7 และมีน้ำหนักที่ยกจริง → หนัก
	met, level := resolveSessionMET(1, 0, []helpers.WeightSetCheck{w(100, 5), w(100, 5)})
	if met != metResistanceHigh || level != 3 {
		t.Fatalf("ต้องการ (6.0, หนัก) ได้ (%v, %d)", met, level)
	}
}

func TestResolveSessionMET_NoHistory_HighReps_Moderate(t *testing.T) {
	met, level := resolveSessionMET(1, 0, []helpers.WeightSetCheck{w(40, 12), w(40, 12)})
	if met != metResistanceModerate || level != 2 {
		t.Fatalf("ต้องการ (3.5, ปานกลาง) ได้ (%v, %d)", met, level)
	}
}

func TestResolveSessionMET_NoHistory_NoWeightedSets_Moderate(t *testing.T) {
	// ไม่มีประวัติ และไม่มีเซตไหนมีน้ำหนักที่ยกจริง (เช่น เครื่องที่ไม่ได้กรอกน้ำหนัก) → ไม่เดาว่าหนัก
	// ตกไปปานกลาง (ปลอดภัยกว่า)
	met, level := resolveSessionMET(1, 0, []helpers.WeightSetCheck{w(0, 5), w(0, 5)})
	if met != metResistanceModerate || level != 2 {
		t.Fatalf("ต้องการ (3.5, ปานกลาง) ได้ (%v, %d)", met, level)
	}
}

// ── ค่าขอบเกณฑ์ (boundary values) ──

func TestResolveSessionMET_EffortRatioExactly090_EntersHigh(t *testing.T) {
	// ER = (60*(1+15/30))/100 = 90/100 = 0.90 พอดี — เกณฑ์ใช้ >= จึงต้องเข้าหนัก
	met, _ := resolveSessionMET(1, 100, []helpers.WeightSetCheck{w(60, 15)})
	if met != metResistanceHigh {
		t.Fatalf("ER = 0.90 พอดี (เกณฑ์ >=) ต้องเข้า metResistanceHigh ได้ %v", met)
	}
}

func TestResolveSessionMET_EffortRatioJustBelow090_DoesNotEnterHigh(t *testing.T) {
	// ER = (59.9*1.5)/100 = 0.8985 ต่ำกว่าเกณฑ์เล็กน้อย
	met, _ := resolveSessionMET(1, 100, []helpers.WeightSetCheck{w(59.9, 15)})
	if met != metResistanceModerate {
		t.Fatalf("ER = 0.8985 ต่ำกว่าเกณฑ์ 0.90 ต้องเข้า metResistanceModerate ได้ %v", met)
	}
}

func TestResolveSessionMET_FallbackReps7VsReps8(t *testing.T) {
	// ไม่มีประวัติ: Reps เฉลี่ย <= 7 เข้าหนัก, Reps เฉลี่ย 8 ต้องตกไปปานกลาง
	metReps7, _ := resolveSessionMET(1, 0, []helpers.WeightSetCheck{w(80, 7)})
	if metReps7 != metResistanceHigh {
		t.Fatalf("Reps=7 ไม่มีประวัติ ต้องเข้า metResistanceHigh ได้ %v", metReps7)
	}
	metReps8, _ := resolveSessionMET(1, 0, []helpers.WeightSetCheck{w(80, 8)})
	if metReps8 != metResistanceModerate {
		t.Fatalf("Reps=8 ไม่มีประวัติ ต้องเข้า metResistanceModerate (เกณฑ์ <= 7) ได้ %v", metReps8)
	}
}

// ── CalculateWeightTrainingCalories: ตัวอย่างเซสชันเต็ม ──

func TestCalculateWeightTrainingCalories_BenchPressSession_Moderate(t *testing.T) {
	// Bench Press 4x10 @50kg, 1RM ก่อนหน้า 80kg, หนักตัว 70kg, เวลารวมทั้งเซสชัน 10 นาที (600 วิ)
	// ER = (50*1.3333)/80 = 0.833 < 0.90 → moderate (3.5)
	// kcal = (3.5-1) × 3.5 × 70 / 200 × 10 = 30.625 ≈ 30.63
	sets := []helpers.WeightSetCheck{w(50, 10), w(50, 10), w(50, 10), w(50, 10)}
	kcalPerSet, total, sessionMET, level := CalculateWeightTrainingCalories(1, 70, 80, 600, sets)

	if sessionMET != metResistanceModerate {
		t.Fatalf("ต้องการ sessionMET = metResistanceModerate (3.5) ได้ %v", sessionMET)
	}
	if level != 2 {
		t.Fatalf("ต้องการ intensityLevel = 2 (ปานกลาง) ได้ %d", level)
	}
	if !almostEqual(total, 30.63, 0.01) {
		t.Fatalf("total kcal ต้องการ ~30.63 ได้ %v", total)
	}
	if len(kcalPerSet) != 4 {
		t.Fatalf("ต้องการ 4 เซต ได้ %d", len(kcalPerSet))
	}
	for _, k := range kcalPerSet {
		if !almostEqual(k, total/4, 0.001) {
			t.Fatalf("ต้องกระจาย kcal เท่ากันทุกเซต ได้ %v (total/4=%v)", k, total/4)
		}
	}
}

func TestCalculateWeightTrainingCalories_HeavySession(t *testing.T) {
	// 3x3 @95kg, 1RM ก่อนหน้า 100kg, หนักตัว 70kg, เวลารวม 3 นาที (180 วิ)
	// ER = 1.045 >= 0.90 → หนัก (6.0)
	// kcal = (6-1) × 3.5 × 70 / 200 × 3 = 18.375 ≈ 18.38
	sets := []helpers.WeightSetCheck{w(95, 3), w(95, 3), w(95, 3)}
	_, total, sessionMET, level := CalculateWeightTrainingCalories(1, 70, 100, 180, sets)

	if sessionMET != metResistanceHigh {
		t.Fatalf("ต้องการ sessionMET = metResistanceHigh (6.0) ได้ %v", sessionMET)
	}
	if level != 3 {
		t.Fatalf("ต้องการ intensityLevel = 3 (หนัก) ได้ %d", level)
	}
	if !almostEqual(total, 18.38, 0.01) {
		t.Fatalf("total kcal ต้องการ ~18.38 ได้ %v", total)
	}
}

func TestCalculateWeightTrainingCalories_BodyweightSession(t *testing.T) {
	// วิดพื้น 3x20 ครั้ง หนักตัว 70kg เวลารวม 5 นาที (300 วิ) — MET = 3.0 (เบา) เสมอ
	// kcal = (3-1) × 3.5 × 70 / 200 × 5 = 12.25
	sets := []helpers.WeightSetCheck{w(0, 20), w(0, 20), w(0, 20)}
	_, total, sessionMET, level := CalculateWeightTrainingCalories(WeightTrainingBodyweightEquipment, 70, 0, 300, sets)

	if sessionMET != metBodyweightGeneral || level != 1 {
		t.Fatalf("ต้องการ (3.0, เบา) ได้ (%v, %d)", sessionMET, level)
	}
	if !almostEqual(total, 12.25, 0.001) {
		t.Fatalf("total kcal ต้องการ 12.25 ได้ %v", total)
	}
}

func TestCalculateWeightTrainingCalories_NoHistory_UsesRepsFallback(t *testing.T) {
	// ครั้งแรกที่ฝึกท่านี้ (bestOneRepMax = 0), Reps เฉลี่ย <= 7 → หนัก (6.0)
	sets := []helpers.WeightSetCheck{w(100, 5), w(100, 5), w(100, 5)}
	_, total, sessionMET, level := CalculateWeightTrainingCalories(1, 70, 0, 150, sets)

	if sessionMET != metResistanceHigh || level != 3 {
		t.Fatalf("ต้องการ (6.0, หนัก) ได้ (%v, %d)", sessionMET, level)
	}
	if total <= 0 {
		t.Fatalf("ต้องคำนวณพลังงานได้มากกว่า 0 ได้ %v", total)
	}
}

func TestCalculateWeightTrainingCalories_TotalDurationUsedDirectly(t *testing.T) {
	// เวลารวมทั้งเซสชันเข้าสูตรตรงๆ (ไม่มีการตัดเพดาน/resolve เวลาพักต่อเซตแล้ว) — เซสชันยาวเป็น 2 เท่า
	// (สัดส่วนเซต/MET เดิม) ต้องได้ kcal เป็น 2 เท่าเป๊ะ
	sets := []helpers.WeightSetCheck{w(50, 10), w(50, 10)}
	_, shortTotal, _, _ := CalculateWeightTrainingCalories(1, 70, 0, 300, sets)
	_, longTotal, _, _ := CalculateWeightTrainingCalories(1, 70, 0, 600, sets)
	if !almostEqual(longTotal, shortTotal*2, 0.01) {
		t.Fatalf("เวลาเป็น 2 เท่า ต้องได้ kcal เป็น 2 เท่า ได้ short=%v long=%v", shortTotal, longTotal)
	}
}

func TestCalculateWeightTrainingCalories_EmptySets(t *testing.T) {
	kcalPerSet, total, sessionMET, level := CalculateWeightTrainingCalories(1, 70, 0, 100, nil)
	if len(kcalPerSet) != 0 || total != 0 || sessionMET != 0 || level != 2 {
		t.Fatalf("เซสชันว่างต้องได้ค่าศูนย์ทั้งหมดและ level=2 ได้ %v %v %v %d", kcalPerSet, total, sessionMET, level)
	}
}

func TestCalculateWeightTrainingCalories_SingleSetSession(t *testing.T) {
	// เซสชันมีแค่ 1 เซต (เช่น AMRAP เดียว) ต้องไม่ error/panic และกระจาย kcal ทั้งหมดให้เซตเดียวนั้น
	sets := []helpers.WeightSetCheck{w(60, 8)}
	kcalPerSet, total, _, _ := CalculateWeightTrainingCalories(1, 70, 100, 92, sets)
	if len(kcalPerSet) != 1 {
		t.Fatalf("ต้องการ 1 เซต ได้ %d", len(kcalPerSet))
	}
	if !almostEqual(kcalPerSet[0], total, 0.001) {
		t.Fatalf("เซสชันเซตเดียว kcal ต่อเซตต้องเท่ากับ total ได้ %v vs %v", kcalPerSet[0], total)
	}
	if total <= 0 {
		t.Fatalf("ต้องได้ kcal มากกว่า 0 ได้ %v", total)
	}
}

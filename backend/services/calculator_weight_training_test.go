package services

import "testing"

// ทดสอบ CalculateWeightTrainingCalories — METs คงที่ต่อท่า (weight_exercises.wet_mets)
// แบบเดียวกับคาร์ดิโอ (ดู ../../CLAUDE.md ข้อ 7[B-1])

func TestCalculateWeightTrainingCalories_BenchPressSession(t *testing.T) {
	// Bench Press (wet_mets = 3.5), หนักตัว 70kg, เวลารวมทั้งเซสชัน 10 นาที (600 วิ), 4 เซต
	// kcal = (3.5-1) × 3.5 × 70 / 200 × 10 = 30.625 ≈ 30.63
	kcalPerSet, total := CalculateWeightTrainingCalories(3.5, 70, 600, 4)

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

func TestCalculateWeightTrainingCalories_SquatSession(t *testing.T) {
	// Back Squat (wet_mets = 5.0), หนักตัว 70kg, เวลารวม 3 นาที (180 วิ), 3 เซต
	// kcal = (5-1) × 3.5 × 70 / 200 × 3 = 14.7
	_, total := CalculateWeightTrainingCalories(5.0, 70, 180, 3)
	if !almostEqual(total, 14.7, 0.01) {
		t.Fatalf("total kcal ต้องการ ~14.7 ได้ %v", total)
	}
}

func TestCalculateWeightTrainingCalories_BodyweightSession(t *testing.T) {
	// Pull-up (wet_mets = 3.0), หนักตัว 70kg เวลารวม 5 นาที (300 วิ)
	// kcal = (3-1) × 3.5 × 70 / 200 × 5 = 12.25
	_, total := CalculateWeightTrainingCalories(3.0, 70, 300, 3)
	if !almostEqual(total, 12.25, 0.001) {
		t.Fatalf("total kcal ต้องการ 12.25 ได้ %v", total)
	}
}

func TestCalculateWeightTrainingCalories_TotalDurationUsedDirectly(t *testing.T) {
	// เวลารวมทั้งเซสชันเข้าสูตรตรงๆ — เซสชันยาวเป็น 2 เท่า (MET/จำนวนเซตเดิม) ต้องได้ kcal เป็น 2 เท่าเป๊ะ
	_, shortTotal := CalculateWeightTrainingCalories(3.5, 70, 300, 2)
	_, longTotal := CalculateWeightTrainingCalories(3.5, 70, 600, 2)
	if !almostEqual(longTotal, shortTotal*2, 0.01) {
		t.Fatalf("เวลาเป็น 2 เท่า ต้องได้ kcal เป็น 2 เท่า ได้ short=%v long=%v", shortTotal, longTotal)
	}
}

func TestCalculateWeightTrainingCalories_EmptySets(t *testing.T) {
	kcalPerSet, total := CalculateWeightTrainingCalories(3.5, 70, 100, 0)
	if len(kcalPerSet) != 0 || total != 0 {
		t.Fatalf("เซสชันว่างต้องได้ค่าศูนย์ทั้งหมด ได้ %v %v", kcalPerSet, total)
	}
}

func TestCalculateWeightTrainingCalories_SingleSetSession(t *testing.T) {
	// เซสชันมีแค่ 1 เซต (เช่น AMRAP เดียว) ต้องไม่ error/panic และกระจาย kcal ทั้งหมดให้เซตเดียวนั้น
	kcalPerSet, total := CalculateWeightTrainingCalories(3.5, 70, 92, 1)
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

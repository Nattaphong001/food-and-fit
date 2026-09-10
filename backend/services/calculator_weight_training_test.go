package services

import (
	"math"
	"testing"
)

func almostEqual(a, b, tolerance float64) bool {
	return math.Abs(a-b) <= tolerance
}

// Use case จากการออกแบบ 2026-09-08: 75kg / 60 นาที / Squat 4 + Bench 4 + Curl 3 เซต
// ไม่มีประวัติ 1RM (oneRepMax=0) → kLoad คงที่ 1.0 (กลาง)
// คาดหวัง (คำนวณมือ): SessionBaseMET=4.4545, cappedMinutes=min(60,11*4)=44,
// density=44/11=4.0 -> kDensity=0.90, FinalMET=4.4545*1.0*0.90=4.0091,
// Kcal=(4.0091-1)*75*(44/60)=165.5
func TestCalculateWeightTrainingCalories_UseCase(t *testing.T) {
	sets := []SetLog{}
	for i := 0; i < 4; i++ {
		sets = append(sets, SetLog{BaseMET: 5.5, WeightKg: 100, Reps: 5}) // Squat (compound ล่าง)
	}
	for i := 0; i < 4; i++ {
		sets = append(sets, SetLog{BaseMET: 4.5, WeightKg: 60, Reps: 8}) // Bench Press (compound บน)
	}
	for i := 0; i < 3; i++ {
		sets = append(sets, SetLog{BaseMET: 3.0, WeightKg: 15, Reps: 12}) // Bicep Curl (isolation)
	}

	result := CalculateWeightTrainingCalories(75, 60*60, 0, sets)

	if !almostEqual(result.SessionBaseMET, 4.454545, 0.001) {
		t.Errorf("SessionBaseMET = %.6f, want ~4.454545", result.SessionBaseMET)
	}
	if !almostEqual(result.EffectiveMinutes, 44.0, 0.01) {
		t.Errorf("EffectiveMinutes = %.4f, want 44.0 (ต้องถูกเพดานจาก 60 เหลือ 11เซต×4นาที)", result.EffectiveMinutes)
	}
	if !almostEqual(result.KDensity, 0.90, 0.001) {
		t.Errorf("KDensity = %.4f, want 0.90 (density=4.0 >= 3.0)", result.KDensity)
	}
	if result.KLoad != 1.0 {
		t.Errorf("KLoad = %.2f, want 1.0 (ไม่มีข้อมูล 1RM)", result.KLoad)
	}
	if !almostEqual(result.FinalMET, 4.009091, 0.001) {
		t.Errorf("FinalMET = %.6f, want ~4.009091", result.FinalMET)
	}
	if !almostEqual(result.TotalCalories, 165.5, 0.5) {
		t.Errorf("TotalCalories = %.2f, want ~165.5", result.TotalCalories)
	}
}

// พักนานกว่าปกติ (อู้/ลืมกดจบ) งานเท่าเดิมทุกอย่าง ต้องได้แคลอรี่เท่ากัน — แก้บั๊กที่พบใน
// สเปกตั้งต้น (multiplier ขั้นบันไดสู้เวลาไม่จำกัดไม่ไหว ได้แคลอรี่ต่างกัน 2 เท่าทั้งที่งานเท่ากัน)
func TestCalculateWeightTrainingCalories_DurationCapPreventsInflation(t *testing.T) {
	sets := make([]SetLog, 11)
	for i := range sets {
		sets[i] = SetLog{BaseMET: 3.0, WeightKg: 10, Reps: 15}
	}

	fast := CalculateWeightTrainingCalories(75, 45*60, 0, sets)
	slow := CalculateWeightTrainingCalories(75, 90*60, 0, sets)

	if !almostEqual(fast.TotalCalories, slow.TotalCalories, 0.01) {
		t.Errorf("45 นาที (%.2f kcal) กับ 90 นาที (%.2f kcal) งานเท่ากันต้องได้แคลอรี่เท่ากัน (ทั้งคู่ถูกเพดานที่ 11×4=44 นาที)",
			fast.TotalCalories, slow.TotalCalories)
	}
}

// %1RM สูง (ยกหนัก) ต้องได้ kLoad สูงกว่ายกเบา เมื่อทุกอย่างอื่นเท่ากัน
func TestCalculateWeightTrainingCalories_LoadIntensityFromOneRepMax(t *testing.T) {
	oneRepMax := 100.0

	light := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, []SetLog{
		{BaseMET: 4.5, WeightKg: 40, Reps: 10}, // RI=0.40 -> เบา
	})
	heavy := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, []SetLog{
		{BaseMET: 4.5, WeightKg: 80, Reps: 5}, // RI=0.80 -> หนัก
	})

	if light.KLoad != 0.90 || light.IntensityLevel != 1 {
		t.Errorf("light: KLoad=%.2f IntensityLevel=%d, want 0.90/1", light.KLoad, light.IntensityLevel)
	}
	if heavy.KLoad != 1.10 || heavy.IntensityLevel != 3 {
		t.Errorf("heavy: KLoad=%.2f IntensityLevel=%d, want 1.10/3", heavy.KLoad, heavy.IntensityLevel)
	}
	if heavy.TotalCalories <= light.TotalCalories {
		t.Errorf("ยกหนักกว่าต้องเผาผลาญมากกว่า: heavy=%.2f, light=%.2f", heavy.TotalCalories, light.TotalCalories)
	}
}

// ท่า bodyweight (weight=0) หรือไม่มีประวัติ 1RM → kLoad ต้อง fallback เป็นกลาง ไม่ error/ไม่หารด้วยศูนย์
func TestCalculateWeightTrainingCalories_NoOneRepMaxFallsBackToMedium(t *testing.T) {
	result := CalculateWeightTrainingCalories(70, 5*60, 0, []SetLog{
		{BaseMET: 3.0, WeightKg: 0, Reps: 20}, // Plank-style bodyweight
	})
	if result.KLoad != 1.0 || result.IntensityLevel != 2 {
		t.Errorf("KLoad=%.2f IntensityLevel=%d, want 1.0/2 (ไม่มี 1RM ต้องถือเป็นกลาง)", result.KLoad, result.IntensityLevel)
	}
}

// เซตที่ reps=0 (ไม่สมบูรณ์) ต้องถูกกรองทิ้งก่อนคำนวณ ไม่นับรวมในตัวหาร
func TestCalculateWeightTrainingCalories_FiltersZeroRepSets(t *testing.T) {
	withInvalid := CalculateWeightTrainingCalories(75, 10*60, 0, []SetLog{
		{BaseMET: 5.5, WeightKg: 100, Reps: 5},
		{BaseMET: 5.5, WeightKg: 100, Reps: 0}, // เซตไม่สมบูรณ์ ต้องถูกข้าม
	})
	onlyValid := CalculateWeightTrainingCalories(75, 10*60, 0, []SetLog{
		{BaseMET: 5.5, WeightKg: 100, Reps: 5},
	})
	if !almostEqual(withInvalid.TotalCalories, onlyValid.TotalCalories, 0.001) {
		t.Errorf("ผลลัพธ์ต้องเหมือนกันไม่ว่าจะมีเซต reps=0 ปนมาหรือไม่: with=%.4f, only=%.4f",
			withInvalid.TotalCalories, onlyValid.TotalCalories)
	}
}

// อินพุตว่างเปล่า (ไม่มีเซตที่สมบูรณ์เลย) ต้องคืนค่าศูนย์ ไม่ panic (หารด้วยศูนย์)
func TestCalculateWeightTrainingCalories_EmptySets(t *testing.T) {
	result := CalculateWeightTrainingCalories(75, 600, 0, []SetLog{})
	if result.TotalCalories != 0 {
		t.Errorf("TotalCalories = %.2f, want 0", result.TotalCalories)
	}
	resultAllInvalid := CalculateWeightTrainingCalories(75, 600, 0, []SetLog{{BaseMET: 5.5, WeightKg: 10, Reps: 0}})
	if resultAllInvalid.TotalCalories != 0 {
		t.Errorf("TotalCalories = %.2f, want 0 (ทุกเซต reps=0)", resultAllInvalid.TotalCalories)
	}
}

// Final MET ต้องไม่หลุดขอบ [1.5, 9.5] แม้อินพุตสุดโต่ง (full-body 7.0 + หนัก 1.10 + เร็ว 1.20)
func TestCalculateWeightTrainingCalories_ClampsFinalMET(t *testing.T) {
	result := CalculateWeightTrainingCalories(75, 60, 100, []SetLog{
		{BaseMET: 7.0, WeightKg: 90, Reps: 3}, // RI=0.90 หนัก, 1 เซตใน 1 นาที = density ต่ำสุด
	})
	if result.FinalMET > WeightTrainingMETCeil {
		t.Errorf("FinalMET = %.4f ต้องไม่เกินเพดาน %.1f", result.FinalMET, WeightTrainingMETCeil)
	}
}

package services

import (
	"math"
	"testing"
)

func almostEqual(a, b, tolerance float64) bool {
	return math.Abs(a-b) <= tolerance
}

func intPtr(v int) *int {
	return &v
}

// ─────────────────────────────────────────────────────────────────────────
// resolveSetBaseMET — ตาราง Dynamic Base MET (Step 1), ทั้ง 5 โซน
// ─────────────────────────────────────────────────────────────────────────

func TestResolveSetBaseMET(t *testing.T) {
	cases := []struct {
		name        string
		reps        int
		restSeconds float64
		want        float64
	}{
		{"พัก < 30 วิ, reps ใดๆ → 8.0", 20, 15, 8.0},
		{"พัก 30-60 วิ (ไม่รวม 60), reps ใดๆ → 4.3", 3, 45, 4.3},
		{"พัก = 60 วิพอดี ตกไปโซน ≥60 ไม่ใช่ 30-60", 12, 60, 3.5},
		{"พัก ≥60 วิ, reps < 8 → 6.0", 5, 90, 6.0},
		{"พัก ≥60 วิ, reps 8-15 → 3.5 (02054 ตามสเปก)", 12, 75, 3.5},
		{"พัก ≥60 วิ, reps > 15 → 3.5 (ส่วนขยาย ไม่มี entry ตรง)", 20, 75, 3.5},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveSetBaseMET(tc.reps, tc.restSeconds)
			if got != tc.want {
				t.Errorf("resolveSetBaseMET(%d, %.0f) = %.2f, want %.2f", tc.reps, tc.restSeconds, got, tc.want)
			}
		})
	}
}

// ─────────────────────────────────────────────────────────────────────────
// CalculateWeightTrainingCalories — ใช้ RestSeconds จริงต่อเซตเมื่อมี
// ─────────────────────────────────────────────────────────────────────────

// ทุกเซตส่ง RestSeconds จริงมาครบ (ไม่ใช้ proxy เลย) — เทียบค่าที่คำนวณมือ
// พัก 20วิ→8.0(1เซต), พัก 45วิ→4.3(1เซต), พัก 75วิ reps=12→3.5(1เซต)
// sessionBaseMET = (8.0+4.3+3.5)/3 = 5.2666...
// duration=3*60=180s=3min, cap=min(3, 3*4=12)=3min, density=3/3=1.0 -> kDensity=1.20 (density<=1.0)
// oneRepMax=0 -> kLoad=1.0
// finalMET = 5.2666...*1.0*1.20 = 6.32
// effectiveHours = 3/60 = 0.05
// Kcal = (6.32-1)*70*0.05 = 5.32*3.5 = 18.62
func TestCalculateWeightTrainingCalories_UsesRealRestSecondsWhenProvided(t *testing.T) {
	sets := []SetLog{
		{WeightKg: 40, Reps: 10, RestSeconds: intPtr(20)}, // พัก<30 -> 8.0
		{WeightKg: 40, Reps: 3, RestSeconds: intPtr(45)},  // พัก 30-60 -> 4.3
		{WeightKg: 40, Reps: 12, RestSeconds: intPtr(75)}, // พัก>=60, reps 8-15 -> 3.5
	}
	result := CalculateWeightTrainingCalories(70, 180, 0, sets)

	wantSessionBaseMET := (8.0 + 4.3 + 3.5) / 3.0
	if !almostEqual(result.SessionBaseMET, wantSessionBaseMET, 0.0001) {
		t.Errorf("SessionBaseMET = %.4f, want %.4f", result.SessionBaseMET, wantSessionBaseMET)
	}
	if !almostEqual(result.KDensity, 1.20, 0.0001) {
		t.Errorf("KDensity = %.4f, want 1.20 (density=1.0)", result.KDensity)
	}
	if !almostEqual(result.TotalCalories, 18.62, 0.05) {
		t.Errorf("TotalCalories = %.2f, want ~18.62", result.TotalCalories)
	}
}

// ไม่มี RestSeconds เลย (มือถือยังไม่ส่ง, กรณีปกติตอนนี้) → ต้อง fallback เป็น proxy ความหนาแน่น
// เฉลี่ยทั้งเซสชัน (cappedMinutes/totalSets แปลงเป็นวินาที) เท่ากันทุกเซต
// 11 เซต, 60 นาที: cappedMinutes=min(60,11*4=44)=44, density=44/11=4.0min/set=240วิ/เซต (>=60 เสมอ)
// reps: 4 เซต reps=5 (<8 -> 6.0), 4 เซต reps=8 (8-15 -> 3.5), 3 เซต reps=12 (8-15 -> 3.5)
// sumBaseMET = 4*6.0 + 4*3.5 + 3*3.5 = 24+14+10.5 = 48.5, sessionBaseMET = 48.5/11 = 4.409090909
// kDensity: density=4.0 >= 3.0 -> 0.90; kLoad=1.0 (ไม่มี 1RM)
// finalMET = 4.409090909*1.0*0.90 = 3.968181818
// Kcal = (3.968181818-1)*75*(44/60) = 2.968181818*55 = 163.25
func TestCalculateWeightTrainingCalories_FallsBackToDensityProxyWhenRestSecondsMissing(t *testing.T) {
	sets := []SetLog{}
	for i := 0; i < 4; i++ {
		sets = append(sets, SetLog{WeightKg: 100, Reps: 5}) // RestSeconds = nil
	}
	for i := 0; i < 4; i++ {
		sets = append(sets, SetLog{WeightKg: 60, Reps: 8})
	}
	for i := 0; i < 3; i++ {
		sets = append(sets, SetLog{WeightKg: 15, Reps: 12})
	}

	result := CalculateWeightTrainingCalories(75, 60*60, 0, sets)

	if !almostEqual(result.SessionBaseMET, 4.409091, 0.001) {
		t.Errorf("SessionBaseMET = %.6f, want ~4.409091", result.SessionBaseMET)
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
	if !almostEqual(result.FinalMET, 3.968182, 0.001) {
		t.Errorf("FinalMET = %.6f, want ~3.968182", result.FinalMET)
	}
	if !almostEqual(result.TotalCalories, 163.25, 0.5) {
		t.Errorf("TotalCalories = %.2f, want ~163.25", result.TotalCalories)
	}
}

// พักนานกว่าปกติ (อู้/ลืมกดจบ) งานเท่าเดิมทุกอย่าง ต้องได้พลังงานเท่ากัน (เพดานเวลากันไว้) — ไม่มี
// RestSeconds ต่อเซต ใช้ proxy ทั้งคู่ ซึ่งถูกเพดานที่ 44 นาทีเท่ากันแล้วไม่ว่าจะพักจริงกี่นาที
func TestCalculateWeightTrainingCalories_DurationCapPreventsInflation(t *testing.T) {
	sets := make([]SetLog, 11)
	for i := range sets {
		sets[i] = SetLog{WeightKg: 10, Reps: 15}
	}

	fast := CalculateWeightTrainingCalories(75, 45*60, 0, sets)
	slow := CalculateWeightTrainingCalories(75, 90*60, 0, sets)

	if !almostEqual(fast.TotalCalories, slow.TotalCalories, 0.01) {
		t.Errorf("45 นาที (%.2f kcal) กับ 90 นาที (%.2f kcal) งานเท่ากันต้องได้พลังงานเท่ากัน (ทั้งคู่ถูกเพดานที่ 11×4=44 นาที)",
			fast.TotalCalories, slow.TotalCalories)
	}
}

// %1RM สูง (ยกหนัก) ต้องได้ kLoad สูงกว่ายกเบา เมื่อทุกอย่างอื่นเท่ากัน
func TestCalculateWeightTrainingCalories_LoadIntensityFromOneRepMax(t *testing.T) {
	oneRepMax := 100.0

	light := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, []SetLog{
		{WeightKg: 40, Reps: 10}, // RI=0.40 -> เบา
	})
	heavy := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, []SetLog{
		{WeightKg: 80, Reps: 5}, // RI=0.80 -> หนัก
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
		{WeightKg: 0, Reps: 20}, // Push-up ทั่วไป
	})
	if result.KLoad != 1.0 || result.IntensityLevel != 2 {
		t.Errorf("KLoad=%.2f IntensityLevel=%d, want 1.0/2 (ไม่มี 1RM ต้องถือเป็นกลาง)", result.KLoad, result.IntensityLevel)
	}
}

// เซตที่ reps=0 (ไม่สมบูรณ์) ต้องถูกกรองทิ้งก่อนคำนวณ ไม่นับรวมในตัวหาร
func TestCalculateWeightTrainingCalories_FiltersZeroRepSets(t *testing.T) {
	withInvalid := CalculateWeightTrainingCalories(75, 10*60, 0, []SetLog{
		{WeightKg: 100, Reps: 5},
		{WeightKg: 100, Reps: 0}, // เซตไม่สมบูรณ์ ต้องถูกข้าม
	})
	onlyValid := CalculateWeightTrainingCalories(75, 10*60, 0, []SetLog{
		{WeightKg: 100, Reps: 5},
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
	resultAllInvalid := CalculateWeightTrainingCalories(75, 600, 0, []SetLog{{WeightKg: 10, Reps: 0}})
	if resultAllInvalid.TotalCalories != 0 {
		t.Errorf("TotalCalories = %.2f, want 0 (ทุกเซต reps=0)", resultAllInvalid.TotalCalories)
	}
}

// Final MET ต้องไม่หลุดขอบ [1.5, 9.5] แม้อินพุตสุดโต่ง (พัก<30 -> 8.0 + หนัก 1.10 + เร็ว 1.20)
func TestCalculateWeightTrainingCalories_ClampsFinalMET(t *testing.T) {
	result := CalculateWeightTrainingCalories(75, 60, 100, []SetLog{
		{WeightKg: 90, Reps: 3, RestSeconds: intPtr(10)}, // RI=0.90 หนัก, พัก<30 -> BaseMET 8.0 สูงสุด
	})
	if result.FinalMET > WeightTrainingMETCeil {
		t.Errorf("FinalMET = %.4f ต้องไม่เกินเพดาน %.1f", result.FinalMET, WeightTrainingMETCeil)
	}
}

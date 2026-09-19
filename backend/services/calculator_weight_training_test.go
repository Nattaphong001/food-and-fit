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

// โปรไฟล์ท่าฝึกสำหรับเทสต์ — ค่าตรงกับ Data Dictionary (wet_equipment / wet_exercise_type)
var (
	barbellCompound  = ExerciseProfile{Equipment: 1, ExerciseType: ExerciseTypeCompound}  // เช่น Squat
	dumbbellIsolated = ExerciseProfile{Equipment: 2, ExerciseType: ExerciseTypeIsolation} // เช่น Bicep Curl
	bodyweightCompnd = ExerciseProfile{Equipment: 5, ExerciseType: ExerciseTypeCompound}  // เช่น Pull-up
	bodyweightIsoltd = ExerciseProfile{Equipment: 5, ExerciseType: ExerciseTypeIsolation} // เช่น Crunch
)

// ─────────────────────────────────────────────────────────────────────────
// resolveSetBaseMET — Dynamic METs Logic Matrix ทั้ง 7 ค่า + ขอบเขตของทุกเงื่อนไข
// ─────────────────────────────────────────────────────────────────────────

func TestResolveSetBaseMET_Resistance(t *testing.T) {
	cases := []struct {
		name        string
		profile     ExerciseProfile
		reps        int
		restSeconds float64
		want        float64
	}{
		{"Reps 7 (< 8) → หนัก 6.0", barbellCompound, 7, 120, 6.0},
		{"Reps 1 → หนัก 6.0 แม้ท่า Isolation", dumbbellIsolated, 1, 120, 6.0},
		{"Reps 8 พอดี ไม่ใช่หนัก + Compound → 5.0", barbellCompound, 8, 120, 5.0},
		{"Compound พักนาน 5 นาที → ปานกลาง 5.0 (Compound ชนะพักนาน)", barbellCompound, 10, 300, 5.0},
		{"Isolation พัก 60 พอดี (รวมปลาย) → 5.0", dumbbellIsolated, 10, 60, 5.0},
		{"Isolation พัก 90 พอดี (รวมปลาย) → 5.0", dumbbellIsolated, 10, 90, 5.0},
		{"Isolation พัก 59.9 → เบา 3.5", dumbbellIsolated, 10, 59.9, 3.5},
		{"Isolation พัก 90.1 → เบา 3.5", dumbbellIsolated, 10, 90.1, 3.5},
		{"Isolation พักสั้น 20 วิ ไม่ได้ถูกจัดเป็นหนัก → เบา 3.5", dumbbellIsolated, 12, 20, 3.5},
		{"Isolation พักนาน 3 นาที → เบา 3.5", dumbbellIsolated, 12, 180, 3.5},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveSetBaseMET(tc.profile, tc.reps, tc.restSeconds)
			if got != tc.want {
				t.Errorf("resolveSetBaseMET(%+v, reps=%d, rest=%.1f) = %.2f, want %.2f", tc.profile, tc.reps, tc.restSeconds, got, tc.want)
			}
		})
	}
}

func TestResolveSetBaseMET_Bodyweight(t *testing.T) {
	cases := []struct {
		name        string
		profile     ExerciseProfile
		reps        int
		restSeconds float64
		want        float64
	}{
		{"Isolation (Crunch) → 2.8 ไม่ว่าพักเท่าไหร่ (พักสั้น)", bodyweightIsoltd, 20, 10, 2.8},
		{"Isolation (Crunch) → 2.8 (พักนาน)", bodyweightIsoltd, 20, 300, 2.8},
		{"Compound พัก 29.9 → ต่อเนื่อง หนัก 8.0", bodyweightCompnd, 10, 29.9, 8.0},
		{"Compound พัก 30 พอดี → ปานกลาง 3.8 (ไม่ใช่ 8.0)", bodyweightCompnd, 10, 30, 3.8},
		{"Compound พัก 90 พอดี (รวมปลาย) → 3.8", bodyweightCompnd, 10, 90, 3.8},
		{"Compound พัก 90.1 → เบา 3.5", bodyweightCompnd, 10, 90.1, 3.5},
		{"Reps น้อย (3) ในหมวดบอดี้เวท ไม่ถูกจัดเป็นหนัก 6.0 (เกณฑ์ Reps ใช้เฉพาะหมวดแรงต้าน)", bodyweightCompnd, 3, 60, 3.8},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveSetBaseMET(tc.profile, tc.reps, tc.restSeconds)
			if got != tc.want {
				t.Errorf("resolveSetBaseMET(%+v, reps=%d, rest=%.1f) = %.2f, want %.2f", tc.profile, tc.reps, tc.restSeconds, got, tc.want)
			}
		})
	}
}

// ─────────────────────────────────────────────────────────────────────────
// CalculateWeightTrainingCalories
// ─────────────────────────────────────────────────────────────────────────

// ทุกเซตส่ง RestSeconds จริงมาครบ (ไม่ใช้ proxy) — เทียบค่าที่คำนวณมือ
// ท่า Isolation แรงต้าน: เซต1 Reps 5 → 6.0 · เซต2 Reps 10 พัก 75 → 5.0 · เซต3 Reps 12 พัก 120 → 3.5
// Session MET = (6.0+5.0+3.5)/3 = 4.8333... = Final MET
// duration=180s=3min, cap=min(3, 3*4=12)=3min
// Kcal = (4.8333-1)*3.5*70/200*3 = 3.8333*1.225*3 = 14.0875
func TestCalculateWeightTrainingCalories_UsesRealRestSecondsAndAveragesPerSet(t *testing.T) {
	sets := []SetLog{
		{WeightKg: 40, Reps: 5, RestSeconds: intPtr(120)},
		{WeightKg: 30, Reps: 10, RestSeconds: intPtr(75)},
		{WeightKg: 20, Reps: 12, RestSeconds: intPtr(120)},
	}
	result := CalculateWeightTrainingCalories(70, 180, 0, dumbbellIsolated, sets)

	wantMET := (6.0 + 5.0 + 3.5) / 3.0
	if !almostEqual(result.SessionBaseMET, wantMET, 0.0001) {
		t.Errorf("SessionBaseMET = %.4f, want %.4f", result.SessionBaseMET, wantMET)
	}
	if !almostEqual(result.FinalMET, wantMET, 0.0001) {
		t.Errorf("FinalMET = %.4f, want %.4f (= SessionBaseMET ตรงๆ)", result.FinalMET, wantMET)
	}
	if !almostEqual(result.TotalCalories, 14.0875, 0.01) {
		t.Errorf("TotalCalories = %.4f, want ~14.0875", result.TotalCalories)
	}
}

// ตัวอย่างจากแผน: 70 กก. 10 เซต × 10 ครั้ง พัก 90 วินาที รวม 40 นาที (ไม่ชนเพดาน 10×4=40)
//   - Squat (Compound แรงต้าน)  → 5.0 → (5.0-1)*3.5*70/200*40 = 196.0
//   - Bicep Curl (Isolation พัก 90 อยู่ในช่วง 60–90) → 5.0 → 196.0
//   - Pull-up (บอดี้เวท พัก 90) → 3.8 → (3.8-1)*1.225*40 = 137.2
//   - Crunch (บอดี้เวท Isolation) → 2.8 → (2.8-1)*1.225*40 = 88.2
func TestCalculateWeightTrainingCalories_WorkedExamples(t *testing.T) {
	makeSets := func() []SetLog {
		sets := make([]SetLog, 10)
		for i := range sets {
			sets[i] = SetLog{WeightKg: 50, Reps: 10, RestSeconds: intPtr(90)}
		}
		return sets
	}
	cases := []struct {
		name    string
		profile ExerciseProfile
		wantMET float64
		wantKc  float64
	}{
		{"Squat Compound", barbellCompound, 5.0, 196.0},
		{"Bicep Curl Isolation พัก 90", dumbbellIsolated, 5.0, 196.0},
		{"Pull-up บอดี้เวท", bodyweightCompnd, 3.8, 137.2},
		{"Crunch บอดี้เวท Isolation", bodyweightIsoltd, 2.8, 88.2},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result := CalculateWeightTrainingCalories(70, 40*60, 0, tc.profile, makeSets())
			if !almostEqual(result.FinalMET, tc.wantMET, 0.0001) {
				t.Errorf("FinalMET = %.4f, want %.1f", result.FinalMET, tc.wantMET)
			}
			if !almostEqual(result.TotalCalories, tc.wantKc, 0.01) {
				t.Errorf("TotalCalories = %.4f, want %.1f", result.TotalCalories, tc.wantKc)
			}
			if !almostEqual(result.CaloriesPerSet*10, result.TotalCalories, 0.0001) {
				t.Errorf("CaloriesPerSet×10 = %.4f ต้องเท่า TotalCalories %.4f", result.CaloriesPerSet*10, result.TotalCalories)
			}
		})
	}
}

// ไม่มี RestSeconds เลย (แถวเก่าก่อน 2026-09-18) → fallback เป็น proxy ความหนาแน่นเฉลี่ยทั้งเซสชัน
// 4 เซต, 4 นาที (240s): cappedMinutes=min(4, 4*4=16)=4, density=1.0 นาที/เซต = 60 วิ/เซต
// ท่า Isolation แรงต้าน Reps 10: proxy 60 วิ อยู่ในช่วง 60–90 → 5.0 ทุกเซต
// Kcal = (5.0-1)*3.5*75/200*4 = 4*1.3125*4 = 21.0
func TestCalculateWeightTrainingCalories_FallsBackToDensityProxyWhenRestSecondsMissing(t *testing.T) {
	sets := make([]SetLog, 4)
	for i := range sets {
		sets[i] = SetLog{WeightKg: 20, Reps: 10} // RestSeconds = nil
	}
	result := CalculateWeightTrainingCalories(75, 4*60, 0, dumbbellIsolated, sets)

	if !almostEqual(result.FinalMET, 5.0, 0.0001) {
		t.Errorf("FinalMET = %.4f, want 5.0 (proxy 60 วิ ตกช่วง 60–90)", result.FinalMET)
	}
	if !almostEqual(result.TotalCalories, 21.0, 0.01) {
		t.Errorf("TotalCalories = %.4f, want 21.0", result.TotalCalories)
	}
}

// พักนานกว่าปกติ (อู้/ลืมกดจบ) งานเท่าเดิม ต้องได้พลังงานเท่ากัน — ไม่มี RestSeconds ต่อเซต ใช้ proxy
// ทั้งคู่ ซึ่งถูกเพดาน 44 นาที (11×4) เท่ากันแล้วไม่ว่าจะพักจริงกี่นาที Compound Reps 15 → 5.0 ทั้งคู่
func TestCalculateWeightTrainingCalories_DurationCapPreventsInflation(t *testing.T) {
	sets := make([]SetLog, 11)
	for i := range sets {
		sets[i] = SetLog{WeightKg: 10, Reps: 15}
	}

	fast := CalculateWeightTrainingCalories(75, 45*60, 0, barbellCompound, sets)
	slow := CalculateWeightTrainingCalories(75, 90*60, 0, barbellCompound, sets)

	if !almostEqual(fast.EffectiveMinutes, 44.0, 0.01) || !almostEqual(slow.EffectiveMinutes, 44.0, 0.01) {
		t.Errorf("EffectiveMinutes fast=%.2f slow=%.2f ต้องถูกเพดานที่ 44 นาที (11 เซต × 4 นาที)", fast.EffectiveMinutes, slow.EffectiveMinutes)
	}
	if !almostEqual(fast.TotalCalories, slow.TotalCalories, 0.01) {
		t.Errorf("45 นาที (%.2f kcal) กับ 90 นาที (%.2f kcal) งานเท่ากันต้องได้พลังงานเท่ากัน", fast.TotalCalories, slow.TotalCalories)
	}
}

// %1RM ไม่มีผลต่อการเลือก MET/พลังงาน (Logic Matrix ไม่อิงน้ำหนักที่ยก) — แต่ IntensityLevel (label
// แสดงผล) ยังต้องต่างกันตาม %1RM: ยกเบา RI=0.40 → 1, ยกหนัก RI=0.80 → 3
func TestCalculateWeightTrainingCalories_IntensityLevelIsDisplayOnly(t *testing.T) {
	oneRepMax := 100.0

	light := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, barbellCompound, []SetLog{
		{WeightKg: 40, Reps: 10, RestSeconds: intPtr(75)},
	})
	heavy := CalculateWeightTrainingCalories(75, 10*60, oneRepMax, barbellCompound, []SetLog{
		{WeightKg: 80, Reps: 10, RestSeconds: intPtr(75)},
	})

	if light.IntensityLevel != 1 {
		t.Errorf("light: IntensityLevel=%d, want 1", light.IntensityLevel)
	}
	if heavy.IntensityLevel != 3 {
		t.Errorf("heavy: IntensityLevel=%d, want 3", heavy.IntensityLevel)
	}
	if !almostEqual(light.FinalMET, heavy.FinalMET, 0.0001) {
		t.Errorf("FinalMET ต้องเท่ากัน (น้ำหนักที่ยกไม่มีผลต่อ MET): light=%.4f heavy=%.4f", light.FinalMET, heavy.FinalMET)
	}
	if !almostEqual(light.TotalCalories, heavy.TotalCalories, 0.001) {
		t.Errorf("TotalCalories ต้องเท่ากัน: light=%.2f heavy=%.2f", light.TotalCalories, heavy.TotalCalories)
	}
}

// ท่า bodyweight (weight=0) หรือไม่มีประวัติ 1RM → IntensityLevel fallback เป็นกลาง ไม่ error/ไม่หารด้วยศูนย์
func TestCalculateWeightTrainingCalories_NoOneRepMaxFallsBackToMedium(t *testing.T) {
	result := CalculateWeightTrainingCalories(70, 5*60, 0, bodyweightCompnd, []SetLog{
		{WeightKg: 0, Reps: 20},
	})
	if result.IntensityLevel != 2 {
		t.Errorf("IntensityLevel=%d, want 2 (ไม่มี 1RM ต้องถือเป็นกลาง)", result.IntensityLevel)
	}
}

// เซตที่ reps=0 (ไม่สมบูรณ์) ต้องถูกกรองทิ้งก่อนคำนวณ ไม่นับรวมในตัวหาร
func TestCalculateWeightTrainingCalories_FiltersZeroRepSets(t *testing.T) {
	withInvalid := CalculateWeightTrainingCalories(75, 10*60, 0, barbellCompound, []SetLog{
		{WeightKg: 100, Reps: 5},
		{WeightKg: 100, Reps: 0}, // เซตไม่สมบูรณ์ ต้องถูกข้าม
	})
	onlyValid := CalculateWeightTrainingCalories(75, 10*60, 0, barbellCompound, []SetLog{
		{WeightKg: 100, Reps: 5},
	})
	if !almostEqual(withInvalid.TotalCalories, onlyValid.TotalCalories, 0.001) {
		t.Errorf("ผลลัพธ์ต้องเหมือนกันไม่ว่าจะมีเซต reps=0 ปนมาหรือไม่: with=%.4f, only=%.4f",
			withInvalid.TotalCalories, onlyValid.TotalCalories)
	}
}

// อินพุตว่างเปล่า (ไม่มีเซตที่สมบูรณ์เลย) ต้องคืนค่าศูนย์ ไม่ panic (หารด้วยศูนย์)
func TestCalculateWeightTrainingCalories_EmptySets(t *testing.T) {
	result := CalculateWeightTrainingCalories(75, 600, 0, barbellCompound, []SetLog{})
	if result.TotalCalories != 0 {
		t.Errorf("TotalCalories = %.2f, want 0", result.TotalCalories)
	}
	resultAllInvalid := CalculateWeightTrainingCalories(75, 600, 0, barbellCompound, []SetLog{{WeightKg: 10, Reps: 0}})
	if resultAllInvalid.TotalCalories != 0 {
		t.Errorf("TotalCalories = %.2f, want 0 (ทุกเซต reps=0)", resultAllInvalid.TotalCalories)
	}
}

// Final MET ต้องไม่หลุดขอบ [1.5, 9.5] — ค่าจาก Logic Matrix สูงสุด 8.0 ต่ำสุด 2.8 ไม่มีวันชนขอบ
// เทสต์นี้เป็น regression safety net เผื่อมีคนเพิ่มค่า/ตัวคูณในอนาคตแล้วลืมเช็คขอบ
func TestCalculateWeightTrainingCalories_FinalMETStaysWithinClampRange(t *testing.T) {
	profiles := []ExerciseProfile{barbellCompound, dumbbellIsolated, bodyweightCompnd, bodyweightIsoltd}
	for _, p := range profiles {
		for _, rest := range []int{0, 15, 45, 75, 120, 400} {
			for _, reps := range []int{1, 8, 30} {
				result := CalculateWeightTrainingCalories(75, 600, 100, p, []SetLog{
					{WeightKg: 50, Reps: reps, RestSeconds: intPtr(rest)},
				})
				if result.FinalMET < WeightTrainingMETFloor || result.FinalMET > WeightTrainingMETCeil {
					t.Errorf("profile=%+v reps=%d rest=%d: FinalMET=%.2f หลุดขอบ [%.1f, %.1f]",
						p, reps, rest, result.FinalMET, WeightTrainingMETFloor, WeightTrainingMETCeil)
				}
			}
		}
	}
}

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
// duration=180s=3min
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
// 4 เซต, 4 นาที (240s): ระยะเวลา=4 นาที, density=1.0 นาที/เซต = 60 วิ/เซต
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

// ไม่มีเพดานเวลา — ใช้เวลารวมตามที่รับมาตรงๆ: เวลา 2 เท่า (MET เท่ากัน) ต้องได้พลังงาน 2 เท่าพอดี
// ไม่มี RestSeconds ต่อเซต ใช้ proxy (เวลารวม ÷ เซต = 245 วิ และ 490 วิ) Compound → 5.0 ทั้งคู่
// ความสมเหตุสมผลของเวลาที่รับมาตรวจที่ชั้น controller ไม่ใช่ในสูตร
func TestCalculateWeightTrainingCalories_DurationHasNoCap(t *testing.T) {
	sets := make([]SetLog, 11)
	for i := range sets {
		sets[i] = SetLog{WeightKg: 10, Reps: 15}
	}

	short := CalculateWeightTrainingCalories(75, 45*60, 0, barbellCompound, sets)
	long := CalculateWeightTrainingCalories(75, 90*60, 0, barbellCompound, sets)

	if !almostEqual(short.DurationMinutes, 45.0, 0.0001) || !almostEqual(long.DurationMinutes, 90.0, 0.0001) {
		t.Errorf("DurationMinutes short=%.2f long=%.2f ต้องเท่าเวลาจริง 45 และ 90 นาที (ไม่มีเพดาน)", short.DurationMinutes, long.DurationMinutes)
	}
	if !almostEqual(short.FinalMET, 5.0, 0.0001) || !almostEqual(long.FinalMET, 5.0, 0.0001) {
		t.Errorf("FinalMET short=%.2f long=%.2f want 5.0 ทั้งคู่", short.FinalMET, long.FinalMET)
	}
	if !almostEqual(long.TotalCalories, 2*short.TotalCalories, 0.001) {
		t.Errorf("90 นาที (%.2f kcal) ต้องเป็น 2 เท่าของ 45 นาที (%.2f kcal)", long.TotalCalories, short.TotalCalories)
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

// ─────────────────────────────────────────────────────────────────────────
// ตารางทดสอบปลายทาง (end-to-end ของ CalculateWeightTrainingCalories) — ชุดข้อมูลเดียวกับที่ใช้ทดสอบมือ
// ตั้งค่ากลาง: น้ำหนักตัว 70 กก., 3 เซต, เวลารวม 540 วินาที (ระยะเวลา = 9 นาที)
// จึงได้ Kcal = (MET−1) × 3.5 × 70 / 200 × 9 = (MET−1) × 11.025 — ค่า want ด้านล่างมาจากการรันฟังก์ชันจริง
// แล้วเทียบสูตรมือ ไม่ได้คัดลอกจากผลของฟังก์ชันอย่างเดียว
// ─────────────────────────────────────────────────────────────────────────

// setsOf สร้างเซตที่ Reps/พัก เท่ากันทุกเซต (rest < 0 = RestSeconds เป็น nil)
func setsOf(n, reps, rest int) []SetLog {
	sets := make([]SetLog, n)
	for i := range sets {
		sets[i] = SetLog{Reps: reps}
		if rest >= 0 {
			sets[i].RestSeconds = intPtr(rest)
		}
	}
	return sets
}

func TestCalculateWeightTrainingCalories_LogicMatrixEndToEnd(t *testing.T) {
	cases := []struct {
		name     string
		profile  ExerciseProfile
		reps     int
		rest     int
		wantMET  float64
		wantKcal float64
	}{
		// หมวดแรงต้าน
		{"R1 Reps 5 Iso พัก 120 → หนัก", dumbbellIsolated, 5, 120, 6.0, 55.125},
		{"R2 Reps 7 (ขอบ) Iso พัก 120 → หนัก", dumbbellIsolated, 7, 120, 6.0, 55.125},
		{"R3 Reps 8 (ขอบ) Iso พัก 120 → เบา", dumbbellIsolated, 8, 120, 3.5, 27.5625},
		{"R4 Reps 10 Compound พัก 120 → ปานกลาง", barbellCompound, 10, 120, 5.0, 44.1},
		{"R5 Iso พัก 60 (ขอบล่าง) → ปานกลาง", dumbbellIsolated, 10, 60, 5.0, 44.1},
		{"R6 Iso พัก 90 (ขอบบน) → ปานกลาง", dumbbellIsolated, 10, 90, 5.0, 44.1},
		{"R7 Iso พัก 59 → เบา", dumbbellIsolated, 10, 59, 3.5, 27.5625},
		{"R8 Iso พัก 91 → เบา", dumbbellIsolated, 10, 91, 3.5, 27.5625},
		{"R9 Reps 5 Compound พัก 75 → ลำดับ: Reps<8 ชนะ", barbellCompound, 5, 75, 6.0, 55.125},
		{"R10 Reps 12 Iso พัก 30 → เบา", dumbbellIsolated, 12, 30, 3.5, 27.5625},
		{"R11 Reps 8 Compound พัก 0 → ปานกลาง", barbellCompound, 8, 0, 5.0, 44.1},
		// หมวดน้ำหนักตัว
		{"B1 Iso พัก 10 → 2.8", bodyweightIsoltd, 15, 10, 2.8, 19.845},
		{"B2 Iso พัก 120 → 2.8 (Isolation ชนะก่อนดูเวลาพัก)", bodyweightIsoltd, 15, 120, 2.8, 19.845},
		{"B3 Compound พัก 0 → หนัก", bodyweightCompnd, 15, 0, 8.0, 77.175},
		{"B4 Compound พัก 29 → หนัก", bodyweightCompnd, 15, 29, 8.0, 77.175},
		{"B5 Compound พัก 30 (ขอบ) → ปานกลาง", bodyweightCompnd, 15, 30, 3.8, 30.87},
		{"B6 Compound พัก 90 (ขอบ) → ปานกลาง", bodyweightCompnd, 15, 90, 3.8, 30.87},
		{"B7 Compound พัก 91 → เบา", bodyweightCompnd, 15, 91, 3.5, 27.5625},
		{"B8 Reps 3 พัก 120 → เบา (Reps ไม่มีผลในหมวดนี้)", bodyweightCompnd, 3, 120, 3.5, 27.5625},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateWeightTrainingCalories(70, 540, 0, tc.profile, setsOf(3, tc.reps, tc.rest))
			if !almostEqual(got.FinalMET, tc.wantMET, 0.0001) {
				t.Errorf("FinalMET = %.4f, want %.4f", got.FinalMET, tc.wantMET)
			}
			if !almostEqual(got.TotalCalories, tc.wantKcal, 0.001) {
				t.Errorf("TotalCalories = %.4f, want %.4f", got.TotalCalories, tc.wantKcal)
			}
			if !almostEqual(got.CaloriesPerSet*3, got.TotalCalories, 0.0001) {
				t.Errorf("CaloriesPerSet×3 = %.4f ต้องเท่ากับ TotalCalories %.4f (หารเท่ากันทุกเซต)", got.CaloriesPerSet*3, got.TotalCalories)
			}
		})
	}
}

// เซสชันที่ MET ต่างกันต่อเซต — Session MET ต้องเป็นค่าเฉลี่ยของ MET รายเซต
func TestCalculateWeightTrainingCalories_MixedSetsAverageMET(t *testing.T) {
	cases := []struct {
		name     string
		profile  ExerciseProfile
		sets     []SetLog
		wantMET  float64
		wantKcal float64
	}{
		{"M1 Compound Reps 5/10/10 พัก 120 → (6+5+5)/3", barbellCompound,
			[]SetLog{{Reps: 5, RestSeconds: intPtr(120)}, {Reps: 10, RestSeconds: intPtr(120)}, {Reps: 10, RestSeconds: intPtr(120)}},
			16.0 / 3.0, 47.775},
		{"M2 Iso Reps 10 พัก 30/75/120 → (3.5+5+3.5)/3", dumbbellIsolated,
			[]SetLog{{Reps: 10, RestSeconds: intPtr(30)}, {Reps: 10, RestSeconds: intPtr(75)}, {Reps: 10, RestSeconds: intPtr(120)}},
			4.0, 33.075},
		{"M3 น้ำหนักตัว Compound พัก 10/60/120 → (8+3.8+3.5)/3", bodyweightCompnd,
			[]SetLog{{Reps: 15, RestSeconds: intPtr(10)}, {Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15, RestSeconds: intPtr(120)}},
			15.3 / 3.0, 45.2025},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateWeightTrainingCalories(70, 540, 0, tc.profile, tc.sets)
			if !almostEqual(got.FinalMET, tc.wantMET, 0.0001) {
				t.Errorf("FinalMET = %.4f, want %.4f", got.FinalMET, tc.wantMET)
			}
			if !almostEqual(got.TotalCalories, tc.wantKcal, 0.001) {
				t.Errorf("TotalCalories = %.4f, want %.4f", got.TotalCalories, tc.wantKcal)
			}
		})
	}
}

// RestSeconds = nil → ใช้ความหนาแน่นเฉลี่ย (เวลารวม ÷ จำนวนเซต) แปลงเป็นวินาทีแทนเวลาพักต่อเซตนั้น
func TestCalculateWeightTrainingCalories_DensityProxyBoundaries(t *testing.T) {
	cases := []struct {
		name     string
		profile  ExerciseProfile
		sets     []SetLog
		duration int
		wantMET  float64
		wantMins float64
		wantKcal float64
	}{
		{"F1 แรงต้าน Iso 180 วิ/เซต → เบา", dumbbellIsolated, setsOf(3, 10, -1), 540, 3.5, 9, 27.5625},
		{"F2 แรงต้าน Iso 60 วิ/เซต → ปานกลาง", dumbbellIsolated, setsOf(3, 10, -1), 180, 5.0, 3, 14.7},
		{"F3 น้ำหนักตัว Compound 20 วิ/เซต → หนัก", bodyweightCompnd, setsOf(3, 15, -1), 60, 8.0, 1, 8.575},
		{"F4 น้ำหนักตัว Compound 60 วิ/เซต → ปานกลาง", bodyweightCompnd, setsOf(3, 15, -1), 180, 3.8, 3, 10.29},
		{"F5 ผสม: เซต 1 พัก 30 จริง เซต 2 เป็น nil (proxy 60 วิ)", bodyweightCompnd,
			[]SetLog{{Reps: 15, RestSeconds: intPtr(30)}, {Reps: 15}}, 120, 3.8, 2, 6.86},
		// ไม่มีพักจริง + เวลารวมยาวมาก → proxy = เวลารวมต่อเซตตรงๆ (1200 วิ) ไม่มีเพดาน, เวลา 60 นาทีเต็ม
		{"F6 ไม่มีเพดาน: 3 เซต 3600 วิ ไม่มีพักจริง → proxy 1200 วิ", dumbbellIsolated, setsOf(3, 10, -1), 3600, 3.5, 60, 183.75},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateWeightTrainingCalories(70, tc.duration, 0, tc.profile, tc.sets)
			if !almostEqual(got.FinalMET, tc.wantMET, 0.0001) {
				t.Errorf("FinalMET = %.4f, want %.4f", got.FinalMET, tc.wantMET)
			}
			if !almostEqual(got.DurationMinutes, tc.wantMins, 0.0001) {
				t.Errorf("DurationMinutes = %.4f, want %.4f", got.DurationMinutes, tc.wantMins)
			}
			if !almostEqual(got.TotalCalories, tc.wantKcal, 0.001) {
				t.Errorf("TotalCalories = %.4f, want %.4f", got.TotalCalories, tc.wantKcal)
			}
		})
	}
}

// ไม่มีเพดานเวลา: ระยะเวลาที่ใช้ = เวลารวม ÷ 60 ตรงๆ ไม่ว่าจะสั้นหรือยาวเท่าไหร่ (ตัวเลขเดิมที่เคยเป็นขอบเพดาน 720 วิ
// ต้องไม่มีผลอีกต่อไป)
func TestCalculateWeightTrainingCalories_DurationUsedAsIs(t *testing.T) {
	cases := []struct {
		name     string
		duration int
		wantMins float64
	}{
		{"719 วิ", 719, 719.0 / 60.0},
		{"720 วิ (ขอบเพดานเดิม 3 เซต × 4 นาที)", 720, 12.0},
		{"3600 วิ (เกินขอบเพดานเดิม)", 3600, 60.0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateWeightTrainingCalories(70, tc.duration, 0, dumbbellIsolated, setsOf(3, 10, 120))
			if !almostEqual(got.DurationMinutes, tc.wantMins, 0.0001) {
				t.Errorf("DurationMinutes = %.4f, want %.4f", got.DurationMinutes, tc.wantMins)
			}
		})
	}
}

// ขอบของ IntensityLevel (label แสดงผล): RI < 0.50 → 1 · 0.50 ≤ RI < 0.70 → 2 · RI ≥ 0.70 → 3
// และต้องไม่กระทบ Final MET/พลังงานเลย (เทียบกับเคสน้ำหนัก 0)
func TestCalculateWeightTrainingCalories_IntensityLevelBoundaries(t *testing.T) {
	const oneRepMax = 100.0
	baseline := CalculateWeightTrainingCalories(70, 180, oneRepMax, barbellCompound, []SetLog{{WeightKg: 0, Reps: 10, RestSeconds: intPtr(90)}})
	cases := []struct {
		weight float64
		want   int8
	}{
		{0, 2}, // ท่า bodyweight ไม่มี RI → กลาง
		{40, 1},
		{49.9, 1},
		{50, 2}, // ขอบ 0.50 นับเป็นกลาง
		{69.9, 2},
		{70, 3}, // ขอบ 0.70 นับเป็นหนัก
		{100, 3},
	}
	for _, tc := range cases {
		got := CalculateWeightTrainingCalories(70, 180, oneRepMax, barbellCompound, []SetLog{{WeightKg: tc.weight, Reps: 10, RestSeconds: intPtr(90)}})
		if got.IntensityLevel != tc.want {
			t.Errorf("weight=%.1f (RI=%.3f): IntensityLevel=%d, want %d", tc.weight, tc.weight/oneRepMax, got.IntensityLevel, tc.want)
		}
		if got.FinalMET != baseline.FinalMET || !almostEqual(got.TotalCalories, baseline.TotalCalories, 0.0001) {
			t.Errorf("weight=%.1f: MET/kcal ต้องไม่เปลี่ยนตามน้ำหนักที่ยก (got MET=%.2f kcal=%.4f)", tc.weight, got.FinalMET, got.TotalCalories)
		}
	}
	// เซตที่ weight=0 ปนกับเซตที่มีน้ำหนัก ต้องไม่ถูกนับใน RI เฉลี่ย (ไม่ดึงค่าลง)
	mixed := CalculateWeightTrainingCalories(70, 180, oneRepMax, barbellCompound, []SetLog{
		{WeightKg: 80, Reps: 10, RestSeconds: intPtr(90)},
		{WeightKg: 0, Reps: 10, RestSeconds: intPtr(90)},
	})
	if mixed.IntensityLevel != 3 {
		t.Errorf("เซต weight=0 ต้องไม่ถูกนับใน RI เฉลี่ย: IntensityLevel=%d, want 3", mixed.IntensityLevel)
	}
}

// พลังงานต้องเป็นเส้นตรงกับน้ำหนักตัว (ทดสอบมือบนบัญชีที่น้ำหนักไม่ใช่ 70 กก. คูณตามน้ำหนักได้เลย)
func TestCalculateWeightTrainingCalories_ScalesLinearlyWithBodyWeight(t *testing.T) {
	at70 := CalculateWeightTrainingCalories(70, 540, 0, barbellCompound, setsOf(3, 10, 120))
	at105 := CalculateWeightTrainingCalories(105, 540, 0, barbellCompound, setsOf(3, 10, 120))
	if !almostEqual(at105.TotalCalories, at70.TotalCalories*1.5, 0.0001) {
		t.Errorf("105 กก. = %.4f, want 70 กก. × 1.5 = %.4f", at105.TotalCalories, at70.TotalCalories*1.5)
	}
}

// เซตสุดท้ายไม่มีการพักจริง (ผู้ใช้กรอกเสร็จแล้วจบการฝึกเลย) มือถือส่ง RestSeconds = nil — เซตนั้นต้องใช้ค่าเฉลี่ย
// เวลาพักของเซตอื่นในเซสชัน ไม่ใช่ proxy ความหนาแน่น และไม่ดึง MET เฉลี่ยไปทางใดทางหนึ่ง เทียบสูตรมือที่ 70 กก. 9 นาที
// (kcal = (MET−1) × 1.225 × 9)
func TestCalculateWeightTrainingCalories_UnknownRestUsesMeanOfKnownRests(t *testing.T) {
	cases := []struct {
		name     string
		profile  ExerciseProfile
		sets     []SetLog
		duration int
		wantMET  float64
		wantKcal float64
	}{
		{"U1 น้ำหนักตัว Compound พัก 60,60,nil → เซตสุดท้ายใช้ 60 → ปานกลางทั้งหมด", bodyweightCompnd,
			[]SetLog{{Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15}}, 540, 3.8, 30.87},
		{"U2 น้ำหนักตัว Compound พัก 10,60,nil → เฉลี่ย 35 → หนัก+ปานกลาง+ปานกลาง", bodyweightCompnd,
			[]SetLog{{Reps: 15, RestSeconds: intPtr(10)}, {Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15}}, 540, (8.0 + 3.8 + 3.8) / 3, 46.305},
		{"U3 แรงต้าน Iso พัก 120,120,nil → เฉลี่ย 120 → เบาทั้งหมด", dumbbellIsolated,
			[]SetLog{{Reps: 10, RestSeconds: intPtr(120)}, {Reps: 10, RestSeconds: intPtr(120)}, {Reps: 10}}, 540, 3.5, 27.5625},
		{"U4 แรงต้าน Iso พัก 75,75,nil → เฉลี่ย 75 → ปานกลางทั้งหมด", dumbbellIsolated,
			[]SetLog{{Reps: 10, RestSeconds: intPtr(75)}, {Reps: 10, RestSeconds: intPtr(75)}, {Reps: 10}}, 540, 5.0, 44.1},
		{"U5 แรงต้าน เซตสุดท้าย Reps < 8 ยังเป็นหนัก ไม่ขึ้นกับเวลาพักที่ไม่ทราบ", dumbbellIsolated,
			[]SetLog{{Reps: 10, RestSeconds: intPtr(75)}, {Reps: 5}}, 360, (5.0 + 6.0) / 2, 33.075},
		{"U6 เซตเดียวและไม่ทราบพัก → ใช้ proxy ความหนาแน่น (120 วิ → เบา)", dumbbellIsolated,
			[]SetLog{{Reps: 10}}, 120, 3.5, 6.125},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := CalculateWeightTrainingCalories(70, tc.duration, 0, tc.profile, tc.sets)
			if !almostEqual(got.FinalMET, tc.wantMET, 0.0001) {
				t.Errorf("FinalMET = %.4f, want %.4f", got.FinalMET, tc.wantMET)
			}
			minutes := float64(tc.duration) / 60.0
			wantKcal := (tc.wantMET - 1) * 3.5 * 70 / 200 * minutes
			if !almostEqual(got.TotalCalories, wantKcal, 0.0001) {
				t.Errorf("TotalCalories = %.4f, want %.4f (สูตรมือ)", got.TotalCalories, wantKcal)
			}
			if !almostEqual(got.TotalCalories, tc.wantKcal, 0.01) {
				t.Errorf("TotalCalories = %.4f, want %.4f (ค่าที่คำนวณมือไว้ล่วงหน้า)", got.TotalCalories, tc.wantKcal)
			}
		})
	}

	// เซตสุดท้ายที่ nil ต้องให้ผลเท่ากับส่งค่าเฉลี่ยของเซตอื่นมาตรงๆ
	withNil := CalculateWeightTrainingCalories(70, 540, 0, bodyweightCompnd,
		[]SetLog{{Reps: 15, RestSeconds: intPtr(10)}, {Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15}})
	withMean := CalculateWeightTrainingCalories(70, 540, 0, bodyweightCompnd,
		[]SetLog{{Reps: 15, RestSeconds: intPtr(10)}, {Reps: 15, RestSeconds: intPtr(60)}, {Reps: 15, RestSeconds: intPtr(35)}})
	if !almostEqual(withNil.TotalCalories, withMean.TotalCalories, 0.0001) {
		t.Errorf("nil = %.4f แต่ส่งค่าเฉลี่ย 35 วิ = %.4f ต้องเท่ากัน", withNil.TotalCalories, withMean.TotalCalories)
	}
}

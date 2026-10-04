package services

// ทดสอบเวทเทรนนิ่งแบบครบเงื่อนไข (เสริม calculator_weight_training_test.go) — ตารางเงื่อนไขเทียบ oracle อิสระ,
// คุณสมบัติของสูตร (monotonic/linear), และช่องโหว่ที่ตรวจพบ 2026-10-04
// ชื่อขึ้นต้น TestVuln_ / TestLimitation_ = ล็อกพฤติกรรมปัจจุบันที่ผิด/เป็นข้อจำกัด ถ้าแก้แล้ว test จะล้ม → กลับ assertion

import (
	"math"
	"testing"
)

// oracleMets เขียนสเปกข้อ 7[B-1] ขั้นที่ 3 ใหม่แบบตรงตัว โดยเทียบ %1RM ด้วยเลขจำนวนเต็ม (เซนต์ของกก.) ไม่ใช้ทศนิยมลอยตัว
// weightCents/refCents = น้ำหนัก/1RM อ้างอิง × 100 (ทั้งคู่เก็บทศนิยม 2 ตำแหน่งใน DB)
func oracleMets(weightCents int, reps int, refCents int, hasWeight, hasReps bool) float64 {
	if !hasWeight || !hasReps || weightCents <= 0 {
		return 3.0
	}
	if reps > 20 || refCents <= 0 {
		return 3.5
	}
	pctNumerator := weightCents * 100 // เทียบ W/ref ≥ 70% ⇔ W×100 ≥ 70×ref
	if weightCents >= refCents {      // เกิน 100% ถือเป็น 100%
		return 6.0
	}
	if pctNumerator >= 70*refCents {
		return 6.0
	}
	return 3.5
}

// ตารางเงื่อนไขครบ: (hasWeight × hasReps) × น้ำหนัก × reps (ขอบ 1/20/21) × ตัวอ้างอิง เทียบ oracle
// ค่าที่เลือกเลี่ยงจุดตัด 70% พอดีที่ทศนิยมลอยตัวคลาดเคลื่อน (ดู TestVuln_WeightSetMets_FloatBoundary)
func TestWeightSetMets_FullConditionMatrix(t *testing.T) {
	weights := []int{-500, 0, 1, 6999, 7001, 10000, 15000} // เซนต์ของกก.
	refs := []int{-100, 0, 10000}
	repsList := []int{0, 1, 10, 20, 21, 100}
	for _, hw := range []bool{false, true} {
		for _, hr := range []bool{false, true} {
			for _, w := range weights {
				for _, r := range repsList {
					for _, ref := range refs {
						want := oracleMets(w, r, ref, hw, hr)
						got := WeightSetMets(float64(w)/100, r, float64(ref)/100, hw, hr)
						if got != want {
							t.Errorf("hasWeight=%v hasReps=%v w=%.2f reps=%d ref=%.2f: got %v want %v", hw, hr, float64(w)/100, r, float64(ref)/100, got, want)
						}
					}
				}
			}
		}
	}
}

// ผลลัพธ์ต้องเป็นหนึ่งใน 3.0 / 3.5 / 6.0 เท่านั้น และไม่ลดลงเมื่อน้ำหนักเพิ่ม (ตัวอ้างอิง/reps คงที่)
func TestWeightSetMets_MonotonicInWeight(t *testing.T) {
	for _, reps := range []int{1, 5, 10, 11, 20} {
		prev := 0.0
		for w := 0.5; w <= 300; w += 0.5 {
			got := WeightSetMets(w, reps, 100, true, true)
			if got != MetsEndurance && got != MetsHeavy {
				t.Fatalf("w=%v reps=%d: METs %v อยู่นอกชุดค่าที่กำหนด", w, reps, got)
			}
			if got < prev {
				t.Fatalf("w=%v reps=%d: METs ลดลงจาก %v เป็น %v เมื่อน้ำหนักเพิ่ม", w, reps, prev, got)
			}
			prev = got
		}
	}
}

// แก้แล้ว 2026-10-04 (เดิมช่องโหว่ V7): เทียบ %1RM ด้วย float64 (W / ref × 100) จุดตัด 70% พอดีบางคู่ได้ 69.999… ตกไป 3.5
// ทั้งที่สเปกให้ ≥ 70 = 6.0 เช่น 5.81 ÷ 8.30 — แก้ด้วย intensityEpsilon ใน WeightSetMets
// ค้นทั้งช่วงอ้างอิง 1.00-400.00 กก. (ทศนิยม 2 ตำแหน่ง) ทุกค่าต้องตรง oracle จำนวนเต็ม รวมจุด 70% พอดี
func TestWeightSetMets_ExactSeventyPercentBoundary(t *testing.T) {
	if got := WeightSetMets(5.81, 5, 8.30, true, true); got != MetsHeavy {
		t.Errorf("5.81/8.30 = 70%% พอดี: got %v, want %v", got, MetsHeavy)
	}
	mismatch, exact := 0, 0
	for ref := 100; ref <= 40000; ref++ {
		for _, w := range []int{70*ref/100 - 1, 70 * ref / 100, 70*ref/100 + 1, (70*ref + 99) / 100} {
			if w <= 0 {
				continue
			}
			if w*100 == 70*ref {
				exact++
			}
			want := oracleMets(w, 5, ref, true, true)
			if got := WeightSetMets(float64(w)/100, 5, float64(ref)/100, true, true); got != want {
				mismatch++
				if mismatch <= 5 {
					t.Errorf("w=%.2f ref=%.2f: got %v want %v", float64(w)/100, float64(ref)/100, got, want)
				}
			}
		}
	}
	if mismatch != 0 {
		t.Errorf("ผิด %d เคส", mismatch)
	}
	if exact == 0 {
		t.Fatalf("ไม่พบเคส 70%% พอดีเลย — test ไม่ได้ตรวจจุดตัด")
	}
}

// Dual-Formula: e1RM ต้องเพิ่มตามจำนวนครั้งภายในแต่ละช่วง (1-10 และ 11-20) และ reps 21+ ได้ 0
func TestEstimateOneRepMax_MonotonicWithinEachRange(t *testing.T) {
	for _, r := range [][2]int{{1, 10}, {11, 20}} {
		prev := 0.0
		for reps := r[0]; reps <= r[1]; reps++ {
			got := EstimateOneRepMax(100, reps)
			if got <= prev {
				t.Errorf("reps=%d: e1RM %v ไม่เพิ่มจาก %v", reps, got, prev)
			}
			prev = got
		}
	}
	if EstimateOneRepMax(100, 21) != 0 {
		t.Errorf("reps 21 ต้อง 0")
	}
}

// Limitation (ค) (เปิดเผยในเล่มแล้ว): 2 สมการไม่ต่อเนื่องที่ขอบ 10/11 — น้ำหนักเท่ากัน ทำ 11 ครั้งได้ e1RM "ต่ำกว่า" 10 ครั้ง
// ผลต่อ PR: 100×10 (133.33) เป็น PR ที่สูงกว่า 100×11 (132.55) ทั้งที่ทำได้มากกว่า
func TestLimitation_EstimateOneRepMax_DiscontinuityAt10And11(t *testing.T) {
	e10, e11 := EstimateOneRepMax(100, 10), EstimateOneRepMax(100, 11)
	if !(e10 > e11) {
		t.Errorf("คาดว่า e1RM(10)=%v > e1RM(11)=%v ตามข้อจำกัดที่ทราบ", e10, e11)
	}
	// ผลข้างเคียงกับ %1RM: ตัวอ้างอิงจาก 100×10 สูงกว่า → น้ำหนัก 94 กก. ถูกมองเป็น 70.5% (หนัก) ส่วนตัวอ้างอิงจาก 100×11 มองเป็น 70.9%
	if WeightSetMets(94, 5, e10, true, true) != MetsHeavy {
		t.Errorf("94 กก. เทียบ e1RM(10)=%v ต้องหนัก", e10)
	}
}

// ตัวอ้างอิงจากเซตเดียวของแต่ละช่วง reps: ขอบ 10/11/20/21 ของ SessionReferenceOneRepMax
func TestSessionReferenceOneRepMax_RepBoundaries(t *testing.T) {
	cases := []struct {
		reps int
		want float64
	}{{10, EstimateOneRepMax(100, 10)}, {11, EstimateOneRepMax(100, 11)}, {20, EstimateOneRepMax(100, 20)}, {21, 0}, {0, 0}}
	for _, tc := range cases {
		got := SessionReferenceOneRepMax([]WeightSetEnergyInput{{WeightKg: 100, Reps: tc.reps, Seconds: 60, NearFailure: true}})
		if !almostEqual(got, tc.want, 0.001) {
			t.Errorf("reps=%d: got %v want %v", tc.reps, got, tc.want)
		}
	}
}

// ResolveReferenceOneRepMax: ลำดับความสำคัญครบทุกกิ่ง รวมค่าผิดปกติของ history
func TestResolveReferenceOneRepMax_AllBranches(t *testing.T) {
	yes := []WeightSetEnergyInput{{WeightKg: 80, Reps: 5, Seconds: 60, NearFailure: true}}
	zeroWeightYes := []WeightSetEnergyInput{{WeightKg: 0, Reps: 10, Seconds: 60, NearFailure: true}}
	cases := []struct {
		name       string
		history    float64
		sets       []WeightSetEnergyInput
		hasW, hasR bool
		wantSrc    string
	}{
		{"history ติดลบ ถือว่าไม่มีประวัติ → ใช้เซตที่ยืนยัน", -5, yes, true, true, ReferenceSession},
		{"history = 0 + ไม่มีเซต", 0, nil, true, true, ReferenceSessionDeclined},
		{"ยืนยันแต่น้ำหนัก 0 → ไม่นับเป็นเซตที่ยืนยัน", 0, zeroWeightYes, true, true, ReferenceSessionDeclined},
		{"มี history แต่เป็นบอดี้เวท", 120, yes, false, true, ReferenceNotApplicable},
		{"มี history แต่เป็นท่าค้างเวลา", 120, yes, true, false, ReferenceNotApplicable},
		{"ทั้ง 2 ไม่ใช่", 120, yes, false, false, ReferenceNotApplicable},
	}
	for _, tc := range cases {
		if _, src := ResolveReferenceOneRepMax(tc.history, tc.sets, tc.hasW, tc.hasR); src != tc.wantSrc {
			t.Errorf("%s: src = %s, want %s", tc.name, src, tc.wantSrc)
		}
	}
}

// BodyweightMets: ค่าความยากนอกช่วง 1-3 (ข้อมูลผิดใน DB) ไม่ทำให้พัง — ≤ 1 ได้ 2.8, ≥ 2 ได้ 3.8
func TestBodyweightMets_OutOfRangeDifficulty(t *testing.T) {
	for _, tc := range []struct {
		d    int
		want float64
	}{{-1, MetsBodyweightLight}, {0, MetsBodyweightLight}, {4, MetsBodyweightModerate}, {99, MetsBodyweightModerate}} {
		if got := BodyweightMets(tc.d); got != tc.want {
			t.Errorf("difficulty %d: got %v want %v", tc.d, got, tc.want)
		}
	}
}

// พลังงานเป็นเส้นตรงกับเวลาและน้ำหนักตัว (ก่อนปัดเศษ) และเพิ่มตาม METs
func TestNetEnergyKcal_LinearAndMonotonic(t *testing.T) {
	base := NetEnergyKcal(6.0, 70, 2)
	if !almostEqual(NetEnergyKcal(6.0, 70, 4), 2*base, 1e-9) {
		t.Errorf("เวลา ×2 ต้องได้พลังงาน ×2")
	}
	if !almostEqual(NetEnergyKcal(6.0, 140, 2), 2*base, 1e-9) {
		t.Errorf("น้ำหนักตัว ×2 ต้องได้พลังงาน ×2")
	}
	if !(NetEnergyKcal(6.0, 70, 2) > NetEnergyKcal(3.5, 70, 2)) {
		t.Errorf("METs สูงกว่าต้องได้พลังงานมากกว่า")
	}
	if NetEnergyKcal(1.0, 70, 10) != 0 || NetEnergyKcal(0.5, 70, 10) != 0 {
		t.Errorf("METs ≤ 1 ต้องได้ 0 (ไม่ติดลบ)")
	}
}

// NetEnergyKcal (สูตรแกนกลางที่ใช้ร่วมกับคาร์ดิโอ) ไม่ clamp เวลา/น้ำหนักตัวติดลบ — ล็อกไว้ว่าเป็นพฤติกรรมของสูตรดิบ
// ส่วนชั้นเวท (CalculateWeightTrainingCalories) clamp เป็น 0 แล้ว (แก้ 2026-10-04 หลังพบ int overflow ใน validation ทำให้เวลาติดลบหลุดมา —
// ชั้นแรกที่ปฏิเสธคือ helpers.ValidateWeightSession ดู controllers.TestSaveWorkoutResult_IntOverflow_Rejected)
func TestNetEnergyKcal_RawFormulaDoesNotClampNegativeInputs(t *testing.T) {
	if got := NetEnergyKcal(6.0, 70, -2); got >= 0 {
		t.Errorf("เวลาติดลบ: got %v — สูตรดิบคาดว่าติดลบ", got)
	}
	if got := NetEnergyKcal(6.0, -70, 2); got >= 0 {
		t.Errorf("น้ำหนักตัวติดลบ: got %v — สูตรดิบคาดว่าติดลบ", got)
	}
}

func TestCalculateWeightTrainingCalories_ClampsNegativeSecondsAndBodyWeight(t *testing.T) {
	// เซตที่เวลาติดลบ (เช่น overflow) ได้ 0 ไม่ฉุดผลรวมเซตอื่นให้ติดลบ
	sets := []WeightSetEnergyInput{{WeightKg: 50, Reps: 5, Seconds: math.MinInt64}, {WeightKg: 50, Reps: 5, Seconds: 600}}
	kcal, _, total := CalculateWeightTrainingCalories(sets, 0, 70, true, true, 2)
	_, _, onlySecond := CalculateWeightTrainingCalories(sets[1:], 0, 70, true, true, 2)
	if kcal[0] != 0 || !almostEqual(total, onlySecond, 0.0001) {
		t.Errorf("kcal = %v total = %v, want เซตแรก 0 และ total = %v", kcal, total, onlySecond)
	}
	// น้ำหนักตัวติดลบ → 0 ทุกเซต
	_, _, total = CalculateWeightTrainingCalories(sets[1:], 0, -70, true, true, 2)
	if total != 0 {
		t.Errorf("น้ำหนักตัวติดลบ: total = %v, want 0", total)
	}
}

// ค่าไม่ใช่ตัวเลข/อนันต์ (กันไว้ที่ชั้น JSON แต่ฟังก์ชันสูตรไม่ป้องกันเอง): NaN ต้องไม่ถูกนับเป็นเซตหนัก
func TestWeightSetMets_NaNAndInf(t *testing.T) {
	if got := WeightSetMets(math.NaN(), 5, 100, true, true); got != MetsEndurance {
		t.Errorf("NaN: got %v, want %v (ต้องไม่เป็นเซตหนัก)", got, MetsEndurance)
	}
	if got := WeightSetMets(math.Inf(1), 5, 100, true, true); got != MetsHeavy {
		t.Errorf("+Inf: got %v, want %v (ถูกจำกัดที่ 100%%)", got, MetsHeavy)
	}
	// Limitation: EstimateOneRepMax ไม่กรอง NaN/Inf (คืน NaN/Inf) — ปลอดภัยเพราะ JSON ส่ง NaN/Inf มาไม่ได้
	if got := EstimateOneRepMax(math.NaN(), 5); !math.IsNaN(got) {
		t.Errorf("NaN: got %v", got)
	}
	// NaN ไม่ถูกเลือกเป็นตัวอ้างอิง (เทียบ > best เป็นเท็จเสมอ)
	if got := SessionReferenceOneRepMax([]WeightSetEnergyInput{{WeightKg: math.NaN(), Reps: 5, NearFailure: true}}); got != 0 {
		t.Errorf("ตัวอ้างอิงจาก NaN = %v, want 0", got)
	}
}

// Limitation (ออกแบบ): เวลาพักหลังเซตคิดพลังงานที่ METs ของเซตนั้นเต็มๆ (สเปกข้อ 7[B-1] ขั้น 4: work + rest)
// เซตหนักทำ 5 วิ พักเพิ่ม 595 วิ ได้พลังงานเท่ากับเซตหนักที่ออกแรงต่อเนื่อง 600 วิ — พลังงานจึงขึ้นกับ "เวลาที่ client ส่งมา" ได้
// (ถูกจำกัดด้วยเพดาน 600 วิ/เซต, 7200 วิ/ท่า/วัน) ควรระบุในเล่มว่าเวลาพักเป็นข้อมูลที่ระบบตรวจสอบไม่ได้
func TestLimitation_RestTimeBurnsAtSetIntensity(t *testing.T) {
	short := []WeightSetEnergyInput{{WeightKg: 90, Reps: 5, Seconds: 600}}            // ทำ 5 + พัก 595
	_, _, restHeavy := CalculateWeightTrainingCalories(short, 100, 70, true, true, 2) // 90% → 6.0
	oneMinute := []WeightSetEnergyInput{{WeightKg: 90, Reps: 5, Seconds: 60}}
	_, _, work1min := CalculateWeightTrainingCalories(oneMinute, 100, 70, true, true, 2)
	if !almostEqual(restHeavy, work1min*10, 0.1) { // work1min ปัดเศษแล้ว คลาดได้ ≤ 0.05
		t.Errorf("พักยาว 10 นาที = %v ต้องเป็น 10 เท่าของ 1 นาที (%v)", restHeavy, work1min)
	}
}

// ผลรวมต้องเท่ากับผลบวกของแถวรายเซตที่ปัดแล้ว แม้เซตจำนวนมาก (50 เซต) และเวลาเศษวินาที — กัน SUM(wtrs_calories) เพี้ยนสะสม
func TestCalculateWeightTrainingCalories_ManySetsSumMatchesRows(t *testing.T) {
	sets := make([]WeightSetEnergyInput, 50)
	for i := range sets {
		sets[i] = WeightSetEnergyInput{WeightKg: 40 + float64(i), Reps: 5 + i%10, Seconds: 37 + i}
	}
	kcal, mets, total := CalculateWeightTrainingCalories(sets, 100, 73.3, true, true, 2)
	sum := 0.0
	for i, k := range kcal {
		if mets[i] != MetsEndurance && mets[i] != MetsHeavy {
			t.Fatalf("เซต %d: METs %v", i, mets[i])
		}
		if k <= 0 {
			t.Fatalf("เซต %d: kcal %v ต้อง > 0", i, k)
		}
		sum += k
	}
	if !almostEqual(total, sum, 0.005) {
		t.Errorf("total = %v, sum รายเซต = %v", total, sum)
	}
}

// พลังงานต่อแถวของเวทในกรณีเลวร้ายสุดที่ validation ยอมรับ (น้ำหนักตัว 300 กก. · METs 6.0 · เซตละ 600 วิ) ต้องไม่เกินที่คอลัมน์
// wtrs_calories DECIMAL(6,2) เก็บได้ (9999.99) — เวทจึงไม่ต้องมีด่านตรวจพลังงานเหมือนคาร์ดิโอ (ถ้าแก้เพดานเวลา/น้ำหนักให้ใหญ่ขึ้นต้องดู test นี้)
// ตัวเลข 300/600/9999.99 มาจาก ValidateWeight, WeightSessionMaxSecondsPerSet, MaxCaloriesPerRow (services ไม่ import helpers จึงสำเนาไว้)
func TestWeightWorstCaseRowFitsColumn(t *testing.T) {
	kcal, _, _ := CalculateWeightTrainingCalories([]WeightSetEnergyInput{{WeightKg: 100, Reps: 5, Seconds: 600}}, 100, 300, true, true, 3)
	if kcal[0] <= 0 || kcal[0] > 9999.99 {
		t.Errorf("เลวร้ายสุด = %v kcal ต่อแถว ต้องไม่เกิน 9999.99", kcal[0])
	}
}

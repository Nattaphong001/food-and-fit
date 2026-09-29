package helpers

import (
	"sync"
	"testing"
	"time"
)

func TestRecentSubmissions_ReplaysSuccessWithinTTL(t *testing.T) {
	r := NewRecentSubmissions(time.Minute)
	first, owner := r.Acquire("k")
	if !owner {
		t.Fatal("คำขอแรกต้องเป็นเจ้าของ")
	}
	r.Complete(first, 200, "body-1")

	again, owner := r.Acquire("k")
	if owner {
		t.Fatal("คำขอซ้ำภายใน TTL ต้องไม่เป็นเจ้าของ")
	}
	<-again.Done()
	status, body, ok := again.Result()
	if !ok || status != 200 || body != "body-1" {
		t.Errorf("ต้องได้ผลเดิม: status=%d body=%v ok=%v", status, body, ok)
	}
}

func TestRecentSubmissions_ExpiresAfterTTL(t *testing.T) {
	r := NewRecentSubmissions(time.Minute)
	clock := time.Date(2026, 9, 19, 10, 0, 0, 0, time.UTC)
	r.now = func() time.Time { return clock }

	first, _ := r.Acquire("k")
	r.Complete(first, 200, "old")

	clock = clock.Add(59 * time.Second)
	if _, owner := r.Acquire("k"); owner {
		t.Error("59 วิ ยังอยู่ใน TTL ต้องตอบซ้ำ")
	}
	clock = clock.Add(2 * time.Second)
	if _, owner := r.Acquire("k"); !owner {
		t.Error("เกิน TTL แล้วต้องรับเป็นคำขอใหม่ได้")
	}
}

func TestRecentSubmissions_AbortAllowsRetry(t *testing.T) {
	r := NewRecentSubmissions(time.Minute)
	first, _ := r.Acquire("k")
	r.Abort("k", first)

	if _, _, ok := first.Result(); ok {
		t.Error("คำขอที่ไม่สำเร็จต้องไม่มีผลสำเร็จเก็บไว้")
	}
	if _, owner := r.Acquire("k"); !owner {
		t.Error("หลัง Abort ต้องลองใหม่ได้ ไม่ตอบซ้ำผลล้มเหลว")
	}
}

// กดรัว: คำขอเหมือนกันเข้ามาพร้อมกัน 10 ตัว → มีเจ้าของตัวเดียวที่ทำงานจริง ที่เหลือรอแล้วได้ผลเดียวกัน
func TestRecentSubmissions_ConcurrentDuplicatesWriteOnce(t *testing.T) {
	r := NewRecentSubmissions(time.Minute)
	var mu sync.Mutex
	writes := 0
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, owner := r.Acquire("k")
			if owner {
				time.Sleep(20 * time.Millisecond) // จำลองเวลาเขียน DB
				mu.Lock()
				writes++
				mu.Unlock()
				r.Complete(s, 200, "saved")
				return
			}
			<-s.Done()
			if _, body, ok := s.Result(); !ok || body != "saved" {
				t.Errorf("ผู้รอต้องได้ผลของเจ้าของ: body=%v ok=%v", body, ok)
			}
		}()
	}
	wg.Wait()
	if writes != 1 {
		t.Errorf("เขียนจริง %d ครั้ง ต้องเป็น 1", writes)
	}
}

func TestWeightSessionFingerprint(t *testing.T) {
	rest := func(v int) *int { return &v }
	base := []WeightSetCheck{{Reps: 10, WeightKg: 40, RestSeconds: rest(60)}, {Reps: 8, WeightKg: 40}}
	key := WeightSessionFingerprint(1, 5, 300, base)

	if key != WeightSessionFingerprint(1, 5, 300, base) {
		t.Error("ข้อมูลเดียวกันต้องได้คีย์เดียวกัน")
	}
	changed := []struct {
		name string
		key  string
	}{
		{"สมาชิกต่าง", WeightSessionFingerprint(2, 5, 300, base)},
		{"ท่าต่าง", WeightSessionFingerprint(1, 6, 300, base)},
		{"เวลารวมต่าง", WeightSessionFingerprint(1, 5, 301, base)},
		{"Reps ต่าง", WeightSessionFingerprint(1, 5, 300, []WeightSetCheck{{Reps: 11, WeightKg: 40, RestSeconds: rest(60)}, {Reps: 8, WeightKg: 40}})},
		{"น้ำหนักต่าง", WeightSessionFingerprint(1, 5, 300, []WeightSetCheck{{Reps: 10, WeightKg: 42.5, RestSeconds: rest(60)}, {Reps: 8, WeightKg: 40}})},
		{"เวลาพักต่าง", WeightSessionFingerprint(1, 5, 300, []WeightSetCheck{{Reps: 10, WeightKg: 40, RestSeconds: rest(61)}, {Reps: 8, WeightKg: 40}})},
		{"nil ต่างจาก 0", WeightSessionFingerprint(1, 5, 300, []WeightSetCheck{{Reps: 10, WeightKg: 40, RestSeconds: rest(60)}, {Reps: 8, WeightKg: 40, RestSeconds: rest(0)}})},
		{"จำนวนเซตต่าง", WeightSessionFingerprint(1, 5, 300, base[:1])},
	}
	for _, c := range changed {
		if c.key == key {
			t.Errorf("%s ต้องได้คีย์ต่างจากเดิม", c.name)
		}
	}
}

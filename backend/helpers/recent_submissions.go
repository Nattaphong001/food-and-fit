package helpers

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"sync"
	"time"
)

// ========================================
// Duplicate-submission guard (กันกดบันทึกซ้ำ)
// ========================================

// [FEATURE] WEIGHT_TRAINING
//
// RecentSubmissions จำคำขอบันทึกที่เพิ่งทำสำเร็จไว้ในหน่วยความจำช่วงสั้นๆ (TTL) แล้วตอบซ้ำด้วยผลเดิมแทนที่จะเขียน DB
// อีกรอบ — กัน 2 กรณีที่ทำให้แถวและพลังงานของวันนั้นซ้ำเป็น 2 เท่า:
//  1. กดปุ่มบันทึกรัว (คำขอเหมือนกันเป๊ะเข้ามาพร้อมกัน — คำขอที่ 2 รอผลของคำขอที่ 1 แล้วได้ผลเดียวกัน)
//  2. เน็ตช้า: backend บันทึกสำเร็จแล้วแต่คำตอบไม่ถึงมือถือ ผู้ใช้กดลองใหม่ (ได้ผลเดิม ไม่เขียนซ้ำ)
//
// ตารางผลเวทไม่มีคอลัมน์เวลาบันทึก (wtrs_date เป็นวันที่อย่างเดียว) จึงตรวจจากแถวใน DB ไม่ได้ — จำไว้ในหน่วยความจำ
// แทน ข้อจำกัด: หายเมื่อรีสตาร์ทเซิร์ฟเวอร์ และใช้ได้เฉพาะกรณีรันโปรเซสเดียว (ตรงกับที่โปรเจกต์รันอยู่)
type RecentSubmissions struct {
	mu      sync.Mutex
	ttl     time.Duration
	now     func() time.Time
	entries map[string]*Submission
}

// Submission คือสถานะของคำขอ 1 ชุดที่ถูกจำไว้: ยังทำอยู่ (Done ยังไม่ปิด) หรือทำเสร็จแล้วพร้อมผลลัพธ์
type Submission struct {
	done    chan struct{}
	ok      bool
	status  int
	body    any
	expires time.Time
}

// NewRecentSubmissions สร้างตัวจำคำขอ ttl คือระยะเวลาที่ผลสำเร็จถูกเก็บไว้ตอบซ้ำ
func NewRecentSubmissions(ttl time.Duration) *RecentSubmissions {
	return &RecentSubmissions{ttl: ttl, now: time.Now, entries: make(map[string]*Submission)}
}

// Acquire คืน (submission, true) ถ้าคำขอนี้เป็นเจ้าของ (ยังไม่เคยมีคำขอเหมือนกันในช่วง TTL) — ผู้เรียกต้องเรียก
// Complete หรือ Abort เสมอ; คืน (submission, false) ถ้ามีคำขอเหมือนกันอยู่แล้ว ให้รอ Done() แล้วอ่าน Result()
func (r *RecentSubmissions) Acquire(key string) (*Submission, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := r.now()
	for k, s := range r.entries {
		if s.ok && now.After(s.expires) {
			delete(r.entries, k)
		}
	}
	if s, exists := r.entries[key]; exists {
		return s, false
	}
	s := &Submission{done: make(chan struct{})}
	r.entries[key] = s
	return s, true
}

// Complete บันทึกผลสำเร็จของเจ้าของคำขอ แล้วปลุกคำขอซ้ำที่รออยู่ — ผลถูกเก็บไว้ตอบซ้ำจนครบ TTL
func (r *RecentSubmissions) Complete(s *Submission, status int, body any) {
	r.mu.Lock()
	s.ok, s.status, s.body = true, status, body
	s.expires = r.now().Add(r.ttl)
	r.mu.Unlock()
	close(s.done)
}

// Abort ใช้เมื่อเจ้าของคำขอไม่สำเร็จ — ลืมคำขอนี้ทันทีเพื่อให้ลองใหม่ได้ (ไม่เก็บผลล้มเหลวไว้ตอบซ้ำ)
func (r *RecentSubmissions) Abort(key string, s *Submission) {
	r.mu.Lock()
	if r.entries[key] == s {
		delete(r.entries, key)
	}
	r.mu.Unlock()
	close(s.done)
}

// Done ปิดเมื่อเจ้าของคำขอทำเสร็จ (ทั้งสำเร็จและไม่สำเร็จ)
func (s *Submission) Done() <-chan struct{} { return s.done }

// Result คืนผลที่เก็บไว้ — ok = false ถ้าเจ้าของคำขอไม่สำเร็จ (ผู้รอควรลอง Acquire ใหม่)
func (s *Submission) Result() (status int, body any, ok bool) { return s.status, s.body, s.ok }

// WeightSessionFingerprint สร้างคีย์ระบุ "คำขอบันทึกเวทเซสชันเดียวกัน" จากสมาชิก ท่า เวลารวม และทุกเซต
// (Reps น้ำหนัก เวลาพัก) — ผู้ใช้ 2 คนหรือ 2 เซสชันจริงที่ต่างกันแม้แต่ค่าเดียวได้คีย์ต่างกัน
func WeightSessionFingerprint(memberID, exerciseID uint, totalDurationSeconds int, sets []WeightSetCheck) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%d|%d|%d", memberID, exerciseID, totalDurationSeconds)
	for _, s := range sets {
		rest := "nil"
		if s.RestSeconds != nil {
			rest = fmt.Sprint(*s.RestSeconds)
		}
		fmt.Fprintf(&b, "|%d,%.2f,%s", s.Reps, s.WeightKg, rest)
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}

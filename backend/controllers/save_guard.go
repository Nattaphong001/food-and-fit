package controllers

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"food_and_fit_api/helpers"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ตัวช่วยร่วมของ SaveWorkoutResult / SaveCardioResult (บันทึกผลออกกำลังกาย)
// [FEATURE] WEIGHT_TRAINING / CARDIO

// saveError คือ error ทางธุรกิจที่เกิดใน transaction ของการบันทึก (คืน HTTP status + ข้อความตามเดิม)
// ต่างจาก error DB จริงที่คืน 500 — ดู respondSaveError
type saveError struct {
	status int
	msg    string
}

func (e saveError) Error() string { return e.msg }

// respondSaveError ตอบ error ที่ออกจาก transaction ของการบันทึก: saveError → status/ข้อความของมันเอง, อื่นๆ → log + 500
func respondSaveError(c *gin.Context, err error, where string) {
	var se saveError
	if errors.As(err, &se) {
		c.JSON(se.status, gin.H{"error": se.msg})
		return
	}
	slog.Error(where+": save failed", "err", err, "request_id", c.GetString("request_id"))
	c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกผลไม่สำเร็จ กรุณาลองใหม่"})
}

// lockMemberRow ล็อกแถว member_profile ของสมาชิกใน transaction (SELECT ... FOR UPDATE) — คำขอบันทึกของสมาชิกคนเดียวกัน
// จึงต่อคิวกัน ส่วนสมาชิกคนละคนไม่ติดกัน ใช้กัน race ของ "นับ SUM เวลา/จำนวนเซตสะสม → ตรวจเพดานรายวัน → insert"
// ที่เดิมอ่านค่าเดียวกันพร้อมกันแล้วผ่านเพดานทั้งหมด (ตรวจพบ 2026-10-04: ส่ง 24 คำขอพร้อมกัน เวลาสะสมเกิน 7200 วิ)
// ต้องเรียกเป็นคำสั่งแรกใน transaction เสมอ และนับ/ตรวจ/insert ใน transaction เดียวกัน
func lockMemberRow(tx *gorm.DB, uid uint) error {
	var id uint
	return tx.Raw("SELECT mb_id FROM member_profile WHERE mb_id = ? FOR UPDATE", uid).Scan(&id).Error
}

// recentSubmissionWait คือเวลาสูงสุดที่คำขอซ้ำที่เข้ามาพร้อมกันจะรอผลของคำขอแรก
const recentSubmissionWait = 15 * time.Second

// beginDedupedSave เริ่มการบันทึกแบบกันซ้ำด้วย fingerprint (ดู helpers.RecentSubmissions):
//   - เป็นเจ้าของคำขอ → คืน (submission, true) ผู้เรียกต้อง Complete หรือ Abort เสมอ
//   - มีคำขอเหมือนกันเพิ่งสำเร็จ/กำลังทำอยู่ → ตอบผลเดิมพร้อม "duplicate": true หรือ 409 แล้วคืน (nil, false) (เขียน response แล้ว)
func beginDedupedSave(c *gin.Context, store *helpers.RecentSubmissions, fingerprint string) (*helpers.Submission, bool) {
	for attempt := 0; ; attempt++ {
		if attempt >= 3 {
			c.JSON(http.StatusConflict, gin.H{"error": "บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง"})
			return nil, false
		}
		s, owner := store.Acquire(fingerprint)
		if owner {
			return s, true
		}
		select {
		case <-s.Done():
		case <-time.After(recentSubmissionWait):
			c.JSON(http.StatusConflict, gin.H{"error": "กำลังบันทึกรายการนี้อยู่ กรุณารอสักครู่แล้วตรวจประวัติการฝึก"})
			return nil, false
		}
		if status, body, ok := s.Result(); ok {
			replay := gin.H{}
			if saved, isMap := body.(gin.H); isMap {
				for k, v := range saved {
					replay[k] = v
				}
			}
			replay["duplicate"] = true
			c.JSON(status, replay)
			return nil, false
		}
		// เจ้าของคำขอไม่สำเร็จ → ลอง Acquire ใหม่
	}
}

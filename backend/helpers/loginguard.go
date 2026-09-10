package helpers

import (
	"strings"
	"sync"
	"time"
)

const (
	maxFailedLoginAttempts = 5
	loginLockoutDuration   = 15 * time.Minute
	loginFailureWindow     = 15 * time.Minute
)

type loginState struct {
	failures    int
	lastFailure time.Time
	lockedUntil time.Time
}

var (
	loginGuardMu  sync.Mutex
	loginGuardMap = make(map[string]*loginState)
)

func loginGuardKey(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// CheckLoginLockout คืนค่าว่าบัญชี/อีเมลนี้ถูกล็อกอยู่หรือไม่ (จากการกรอกรหัสผ่านผิดซ้ำๆ)
func CheckLoginLockout(email string) (locked bool, retryAfter time.Duration) {
	loginGuardMu.Lock()
	defer loginGuardMu.Unlock()

	st, ok := loginGuardMap[loginGuardKey(email)]
	if !ok {
		return false, 0
	}
	if time.Now().Before(st.lockedUntil) {
		return true, time.Until(st.lockedUntil)
	}
	return false, 0
}

// RecordLoginFailure เพิ่มจำนวนครั้งที่ login ผิดของอีเมลนี้ และล็อกบัญชีชั่วคราวถ้าเกินจำนวนที่กำหนด
func RecordLoginFailure(email string) {
	loginGuardMu.Lock()
	defer loginGuardMu.Unlock()

	key := loginGuardKey(email)
	st, ok := loginGuardMap[key]
	if !ok || time.Since(st.lastFailure) > loginFailureWindow {
		st = &loginState{}
		loginGuardMap[key] = st
	}
	st.failures++
	st.lastFailure = time.Now()
	if st.failures >= maxFailedLoginAttempts {
		st.lockedUntil = time.Now().Add(loginLockoutDuration)
	}
}

// ResetLoginFailures ล้างประวัติ login ผิดของอีเมลนี้ (เรียกตอน login สำเร็จ)
func ResetLoginFailures(email string) {
	loginGuardMu.Lock()
	defer loginGuardMu.Unlock()
	delete(loginGuardMap, loginGuardKey(email))
}

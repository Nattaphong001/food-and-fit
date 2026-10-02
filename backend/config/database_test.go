package config

import (
	"strings"
	"testing"
)

// DSN ต้องตรึงเขตเวลา session เป็น +07:00 (ให้ CURDATE() ตรงกับวันที่ที่ Go บันทึก) และคง loc=Local ตาม main.go
func TestBuildDSN_PinsSessionTimeZone(t *testing.T) {
	dsn := buildDSN("u", "p", "127.0.0.1", "3306", "food_and_fit_db")
	for _, want := range []string{"time_zone=%27%2B07%3A00%27", "loc=Local", "parseTime=True", "u:p@tcp(127.0.0.1:3306)/food_and_fit_db?"} {
		if !strings.Contains(dsn, want) {
			t.Errorf("DSN ขาด %q: %s", want, dsn)
		}
	}
}

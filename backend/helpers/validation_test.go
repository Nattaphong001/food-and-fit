package helpers

import "testing"

// ครอบคลุมทั้ง 5 ค่ามาตรฐานที่ต้องผ่าน + ค่ากลางๆ ที่ต้อง reject (D9)
func TestValidateActivityLevel(t *testing.T) {
	cases := []struct {
		name  string
		level float64
		want  bool
	}{
		{"sedentary 1.2", 1.2, true},
		{"light 1.375", 1.375, true},
		{"moderate 1.55", 1.55, true},
		{"active 1.725", 1.725, true},
		{"very active 1.9", 1.9, true},
		{"epsilon tolerance 1.3750001", 1.3750001, true},
		{"mid value 1.6 rejected", 1.6, false},
		{"mid value 1.3 rejected", 1.3, false},
		{"below range 1.0 rejected", 1.0, false},
		{"above range 2.0 rejected", 2.0, false},
		{"zero rejected", 0, false},
		{"negative rejected", -1.2, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, msg := ValidateActivityLevel(tc.level)
			if ok != tc.want {
				t.Errorf("ValidateActivityLevel(%v) = (%v, %q), want ok=%v", tc.level, ok, msg, tc.want)
			}
			if !tc.want && msg == "" {
				t.Errorf("ValidateActivityLevel(%v) rejected without error message", tc.level)
			}
			if tc.want && msg != "" {
				t.Errorf("ValidateActivityLevel(%v) accepted but returned message %q", tc.level, msg)
			}
		})
	}
}

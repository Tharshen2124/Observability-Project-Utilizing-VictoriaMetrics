package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRequireAPIKey(t *testing.T) {
	const key = "correct-horse-battery-staple"

	tests := []struct {
		name       string
		configured string
		header     string
		setHeader  bool
		wantStatus int
	}{
		{name: "correct key is allowed", configured: key, header: key, setHeader: true, wantStatus: http.StatusOK},
		{name: "missing header is rejected", configured: key, setHeader: false, wantStatus: http.StatusUnauthorized},
		{name: "wrong key is rejected", configured: key, header: "nope", setHeader: true, wantStatus: http.StatusUnauthorized},
		{name: "empty header is rejected", configured: key, header: "", setHeader: true, wantStatus: http.StatusUnauthorized},
		{name: "unconfigured key denies empty header", configured: "", header: "", setHeader: true, wantStatus: http.StatusUnauthorized},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			called := false
			next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				called = true
				w.WriteHeader(http.StatusOK)
			})

			handler := RequireAPIKey(tc.configured)(next)
			req := httptest.NewRequest(http.MethodDelete, "/api/products/123", nil)
			if tc.setHeader {
				req.Header.Set(APIKeyHeader, tc.header)
			}
			rec := httptest.NewRecorder()

			handler.ServeHTTP(rec, req)

			if rec.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tc.wantStatus)
			}
			wantCalled := tc.wantStatus == http.StatusOK
			if called != wantCalled {
				t.Fatalf("downstream handler called = %v, want %v", called, wantCalled)
			}
		})
	}
}

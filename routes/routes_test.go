package routes

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gorilla/mux"

	"tharshen2124/vivmdummyproject/middlewares"
)

func TestRegisterRoutesRequiresAPIKey(t *testing.T) {
	r := mux.NewRouter()
	RegisterRoutes(r, "test-key")

	tests := []struct {
		method, path, key string
		wantStatus        int
	}{
		{http.MethodDelete, "/api/products/1", "", http.StatusUnauthorized},
		{http.MethodPost, "/api/users", "", http.StatusUnauthorized},
		{http.MethodPut, "/api/orders/1/status", "wrong", http.StatusUnauthorized},
	}

	for _, tc := range tests {
		req := httptest.NewRequest(tc.method, tc.path, nil)
		if tc.key != "" {
			req.Header.Set(middlewares.APIKeyHeader, tc.key)
		}
		rec := httptest.NewRecorder()

		r.ServeHTTP(rec, req)

		if rec.Code != tc.wantStatus {
			t.Fatalf("%s %s with key %q: status = %d, want %d", tc.method, tc.path, tc.key, rec.Code, tc.wantStatus)
		}
	}
}

package middlewares

import (
	"crypto/subtle"
	"net/http"

	"tharshen2124/vivmdummyproject/utils"
)

// APIKeyHeader is the request header that carries the shared API key.
const APIKeyHeader = "X-API-Key"

// RequireAPIKey returns middleware that rejects any request whose X-API-Key
// header does not match apiKey with 401 Unauthorized. An empty configured key
// denies every request, so a missing API_KEY can never authenticate an
// empty or absent header.
func RequireAPIKey(apiKey string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			provided := r.Header.Get(APIKeyHeader)
			if apiKey == "" || subtle.ConstantTimeCompare([]byte(provided), []byte(apiKey)) != 1 {
				utils.Error(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

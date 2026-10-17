package handlers

import (
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"tharshen2124/vivmdummyproject/db"
	"tharshen2124/vivmdummyproject/models"
)

// setupTestDB initialises the store against TEST_DATABASE_URL and clears the
// users table. It skips the test when the variable is unset so the unit suite
// still runs without a database.
func setupTestDB(t *testing.T) *gorm.DB {
	t.Helper()

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping Postgres integration test")
	}

	if err := db.InitDB(dsn); err != nil {
		t.Fatalf("InitDB: %v", err)
	}

	gormDB, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := gormDB.Exec("TRUNCATE TABLE users").Error; err != nil {
		t.Fatalf("truncate users: %v", err)
	}
	return gormDB
}

func postUser(t *testing.T, body string) int {
	t.Helper()

	req := httptest.NewRequest(http.MethodPost, "/api/users", strings.NewReader(body))
	rr := httptest.NewRecorder()
	CreateUser(rr, req)
	return rr.Code
}

func countUsers(t *testing.T, gormDB *gorm.DB, email string) int64 {
	t.Helper()

	var count int64
	if err := gormDB.Model(&models.User{}).Where("email = ?", email).Count(&count).Error; err != nil {
		t.Fatalf("count users: %v", err)
	}
	return count
}

// TestCreateUserRejectsDuplicateEmail checks the documented contract: the
// second POST for an existing email returns 409 and no second row is written.
func TestCreateUserRejectsDuplicateEmail(t *testing.T) {
	gormDB := setupTestDB(t)

	if got := postUser(t, `{"name":"Alice","email":"alice@example.com"}`); got != http.StatusCreated {
		t.Fatalf("first create status = %d, want 201", got)
	}
	if got := postUser(t, `{"name":"Alice Again","email":"alice@example.com"}`); got != http.StatusConflict {
		t.Fatalf("duplicate create status = %d, want 409", got)
	}
	if got := countUsers(t, gormDB, "alice@example.com"); got != 1 {
		t.Fatalf("user rows = %d, want 1", got)
	}
}

// TestCreateUserEnforcesEmailUniquenessUnderConcurrency fires concurrent
// requests with the same email. Exactly one must succeed, the rest must get the
// 409 duplicate response, and only one row may exist.
func TestCreateUserEnforcesEmailUniquenessUnderConcurrency(t *testing.T) {
	gormDB := setupTestDB(t)

	const concurrency = 8
	statuses := make([]int, concurrency)

	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := 0; i < concurrency; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			statuses[i] = postUser(t, `{"name":"Bob","email":"bob@example.com"}`)
		}(i)
	}
	close(start)
	wg.Wait()

	var created, conflict int
	for _, status := range statuses {
		switch status {
		case http.StatusCreated:
			created++
		case http.StatusConflict:
			conflict++
		default:
			t.Errorf("unexpected status %d", status)
		}
	}

	if created != 1 {
		t.Errorf("created = %d, want 1", created)
	}
	if conflict != concurrency-1 {
		t.Errorf("conflict = %d, want %d", conflict, concurrency-1)
	}
	if got := countUsers(t, gormDB, "bob@example.com"); got != 1 {
		t.Errorf("user rows = %d, want 1", got)
	}
}

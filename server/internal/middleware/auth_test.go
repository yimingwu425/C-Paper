package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func makeToken(secret string, userID int64, exp time.Time) string {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": float64(userID),
		"exp":     exp.Unix(),
	})
	s, _ := token.SignedString([]byte(secret))
	return s
}

func TestAuth_ValidToken(t *testing.T) {
	secret := "test-secret"
	token := makeToken(secret, 42, time.Now().Add(time.Hour))

	handler := Auth(secret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		uid, ok := GetUserID(r)
		if !ok || uid != 42 {
			t.Errorf("expected userID 42, got %d, ok=%v", uid, ok)
		}
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 200 {
		t.Errorf("expected 200, got %d", rec.Code)
	}
}

func TestAuth_MissingHeader(t *testing.T) {
	handler := Auth("secret")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler should not be called")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 401 {
		t.Errorf("expected 401, got %d", rec.Code)
	}
}

func TestAuth_InvalidToken(t *testing.T) {
	handler := Auth("secret")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler should not be called")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer invalid.token.here")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 401 {
		t.Errorf("expected 401, got %d", rec.Code)
	}
}

func TestAuth_WrongSecret(t *testing.T) {
	token := makeToken("wrong-secret", 42, time.Now().Add(time.Hour))

	handler := Auth("correct-secret")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler should not be called")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 401 {
		t.Errorf("expected 401, got %d", rec.Code)
	}
}

func TestAuth_ExpiredToken(t *testing.T) {
	secret := "test-secret"
	token := makeToken(secret, 42, time.Now().Add(-time.Hour)) // expired 1 hour ago

	handler := Auth(secret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler should not be called for expired token")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 401 {
		t.Errorf("expected 401 for expired token, got %d", rec.Code)
	}
}

func TestAuth_MalformedHeader(t *testing.T) {
	handler := Auth("secret")(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("handler should not be called")
	}))

	tests := []struct {
		name   string
		header string
	}{
		{"no space", "Bearertoken"},
		{"wrong scheme", "Basic dXNlcjpwYXNz"},
		{"empty value", "Bearer "},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/", nil)
			req.Header.Set("Authorization", tt.header)
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != 401 {
				t.Errorf("expected 401 for %s, got %d", tt.name, rec.Code)
			}
		})
	}
}

func TestAuth_DifferentUserIDs(t *testing.T) {
	secret := "test-secret"

	for _, uid := range []int64{1, 100, 999999} {
		token := makeToken(secret, uid, time.Now().Add(time.Hour))

		handler := Auth(secret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			got, ok := GetUserID(r)
			if !ok {
				t.Error("expected ok=true")
			}
			if got != uid {
				t.Errorf("expected userID %d, got %d", uid, got)
			}
			w.WriteHeader(http.StatusOK)
		}))

		req := httptest.NewRequest("GET", "/", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != 200 {
			t.Errorf("expected 200 for userID %d, got %d", uid, rec.Code)
		}
	}
}

func TestGetUserID_NoContext(t *testing.T) {
	req := httptest.NewRequest("GET", "/", nil)
	uid, ok := GetUserID(req)
	if ok {
		t.Errorf("expected ok=false, got uid=%d", uid)
	}
}

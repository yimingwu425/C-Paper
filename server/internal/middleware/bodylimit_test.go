package middleware

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMaxBodySize_AllowsSmallBody(t *testing.T) {
	handler := MaxBodySize(1024)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("unexpected error reading body: %v", err)
		}
		if string(body) != "small body" {
			t.Errorf("expected 'small body', got '%s'", string(body))
		}
		w.WriteHeader(http.StatusOK)
	}))

	body := strings.NewReader("small body")
	req := httptest.NewRequest("POST", "/", body)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 200 {
		t.Errorf("expected 200, got %d", rec.Code)
	}
}

func TestMaxBodySize_RejectsLargeBody(t *testing.T) {
	handler := MaxBodySize(10)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		buf := new(bytes.Buffer)
		_, err := buf.ReadFrom(r.Body)
		if err == nil {
			t.Error("expected error when reading oversized body")
		}
		w.WriteHeader(http.StatusBadRequest)
	}))

	body := strings.NewReader("this body is larger than 10 bytes")
	req := httptest.NewRequest("POST", "/", body)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 400 {
		t.Errorf("expected 400 for oversized body, got %d", rec.Code)
	}
}

func TestMaxBodySize_ExactLimit(t *testing.T) {
	handler := MaxBodySize(10)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("unexpected error reading body at exact limit: %v", err)
		}
		if len(body) != 10 {
			t.Errorf("expected 10 bytes, got %d", len(body))
		}
		w.WriteHeader(http.StatusOK)
	}))

	body := strings.NewReader("1234567890") // exactly 10 bytes
	req := httptest.NewRequest("POST", "/", body)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 200 {
		t.Errorf("expected 200 for body at exact limit, got %d", rec.Code)
	}
}

func TestMaxBodySize_EmptyBody(t *testing.T) {
	handler := MaxBodySize(1024)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if len(body) != 0 {
			t.Errorf("expected empty body, got %d bytes", len(body))
		}
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest("POST", "/", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 200 {
		t.Errorf("expected 200, got %d", rec.Code)
	}
}

func TestMaxBodySize_OneByteOver(t *testing.T) {
	handler := MaxBodySize(10)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		buf := new(bytes.Buffer)
		_, err := buf.ReadFrom(r.Body)
		if err == nil {
			t.Error("expected error when reading 1 byte over limit")
		}
		w.WriteHeader(http.StatusBadRequest)
	}))

	body := strings.NewReader("12345678901") // 11 bytes, 1 over limit
	req := httptest.NewRequest("POST", "/", body)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != 400 {
		t.Errorf("expected 400 for 1 byte over limit, got %d", rec.Code)
	}
}

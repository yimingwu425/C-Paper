package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/ja-son-wu/c-paper-server/internal/middleware"
	"github.com/ja-son-wu/c-paper-server/internal/models"
)

type ShareHandler struct {
	shares *models.ShareStore
}

func NewShareHandler(shares *models.ShareStore) *ShareHandler {
	return &ShareHandler{shares: shares}
}

type createShareReq struct {
	Subject   string `json:"subject"`
	Year      int    `json:"year"`
	Season    string `json:"season"`
	PaperType string `json:"paper_type"`
	Expiry    string `json:"expiry"`
}

func (h *ShareHandler) CreateShare(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createShareReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	code, err := generateCode(7)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to generate code")
		return
	}

	days := 7
	switch req.Expiry {
	case "1d":
		days = 1
	case "30d":
		days = 30
	case "never":
		days = 36500
	}
	expiresAt := time.Now().AddDate(0, 0, days).Format(time.RFC3339)

	share, err := h.shares.Create(userID, code, req.Subject, req.Year, req.Season, req.PaperType, expiresAt)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to create share")
		return
	}

	RespondJSON(w, http.StatusCreated, share)
}

func (h *ShareHandler) GetShare(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	share, err := h.shares.GetByCode(code)
	if err != nil {
		RespondError(w, http.StatusNotFound, "share not found")
		return
	}

	RespondJSON(w, http.StatusOK, share)
}

func (h *ShareHandler) DeleteShare(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	code := chi.URLParam(r, "code")
	if err := h.shares.Delete(code, userID); err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to delete share")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *ShareHandler) ListMyShares(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	shares, err := h.shares.ListByUser(userID)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to list shares")
		return
	}

	RespondJSON(w, http.StatusOK, shares)
}

func generateCode(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b)[:n], nil
}

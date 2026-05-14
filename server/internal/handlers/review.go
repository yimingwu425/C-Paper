package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/ja-son-wu/c-paper-server/internal/middleware"
	"github.com/ja-son-wu/c-paper-server/internal/models"
)

type ReviewHandler struct {
	reviews *models.ReviewStore
}

func NewReviewHandler(reviews *models.ReviewStore) *ReviewHandler {
	return &ReviewHandler{reviews: reviews}
}

type createReviewReq struct {
	Subject    string   `json:"subject"`
	Year       int      `json:"year"`
	Season     string   `json:"season"`
	PaperType  string   `json:"paper_type"`
	Filename   string   `json:"filename"`
	Rating     int      `json:"rating"`
	Difficulty int      `json:"difficulty"`
	Tags       []string `json:"tags"`
	Comment    string   `json:"comment"`
}

func (h *ReviewHandler) CreateReview(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createReviewReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Rating < 1 || req.Rating > 5 || req.Difficulty < 1 || req.Difficulty > 5 {
		RespondError(w, http.StatusBadRequest, "rating and difficulty must be 1-5")
		return
	}

	review, err := h.reviews.Create(userID, req.Subject, req.Year, req.Season, req.PaperType, req.Filename, req.Rating, req.Difficulty, req.Tags, req.Comment)
	if err != nil {
		RespondError(w, http.StatusConflict, "review already exists for this paper")
		return
	}

	RespondJSON(w, http.StatusCreated, review)
}

func (h *ReviewHandler) DeleteReview(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	reviewID, _ := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err := h.reviews.Delete(reviewID, userID); err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to delete review")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *ReviewHandler) ListReviews(w http.ResponseWriter, r *http.Request) {
	subject := r.URL.Query().Get("subject")
	yearStr := r.URL.Query().Get("year")
	season := r.URL.Query().Get("season")

	year := 0
	if yearStr != "" {
		year, _ = strconv.Atoi(yearStr)
	}

	reviews, err := h.reviews.List(subject, year, season)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to list reviews")
		return
	}

	RespondJSON(w, http.StatusOK, reviews)
}

func (h *ReviewHandler) GetReviewStats(w http.ResponseWriter, r *http.Request) {
	subject := r.URL.Query().Get("subject")
	if subject == "" {
		RespondError(w, http.StatusBadRequest, "subject is required")
		return
	}

	stats, err := h.reviews.Stats(subject)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	RespondJSON(w, http.StatusOK, stats)
}

package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/ja-son-wu/c-paper-server/internal/config"
	"github.com/ja-son-wu/c-paper-server/internal/middleware"
	"github.com/ja-son-wu/c-paper-server/internal/models"
)

type AuthHandler struct {
	users *models.UserStore
	cfg   *config.Config
}

func NewAuthHandler(users *models.UserStore, cfg *config.Config) *AuthHandler {
	return &AuthHandler{users: users, cfg: cfg}
}

type registerReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	Nickname string `json:"nickname"`
}

type loginReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type tokenResp struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	User         interface{} `json:"user"`
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if !isValidEmail(req.Email) {
		RespondError(w, http.StatusBadRequest, "invalid email format")
		return
	}
	if len(req.Password) < 8 {
		RespondError(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), h.cfg.BcryptCost)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to hash password")
		return
	}

	user, err := h.users.Create(req.Email, string(hash), req.Nickname)
	if err != nil {
		RespondError(w, http.StatusConflict, "email already registered")
		return
	}

	access, refresh, err := issueTokens(user.ID, h.cfg)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	RespondJSON(w, http.StatusCreated, tokenResp{AccessToken: access, RefreshToken: refresh, User: user})
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	user, err := h.users.GetByEmail(strings.ToLower(strings.TrimSpace(req.Email)))
	if err != nil {
		RespondError(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		RespondError(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	access, refresh, err := issueTokens(user.ID, h.cfg)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	RespondJSON(w, http.StatusOK, tokenResp{AccessToken: access, RefreshToken: refresh, User: user})
}

func (h *AuthHandler) RefreshToken(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	token, err := jwt.Parse(req.RefreshToken, func(t *jwt.Token) (interface{}, error) {
		return []byte(h.cfg.JWTSecret), nil
	})
	if err != nil || !token.Valid {
		RespondError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "invalid token claims")
		return
	}

	userIDFloat, ok := claims["user_id"].(float64)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "invalid user_id in token")
		return
	}
	userID := int64(userIDFloat)
	access, refresh, err := issueTokens(userID, h.cfg)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to issue tokens")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]string{"access_token": access, "refresh_token": refresh})
}

func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	user, err := h.users.GetByID(userID)
	if err != nil {
		RespondError(w, http.StatusNotFound, "user not found")
		return
	}

	RespondJSON(w, http.StatusOK, user)
}

func (h *AuthHandler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req struct {
		Nickname  string `json:"nickname"`
		AvatarURL string `json:"avatar_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.users.Update(userID, req.Nickname, req.AvatarURL); err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to update user")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func issueTokens(userID int64, cfg *config.Config) (access, refresh string, err error) {
	now := time.Now()

	accessClaims := jwt.MapClaims{
		"user_id": userID,
		"iat":     now.Unix(),
		"exp":     now.Add(cfg.JWTExpiry).Unix(),
	}
	accessT := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	access, err = accessT.SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		return
	}

	refreshClaims := jwt.MapClaims{
		"user_id": userID,
		"iat":     now.Unix(),
		"exp":     now.Add(cfg.RefreshExpiry).Unix(),
	}
	refreshT := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refresh, err = refreshT.SignedString([]byte(cfg.JWTSecret))
	return
}

// RespondJSON writes a JSON response with the given status code.
func RespondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// RespondError writes a JSON error response with the given status code.
func RespondError(w http.ResponseWriter, status int, msg string) {
	RespondJSON(w, status, map[string]interface{}{"ok": false, "error": msg})
}

func isValidEmail(email string) bool {
	parts := strings.Split(email, "@")
	if len(parts) != 2 || len(parts[0]) == 0 || len(parts[1]) == 0 {
		return false
	}
	if !strings.Contains(parts[1], ".") {
		return false
	}
	for _, c := range email {
		if c > unicode.MaxASCII {
			return false
		}
	}
	return true
}

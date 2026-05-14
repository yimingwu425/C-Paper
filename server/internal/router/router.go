package router

import (
	"database/sql"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"

	"github.com/ja-son-wu/c-paper-server/internal/config"
	"github.com/ja-son-wu/c-paper-server/internal/handlers"
	sse "github.com/ja-son-wu/c-paper-server/internal/handlers/sse"
	"github.com/ja-son-wu/c-paper-server/internal/middleware"
	"github.com/ja-son-wu/c-paper-server/internal/models"
)

func Setup(db *sql.DB, cfg *config.Config) http.Handler {
	r := chi.NewRouter()

	// Global middleware
	r.Use(middleware.Logger)
	r.Use(cors.Handler(middleware.CORSOptions(cfg.AllowedOrigins)))
	r.Use(middleware.MaxBodySize(1 << 20)) // 1MB request body limit
	r.Use(func(next http.Handler) http.Handler {
		return middleware.RateLimitGeneral(next)
	})

	// Stores
	users := models.NewUserStore(db)
	shares := models.NewShareStore(db)
	groups := models.NewGroupStore(db)
	reviews := models.NewReviewStore(db)

	// Handlers
	auth := handlers.NewAuthHandler(users, cfg)
	share := handlers.NewShareHandler(shares)
	sseHub := sse.NewHub()
	group := handlers.NewGroupHandler(groups, sseHub)
	review := handlers.NewReviewHandler(reviews)

	// Health check
	r.Get("/api/health", func(w http.ResponseWriter, r *http.Request) {
		handlers.RespondJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Auth routes (rate limited)
	r.Group(func(r chi.Router) {
		r.Use(func(next http.Handler) http.Handler {
			return middleware.RateLimitAuth(next)
		})
		r.Post("/api/auth/register", auth.Register)
		r.Post("/api/auth/login", auth.Login)
		r.Post("/api/auth/refresh", auth.RefreshToken)
	})

	// Public routes
	r.Get("/api/share/{code}", share.GetShare)
	r.Get("/api/reviews", review.ListReviews)
	r.Get("/api/reviews/stats", review.GetReviewStats)

	// Protected routes
	r.Group(func(r chi.Router) {
		r.Use(middleware.Auth(cfg.JWTSecret))

		// User
		r.Get("/api/me", auth.GetMe)
		r.Put("/api/me", auth.UpdateMe)

		// Share
		r.Post("/api/share", share.CreateShare)
		r.Delete("/api/share/{code}", share.DeleteShare)
		r.Get("/api/share/list", share.ListMyShares)

		// Group
		r.Post("/api/groups", group.CreateGroup)
		r.Get("/api/groups", group.ListGroups)
		r.Get("/api/groups/{id}", group.GetGroup)
		r.Post("/api/groups/{id}/join", group.JoinGroup)
		r.Post("/api/groups/{id}/leave", group.LeaveGroup)
		r.Post("/api/groups/{id}/papers", group.AddPaper)
		r.Delete("/api/groups/{id}/papers/{pid}", group.RemovePaper)
		r.Get("/api/groups/{id}/progress", group.GetProgress)
		r.Post("/api/groups/{id}/progress", group.UpdateProgress)
		r.Get("/api/groups/{id}/events", sse.HandleSSE(sseHub, groups.IsMember))

		// Review
		r.Post("/api/reviews", review.CreateReview)
		r.Delete("/api/reviews/{id}", review.DeleteReview)
	})

	return r
}

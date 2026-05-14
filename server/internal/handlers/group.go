package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/ja-son-wu/c-paper-server/internal/handlers/sse"
	"github.com/ja-son-wu/c-paper-server/internal/middleware"
	"github.com/ja-son-wu/c-paper-server/internal/models"
)

type GroupHandler struct {
	groups  *models.GroupStore
	sseHub  *sse.Hub
}

func NewGroupHandler(groups *models.GroupStore, sseHub *sse.Hub) *GroupHandler {
	return &GroupHandler{groups: groups, sseHub: sseHub}
}

type createGroupReq struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

func (h *GroupHandler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createGroupReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	code, err := generateCode(8)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to generate invite code")
		return
	}

	group, err := h.groups.Create(req.Name, req.Description, code, userID)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to create group")
		return
	}

	RespondJSON(w, http.StatusCreated, group)
}

func (h *GroupHandler) JoinGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req struct {
		InviteCode string `json:"invite_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.groups.Join(req.InviteCode, userID); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid invite code or already a member")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func parseIDParam(r *http.Request, key string) (int64, bool) {
	id, err := strconv.ParseInt(chi.URLParam(r, key), 10, 64)
	return id, err == nil && id > 0
}

func (h *GroupHandler) LeaveGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groupID, ok := parseIDParam(r, "id")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid group id")
		return
	}
	if err := h.groups.Leave(groupID, userID); err != nil {
		RespondError(w, http.StatusBadRequest, "cannot leave group (owners cannot leave)")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *GroupHandler) ListGroups(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groups, err := h.groups.ListByUser(userID)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to list groups")
		return
	}

	RespondJSON(w, http.StatusOK, groups)
}

func (h *GroupHandler) GetGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groupID, ok := parseIDParam(r, "id")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid group id")
		return
	}

	isMember, err := h.groups.IsMember(groupID, userID)
	if err != nil || !isMember {
		RespondError(w, http.StatusForbidden, "not a member of this group")
		return
	}

	group, err := h.groups.GetByID(groupID)
	if err != nil {
		RespondError(w, http.StatusNotFound, "group not found")
		return
	}

	members, _ := h.groups.ListMembers(groupID)
	papers, _ := h.groups.ListPapers(groupID)

	RespondJSON(w, http.StatusOK, map[string]interface{}{
		"group":   group,
		"members": members,
		"papers":  papers,
	})
}

type addPaperReq struct {
	Subject     string `json:"subject"`
	Year        int    `json:"year"`
	Season      string `json:"season"`
	PaperType   string `json:"paper_type"`
	Filename    string `json:"filename"`
	DownloadURL string `json:"download_url"`
}

func (h *GroupHandler) AddPaper(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groupID, ok := parseIDParam(r, "id")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid group id")
		return
	}

	isMember, err := h.groups.IsMember(groupID, userID)
	if err != nil || !isMember {
		RespondError(w, http.StatusForbidden, "not a member of this group")
		return
	}

	var req addPaperReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	paper, err := h.groups.AddPaper(groupID, userID, req.Subject, req.Year, req.Season, req.PaperType, req.Filename, req.DownloadURL)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to add paper")
		return
	}

	RespondJSON(w, http.StatusCreated, paper)
}

func (h *GroupHandler) RemovePaper(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	paperID, ok := parseIDParam(r, "pid")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid paper id")
		return
	}
	if err := h.groups.RemovePaper(paperID, userID); err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to remove paper")
		return
	}

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *GroupHandler) GetProgress(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groupID, ok := parseIDParam(r, "id")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid group id")
		return
	}

	isMember, err := h.groups.IsMember(groupID, userID)
	if err != nil || !isMember {
		RespondError(w, http.StatusForbidden, "not a member of this group")
		return
	}

	progress, err := h.groups.GetProgress(groupID)
	if err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to get progress")
		return
	}

	RespondJSON(w, http.StatusOK, progress)
}

type updateProgressReq struct {
	GroupPaperID int64  `json:"group_paper_id"`
	Status       string `json:"status"`
}

func (h *GroupHandler) UpdateProgress(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r)
	if !ok {
		RespondError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	groupID, ok := parseIDParam(r, "id")
	if !ok {
		RespondError(w, http.StatusBadRequest, "invalid group id")
		return
	}

	var req updateProgressReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		RespondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.groups.UpdateProgress(req.GroupPaperID, userID, req.Status); err != nil {
		RespondError(w, http.StatusInternalServerError, "failed to update progress")
		return
	}

	// Broadcast SSE event
	data, _ := json.Marshal(map[string]interface{}{
		"user_id":        userID,
		"group_paper_id": req.GroupPaperID,
		"status":         req.Status,
	})
	h.sseHub.Broadcast(groupID, sse.Event{Type: "progress_update", Data: string(data)})

	RespondJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

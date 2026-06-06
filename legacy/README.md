# Legacy Archive

This directory is an archival record of earlier C-Paper implementations. It is kept so the final legacy release can be understood, rebuilt when explicitly requested, and compared against the current native product.

The active maintained product is the Swift/macOS implementation at the repository root `Package.swift` and under `macos/`. Do not treat anything in `legacy/` as part of the active native app, native CI, or normal release path.

## Contents

- `pywebview/`: archived Python + pywebview desktop shell and legacy packaging scripts for the final 5.2.1 legacy release.
- `python-backend/`: archived Python bridge/backend and historical tests retained for reference.

## Maintenance Boundary

- Prefer native changes in `macos/`, `scripts/`, and the root Swift package.
- Edit `legacy/` only for archival corrections, final legacy release reproducibility, or explicitly requested legacy maintenance.
- Legacy-only file changes should not trigger the native macOS workflow.
- Python dependency locking is intentionally not added here because no routine legacy CI runs from ordinary branch or pull-request changes.

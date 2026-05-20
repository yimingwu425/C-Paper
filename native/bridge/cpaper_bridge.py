#!/usr/bin/env python3
"""JSON-lines bridge for the native Swift C-Paper app."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from backend.api import API  # noqa: E402
from backend.const import BASE_URL  # noqa: E402
from backend.parser import get_year  # noqa: E402

api = API()


def _ok(request_id: str, payload: Any) -> dict[str, Any]:
    return {"id": request_id, "ok": True, "payload": payload}


def _err(request_id: str, message: str) -> dict[str, Any]:
    return {"id": request_id, "ok": False, "error": message}


def _parse_json_blob(blob: str) -> Any:
    try:
        return json.loads(blob)
    except json.JSONDecodeError:
        return blob


def _unwrap_ok(blob: str) -> Any:
    payload = _parse_json_blob(blob)
    if isinstance(payload, dict) and payload.get("ok") is False:
        raise RuntimeError(payload.get("error") or "Backend request failed")
    return payload


def _season_name(sy: str | None) -> str | None:
    if not sy:
        return None
    first = sy[0].lower()
    if first == "m":
        return "Mar"
    if first == "s":
        return "Jun"
    if first == "w":
        return "Nov"
    return None


def _paper_url(filename: str) -> str:
    return f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"


def _file_record(
    filename: str,
    *,
    subject: str | None,
    sy: str | None,
    number: str | None,
    paper_type: str | None,
    label: str | None = None,
) -> dict[str, Any]:
    return {
        "filename": filename,
        "url": _paper_url(filename),
        "year": int(get_year(sy)) if sy and get_year(sy).isdigit() else None,
        "season": _season_name(sy),
        "paperType": paper_type,
        "subjectCode": subject,
        "number": number or None,
        "label": label or None,
    }


def _files_from_groups(groups: list[dict[str, Any]]) -> list[dict[str, Any]]:
    files: list[dict[str, Any]] = []
    for group in groups:
        subject = group.get("subject")
        sy = group.get("sy")
        number = group.get("number")
        label = group.get("label")
        if group.get("qp"):
            files.append(
                _file_record(
                    group["qp"],
                    subject=subject,
                    sy=sy,
                    number=number,
                    paper_type="QP",
                    label=label,
                )
            )
        if group.get("ms"):
            files.append(
                _file_record(
                    group["ms"],
                    subject=subject,
                    sy=sy,
                    number=number,
                    paper_type="MS",
                    label=label,
                )
            )
        if group.get("filename"):
            files.append(
                _file_record(
                    group["filename"],
                    subject=subject,
                    sy=sy,
                    number=number,
                    paper_type=(group.get("ftype") or "").upper() or None,
                    label=label,
                )
            )
    return files


def handle(message: dict[str, Any]) -> dict[str, Any]:
    request_id = str(message.get("id", ""))
    method = message.get("method")
    params = message.get("params") or {}

    if not request_id:
        return _err("", "Missing request id")

    try:
        if method == "get_default_dir":
            return _ok(request_id, api.get_default_dir())

        if method == "choose_directory":
            return _ok(request_id, api.choose_directory())

        if method == "get_subjects":
            payload = _unwrap_ok(api.get_subjects())
            data = payload.get("data", [])
            subjects = []
            for item in data:
                code = item.get("value") or item.get("code") or item.get("id")
                name = item.get("text") or item.get("name") or item.get("title")
                if code and name:
                    subjects.append({"code": code, "name": name})
            return _ok(request_id, subjects)

        if method == "get_favorites":
            payload = _unwrap_ok(api.get_favorites())
            favorites = []
            for item in payload:
                code = item.get("code")
                name = item.get("name")
                if code and name:
                    favorites.append({"code": code, "name": name})
            return _ok(request_id, favorites)

        if method == "load_settings":
            return _ok(request_id, _unwrap_ok(api.load_settings()))

        if method == "save_settings":
            return _ok(request_id, _unwrap_ok(api.save_settings(json.dumps(params, ensure_ascii=False))))

        if method == "set_proxy":
            return _ok(request_id, _unwrap_ok(api.set_proxy(params.get("proxy_url", ""))))

        if method == "test_proxy":
            return _ok(request_id, _unwrap_ok(api.test_proxy(params.get("proxy_url", ""))))

        if method == "search":
            payload = _unwrap_ok(api.search(params["subject"], params["year"], params["season"]))
            groups = payload.get("groups", [])
            return _ok(request_id, {"groups": groups, "files": _files_from_groups(groups)})

        if method == "batch_preview":
            payload = _unwrap_ok(api.batch_preview(json.dumps(params, ensure_ascii=False)))
            groups = payload.get("groups", [])
            warnings = payload.get("warnings", [])
            return _ok(
                request_id,
                {"groups": groups, "files": _files_from_groups(groups), "warnings": warnings},
            )

        if method == "start_download":
            payload = _unwrap_ok(
                api.start_download(
                    json.dumps(params.get("groups", []), ensure_ascii=False),
                    params.get("save_dir", ""),
                    json.dumps(params.get("options", {}), ensure_ascii=False),
                )
            )
            return _ok(request_id, payload)

        if method == "get_status":
            return _ok(request_id, _unwrap_ok(api.get_status()))

        if method == "get_download_list":
            return _ok(request_id, _unwrap_ok(api.get_download_list()))

        if method == "cancel_download":
            return _ok(request_id, _unwrap_ok(api.cancel_download()))

        if method == "get_pdf_url":
            payload = _unwrap_ok(api.get_pdf_url(params.get("filename", "")))
            if payload.get("ok") is False:
                raise RuntimeError(payload.get("error") or "Unable to create PDF URL")
            return _ok(request_id, {"url": payload["url"]})

        return _err(request_id, f"Unknown method: {method}")
    except Exception as exc:
        return _err(request_id, str(exc))


def main() -> int:
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
                response = handle(message)
            except Exception as exc:
                response = _err("", f"Invalid request: {exc}")
            print(json.dumps(response, ensure_ascii=False), flush=True)
    finally:
        try:
            api.plugin_manager.close(wait=False)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

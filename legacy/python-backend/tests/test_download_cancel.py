import json
import threading
import time

from backend import API


def make_item(item_id, status):
    return {
        "id": item_id,
        "filename": f"paper_{item_id}.pdf",
        "ftype": "QP",
        "label": f"Paper {item_id}",
        "year": "2024",
        "save_path": f"/tmp/paper_{item_id}.pdf",
        "status": status,
        "error": "",
        "error_type": "",
    }


def test_handle_auto_retry_cancel_interrupts_delay_and_keeps_failed():
    api = API()
    failed = [make_item(1, "failed")]

    started = time.monotonic()
    thread = threading.Thread(target=api._handle_auto_retry, args=(failed, 0))
    thread.start()
    time.sleep(0.05)
    api._cancel.set()
    thread.join(timeout=1)
    elapsed = time.monotonic() - started

    assert not thread.is_alive()
    assert elapsed < 1
    assert failed[0]["status"] == "failed"
    assert failed[0]["error"] == ""


def test_cancel_download_immediately_marks_active_items_cancelled():
    api = API()
    pending = make_item(1, "pending")
    downloading = make_item(2, "downloading")
    done = make_item(3, "done")
    failed = make_item(4, "failed")
    api._dl_items = [pending, downloading, done, failed]
    api._status = {
        "phase": "running",
        "done": 0,
        "total": 4,
        "success": 0,
        "message": "下载中...",
    }

    result = json.loads(api.cancel_download())
    status = json.loads(api.get_status())
    items = json.loads(api.get_download_list())

    assert result["ok"] is True
    assert items[0]["status"] == "cancelled"
    assert items[0]["error"] == "用户取消"
    assert items[1]["status"] == "cancelled"
    assert items[1]["error"] == "用户取消"
    assert items[2]["status"] == "done"
    assert items[3]["status"] == "failed"
    assert status["phase"] == "done"
    assert status["message"] == "已取消"


def test_update_download_progress_uses_global_download_list_counts():
    api = API()
    api._dl_items = [
        make_item(1, "done"),
        make_item(2, "failed"),
        make_item(3, "pending"),
        make_item(4, "cancelled"),
    ]
    api._status = {
        "phase": "running",
        "done": 0,
        "total": 4,
        "success": 0,
        "message": "",
    }

    api._update_download_progress(batch_total=4)
    status = json.loads(api.get_status())

    assert status["done"] == 3
    assert status["total"] == 4
    assert status["success"] == 1
    assert status["failed"] == 1
    assert status["cancelled"] == 1
    assert status["message"] == "下载中... (3/4)"

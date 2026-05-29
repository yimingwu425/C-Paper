"""Network helpers + filename parsing + paper grouping"""
import os, re
import requests
from .const import BASE_URL
from .cache import load_cache, save_cache


def fetch_subjects(session: requests.Session):
    """Fetch subject list from API. Results are cached for 24 hours."""
    cache_key = "subjects"
    cached = load_cache(cache_key)
    if cached is not None:
        return cached
    resp = session.post(f"{BASE_URL}/obj/Common/Subject/combo", timeout=(5, 15))
    resp.raise_for_status()
    data = resp.json()
    save_cache(cache_key, data)
    return data


def search_papers(session: requests.Session, subject, year, season):
    key = f"{subject}_{year}_{season}"
    cached = load_cache(key)
    if cached is not None:
        return cached
    resp = session.post(
        f"{BASE_URL}/obj/Common/Fetch/renum",
        data={"subject": str(subject), "year": str(year), "season": season},
        timeout=(5, 20),
    )
    resp.raise_for_status()
    result = resp.json()
    save_cache(key, result)
    return result


def parse_filename(fname):
    if os.path.sep in fname or '/' in fname or '\\' in fname:
        return None
    if not fname.lower().endswith(".pdf"):
        return None
    m = re.fullmatch(r"(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf", fname)
    if not m:
        return None
    return dict(subject=m.group(1), sy=m.group(2), type=m.group(3),
                number=m.group(4) or "", filename=fname)


def get_year(sy):
    y = sy[1:] if len(sy) > 1 and sy[0] in "msw" else "unknown"
    return "20" + y if y.isdigit() and len(y) == 2 else y


def paper_group_of(number):
    if not number:
        return 0
    try:
        n = int(number)
        return n // 10 if n >= 10 else n
    except ValueError:
        return 0


def group_papers(rows):
    pairs, standalone_files = {}, []
    for row in rows:
        fname = row["file"]
        p = parse_filename(fname)
        if not p:
            continue
        if p["type"] not in ("qp", "ms"):
            standalone_files.append(dict(
                filename=fname, ftype=p["type"],
                label=fname.replace(".pdf", ""), paper_group=0, sy="", number="",
            ))
            continue
        key = (p["subject"], p["sy"], p["number"])
        if key not in pairs:
            pairs[key] = dict(
                subject=p["subject"], sy=p["sy"], number=p["number"],
                paper_group=paper_group_of(p["number"]), qp=None, ms=None,
            )
        pairs[key][p["type"]] = fname
    results = []
    for v in pairs.values():
        results.append(dict(
            subject=v["subject"], sy=v["sy"], number=v["number"],
            paper_group=v["paper_group"], qp=v.get("qp"), ms=v.get("ms"),
        ))
    results.sort(key=lambda g: (g["paper_group"],
                                 int(g["number"]) if g["number"].isdigit() else 999))
    results.extend(standalone_files)
    return results


def build_folders(groups, save_dir, merge):
    os.makedirs(save_dir, exist_ok=True)
    if merge:
        return {"root": save_dir}
    folders = {}
    for g in groups:
        year = get_year(g.get("sy", ""))
        if year not in folders:
            folders[year] = {
                "qp": os.path.join(save_dir, year, "QP"),
                "ms": os.path.join(save_dir, year, "MS"),
            }
            os.makedirs(folders[year]["qp"], exist_ok=True)
            os.makedirs(folders[year]["ms"], exist_ok=True)
    return folders

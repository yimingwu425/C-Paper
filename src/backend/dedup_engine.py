"""Smart deduplication engine using sentence-transformers + FAISS."""
import json
import os
import pickle
import time
from dataclasses import dataclass, asdict
from typing import Callable, Optional

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

try:
    from sentence_transformers import SentenceTransformer
    HAS_ST = True
except ImportError:
    HAS_ST = False

try:
    import faiss
    HAS_FAISS = True
except ImportError:
    HAS_FAISS = False


@dataclass
class SimilarMatch:
    question_number: str
    paper_id: str
    paper_info: dict
    similarity: float
    matched_text: str

    def to_dict(self):
        return asdict(self)


class DedupEngine:
    """Smart deduplication engine — sentence-transformers + FAISS."""

    THRESHOLD_HIGH = 0.80
    THRESHOLD_MEDIUM = 0.65

    def __init__(self, model_name="all-MiniLM-L6-v2", cache_dir=""):
        self._model_name = model_name
        self._cache_dir = cache_dir or os.path.join(os.path.expanduser("~"), ".cie_cache", "dedup_index")
        os.makedirs(self._cache_dir, exist_ok=True)

        self._model = None
        self._index = None
        self._metadata = []  # list of dicts: {paper_id, question_number, text, subject, year}
        self._paper_ids = set()
        self._dirty = False  # tracks unsaved changes

        self._index_path = os.path.join(self._cache_dir, "questions.index")
        self._meta_path = os.path.join(self._cache_dir, "questions.meta.pkl")
        self._papers_path = os.path.join(self._cache_dir, "papers.set.pkl")

    def is_available(self):
        """Check if dependencies are available."""
        return HAS_ST and HAS_FAISS and HAS_NUMPY

    def initialize(self, progress_cb=None):
        """Initialize the model (first run downloads ~80MB)."""
        if not HAS_ST:
            return {"ok": False, "error": "sentence-transformers 未安装"}
        if not HAS_FAISS:
            return {"ok": False, "error": "faiss-cpu 未安装"}

        try:
            if progress_cb:
                progress_cb("loading", 0, "正在加载模型...")

            self._model = SentenceTransformer(self._model_name)

            if progress_cb:
                progress_cb("loading", 100, "模型加载完成")

            # Try loading existing index
            self._load_index()

            return {"ok": True, "model": self._model_name, "indexed_questions": len(self._metadata)}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def add_paper(self, paper_id, questions, metadata=None):
        """Add paper questions to the index."""
        if not self._model:
            return {"ok": False, "error": "引擎未初始化"}

        if paper_id in self._paper_ids:
            return {"ok": True, "added_count": 0, "note": "already indexed"}

        texts = [q.text if hasattr(q, 'text') else q.get('text', '') for q in questions]
        if not texts:
            return {"ok": True, "added_count": 0}

        # Generate embeddings
        embeddings = self._model.encode(texts, normalize_embeddings=True)

        # Add to FAISS index
        if self._index is None:
            dim = embeddings.shape[1]
            self._index = faiss.IndexFlatIP(dim)  # Inner product = cosine for normalized vectors

        self._index.add(embeddings.astype('float32'))

        # Add metadata
        for i, q in enumerate(questions):
            text = q.text if hasattr(q, 'text') else q.get('text', '')
            num = q.number if hasattr(q, 'number') else q.get('number', str(i+1))
            self._metadata.append({
                "paper_id": paper_id,
                "question_number": num,
                "text": text[:500],
                "subject": (metadata or {}).get("subject", ""),
                "year": (metadata or {}).get("year", 0),
            })

        self._paper_ids.add(paper_id)
        self._dirty = True

        return {"ok": True, "added_count": len(texts)}

    def find_similar(self, question_text, top_k=10, threshold=None):
        """Find similar questions to the given text."""
        if not self._model or not self._index:
            return {"ok": False, "error": "引擎未初始化或索引为空"}

        if threshold is None:
            threshold = self.THRESHOLD_MEDIUM

        # Generate query embedding
        query_emb = self._model.encode([question_text], normalize_embeddings=True).astype('float32')

        # Search
        k = min(top_k, self._index.ntotal)
        if k == 0:
            return {"ok": True, "matches": []}

        scores, indices = self._index.search(query_emb, k)

        matches = []
        for score, idx in zip(scores[0], indices[0]):
            if idx < 0 or score < threshold:
                continue
            meta = self._metadata[idx]
            matches.append(SimilarMatch(
                question_number=meta["question_number"],
                paper_id=meta["paper_id"],
                paper_info={"subject": meta.get("subject", ""), "year": meta.get("year", 0)},
                similarity=round(float(score), 4),
                matched_text=meta["text"][:200],
            ).to_dict())

        return {"ok": True, "matches": matches}

    def build_full_index(self, ocr_results, progress_cb=None):
        """Rebuild full index from all OCR results."""
        if not self._model:
            return {"ok": False, "error": "引擎未初始化"}

        # Reset
        self._index = None
        self._metadata = []
        self._paper_ids = set()

        total = len(ocr_results)
        for i, (paper_id, questions, meta) in enumerate(ocr_results):
            if progress_cb:
                progress_cb("indexing", int((i / total) * 100), f"索引中 {i+1}/{total}")
            self.add_paper(paper_id, questions, meta)

        self._save_index()

        if progress_cb:
            progress_cb("done", 100, f"索引完成，共 {len(self._metadata)} 道题")

        return {"ok": True, "total_questions": len(self._metadata), "total_papers": len(self._paper_ids)}

    def flush(self):
        """Save index to disk if there are unsaved changes."""
        if self._dirty:
            self._save_index()
            self._dirty = False

    def get_stats(self):
        """Get index statistics."""
        return {
            "ok": True,
            "total_questions": len(self._metadata),
            "total_papers": len(self._paper_ids),
            "model": self._model_name,
            "initialized": self._model is not None,
        }

    def _save_index(self):
        """Save FAISS index and metadata to disk."""
        try:
            if self._index is not None:
                faiss.write_index(self._index, self._index_path)
            with open(self._meta_path, 'wb') as f:
                pickle.dump(self._metadata, f)
            with open(self._papers_path, 'wb') as f:
                pickle.dump(self._paper_ids, f)
        except Exception:
            pass

    def _load_index(self):
        """Load FAISS index and metadata from disk."""
        try:
            if os.path.exists(self._index_path):
                self._index = faiss.read_index(self._index_path)
            if os.path.exists(self._meta_path):
                with open(self._meta_path, 'rb') as f:
                    self._metadata = pickle.load(f)
            if os.path.exists(self._papers_path):
                with open(self._papers_path, 'rb') as f:
                    self._paper_ids = pickle.load(f)
        except Exception:
            self._index = None
            self._metadata = []
            self._paper_ids = set()

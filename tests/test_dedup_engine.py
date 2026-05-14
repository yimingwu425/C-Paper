import os
import pytest
from backend.dedup_engine import DedupEngine, SimilarMatch, HAS_ST, HAS_FAISS, HAS_NUMPY


class TestDedupEngineAvailability:
    def test_is_available_check(self):
        """is_available reflects the actual state of optional dependencies."""
        engine = DedupEngine.__new__(DedupEngine)
        engine._model_name = "all-MiniLM-L6-v2"
        engine._cache_dir = "/tmp/test_dedup"
        engine._model = None
        engine._index = None
        engine._metadata = []
        engine._paper_ids = set()

        result = engine.is_available()
        # Should match the module-level dependency flags
        assert result == (HAS_ST and HAS_FAISS and HAS_NUMPY)
        assert isinstance(result, bool)

    def test_is_available_without_deps(self):
        """When dependencies are missing, is_available returns False."""
        engine = DedupEngine.__new__(DedupEngine)
        engine._model_name = "all-MiniLM-L6-v2"
        engine._cache_dir = "/tmp/test_dedup"
        engine._model = None
        engine._index = None
        engine._metadata = []
        engine._paper_ids = set()

        # If any dep is missing, is_available should be False
        if not (HAS_ST and HAS_FAISS and HAS_NUMPY):
            assert engine.is_available() is False


class TestDedupEngineStats:
    def test_stats_empty(self, tmp_path):
        """Stats on a fresh engine returns zero counts."""
        engine = DedupEngine.__new__(DedupEngine)
        engine._model_name = "all-MiniLM-L6-v2"
        engine._cache_dir = str(tmp_path)
        engine._model = None
        engine._index = None
        engine._metadata = []
        engine._paper_ids = set()
        engine._index_path = str(tmp_path / "questions.index")
        engine._meta_path = str(tmp_path / "questions.meta.pkl")
        engine._papers_path = str(tmp_path / "papers.set.pkl")

        stats = engine.get_stats()
        assert stats["ok"] is True
        assert stats["total_questions"] == 0
        assert stats["total_papers"] == 0
        assert stats["model"] == "all-MiniLM-L6-v2"
        assert stats["initialized"] is False

    def test_stats_with_data(self, tmp_path):
        """Stats reflects in-memory metadata and paper_ids."""
        engine = DedupEngine.__new__(DedupEngine)
        engine._model_name = "test-model"
        engine._cache_dir = str(tmp_path)
        engine._model = "fake_model"  # pretend initialized
        engine._index = None
        engine._metadata = [
            {"paper_id": "p1", "question_number": "1", "text": "Q1"},
            {"paper_id": "p1", "question_number": "2", "text": "Q2"},
            {"paper_id": "p2", "question_number": "1", "text": "Q3"},
        ]
        engine._paper_ids = {"p1", "p2"}
        engine._index_path = str(tmp_path / "questions.index")
        engine._meta_path = str(tmp_path / "questions.meta.pkl")
        engine._papers_path = str(tmp_path / "papers.set.pkl")

        stats = engine.get_stats()
        assert stats["ok"] is True
        assert stats["total_questions"] == 3
        assert stats["total_papers"] == 2
        assert stats["model"] == "test-model"
        assert stats["initialized"] is True


class TestDedupEngineInit:
    def test_initialize_without_deps(self, tmp_path):
        """initialize() returns error when optional dependencies are missing."""
        engine = DedupEngine(cache_dir=str(tmp_path / "dedup"))

        if not HAS_ST:
            result = engine.initialize()
            assert result["ok"] is False
            assert "sentence-transformers" in result["error"]
        elif not HAS_FAISS:
            result = engine.initialize()
            assert result["ok"] is False
            assert "faiss" in result["error"]


class TestDedupEngineAddPaper:
    def test_add_paper_without_model(self, tmp_path):
        """add_paper returns error when model is not initialized."""
        engine = DedupEngine(cache_dir=str(tmp_path / "dedup"))

        class Q:
            def __init__(self, number, text):
                self.number = number
                self.text = text

        result = engine.add_paper("p1", [Q("1", "test question")])
        assert result["ok"] is False
        assert "\u672a\u521d\u59cb\u5316" in result["error"]  # "未初始化"

    def test_find_similar_without_model(self, tmp_path):
        """find_similar returns error when model/index is not ready."""
        engine = DedupEngine(cache_dir=str(tmp_path / "dedup"))

        result = engine.find_similar("test query")
        assert result["ok"] is False


class TestSimilarMatchDataclass:
    def test_similar_match_to_dict(self):
        """SimilarMatch.to_dict() returns a proper dictionary."""
        match = SimilarMatch(
            question_number="1",
            paper_id="paper_001",
            paper_info={"subject": "Math", "year": 2024},
            similarity=0.85,
            matched_text="Sample matched text",
        )
        d = match.to_dict()
        assert d["question_number"] == "1"
        assert d["paper_id"] == "paper_001"
        assert d["similarity"] == 0.85
        assert d["paper_info"]["subject"] == "Math"

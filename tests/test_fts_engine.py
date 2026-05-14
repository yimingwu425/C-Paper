import os
import sqlite3
import pytest
from backend.fts_engine import FTSEngine, SearchResult


class TestFTSEngineInit:
    def test_initialize(self, tmp_path):
        """initialize() creates the FTS tables without error."""
        db_path = str(tmp_path / "test_fts.db")
        engine = FTSEngine(db_path=db_path)
        engine.initialize()
        # Verify the database file was created
        assert os.path.exists(db_path)
        # Verify the tables exist
        conn = sqlite3.connect(db_path)
        tables = {row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table','view')"
        ).fetchall()}
        conn.close()
        assert "papers_meta" in tables
        assert "papers_fts" in tables
        engine.close()

    def test_initialize_is_idempotent(self, tmp_path):
        """Calling initialize() twice does not raise."""
        db_path = str(tmp_path / "test_fts.db")
        engine = FTSEngine(db_path=db_path)
        engine.initialize()
        engine.initialize()  # should not fail
        engine.close()


def _make_engine_with_plain_fts(tmp_path):
    """Create an FTSEngine with a plain FTS5 table (no content= option)
    so that direct INSERT/DELETE work in test environments."""
    db_path = str(tmp_path / "test_fts.db")
    engine = FTSEngine(db_path=db_path)
    conn = engine._get_conn()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS papers_meta (
            paper_id TEXT PRIMARY KEY,
            subject TEXT DEFAULT '',
            year INTEGER DEFAULT 0,
            season TEXT DEFAULT '',
            filename TEXT DEFAULT '',
            indexed_at TEXT DEFAULT ''
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS papers_fts USING fts5(
            paper_id,
            question_number,
            text,
            subject,
            year
        );
    """)
    conn.commit()
    return engine


class TestFTSEngineSearch:
    def test_index_and_search(self, tmp_path):
        """Indexing a paper then searching finds it."""
        engine = _make_engine_with_plain_fts(tmp_path)

        class Q:
            def __init__(self, number, text):
                self.number = number
                self.text = text

        questions = [
            Q("1", "Solve the quadratic equation x squared minus five x plus six equals zero"),
            Q("2", "Find the derivative of sine of x with respect to x"),
        ]
        engine.index_paper("paper_001", "full text here", questions, metadata={"subject": "Math", "year": 2024})

        # Search for a term that appears in question 1
        result = engine.search("quadratic")
        assert result["ok"] is True
        assert len(result["results"]) > 0
        assert result["results"][0]["paper_id"] == "paper_001"

        engine.close()

    def test_search_no_results(self, tmp_path):
        """Searching for a term that doesn't exist returns empty results."""
        engine = _make_engine_with_plain_fts(tmp_path)

        class Q:
            def __init__(self, number, text):
                self.number = number
                self.text = text

        engine.index_paper("paper_001", "text", [Q("1", "Simple math problem")])

        result = engine.search("quantum_physics_nonexistent")
        assert result["ok"] is True
        assert len(result["results"]) == 0

        engine.close()

    def test_empty_query(self, tmp_path):
        """Empty search string returns empty results."""
        engine = _make_engine_with_plain_fts(tmp_path)

        result = engine.search("")
        assert result["ok"] is True
        assert result["results"] == []

        result2 = engine.search("   ")
        assert result2["ok"] is True
        assert result2["results"] == []

        engine.close()


class TestFTSEngineRemove:
    def test_remove_paper(self, tmp_path):
        """Removing a paper makes it unsearchable."""
        engine = _make_engine_with_plain_fts(tmp_path)

        class Q:
            def __init__(self, number, text):
                self.number = number
                self.text = text

        engine.index_paper("paper_rm", "text", [Q("1", "Differentiation of polynomials")])

        # Verify it is searchable
        result = engine.search("Differentiation")
        assert len(result["results"]) > 0

        # Remove and verify
        engine.remove_paper("paper_rm")
        result2 = engine.search("Differentiation")
        assert len(result2["results"]) == 0

        engine.close()


class TestFTSEngineStats:
    def test_stats_empty(self, tmp_path):
        """Stats on empty index returns zero counts."""
        db_path = str(tmp_path / "test_fts.db")
        engine = FTSEngine(db_path=db_path)
        engine.initialize()

        stats = engine.get_stats()
        assert stats["ok"] is True
        assert stats["total_papers"] == 0
        assert stats["total_questions"] == 0

        engine.close()

    def test_stats_after_indexing(self, tmp_path):
        """Stats reflect indexed papers and questions."""
        engine = _make_engine_with_plain_fts(tmp_path)

        class Q:
            def __init__(self, number, text):
                self.number = number
                self.text = text

        engine.index_paper("p1", "text", [Q("1", "Question one text"), Q("2", "Question two text")])
        engine.index_paper("p2", "text", [Q("1", "Another paper question")])

        stats = engine.get_stats()
        assert stats["ok"] is True
        assert stats["total_papers"] == 2
        assert stats["total_questions"] == 3

        engine.close()

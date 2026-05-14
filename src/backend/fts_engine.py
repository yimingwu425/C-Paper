"""Full-text search engine using SQLite FTS5."""
import json
import os
import sqlite3
import time
from dataclasses import dataclass, asdict


@dataclass
class SearchResult:
    paper_id: str
    question_number: str
    snippet: str
    rank: float
    metadata: dict

    def to_dict(self):
        return asdict(self)


class FTSEngine:
    """SQLite FTS5 full-text search engine for OCR-extracted text."""

    def __init__(self, db_path=""):
        self._db_path = db_path or os.path.join(os.path.expanduser("~"), ".cie_cache", "cpaper_fts.db")
        os.makedirs(os.path.dirname(self._db_path), exist_ok=True)
        self._conn = None

    def _get_conn(self):
        if self._conn is None:
            self._conn = sqlite3.connect(self._db_path)
            self._conn.execute("PRAGMA journal_mode=WAL")
        return self._conn

    def initialize(self):
        """Create FTS5 virtual table and auxiliary tables."""
        conn = self._get_conn()
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
                year,
                content=papers_meta,
                content_rowid=rowid
            );
        """)
        conn.commit()

    def index_paper(self, paper_id, full_text, questions, metadata=None):
        """Index a paper's text for full-text search."""
        conn = self._get_conn()
        meta = metadata or {}

        # Upsert metadata
        conn.execute(
            """INSERT OR REPLACE INTO papers_meta (paper_id, subject, year, season, filename, indexed_at)
               VALUES (?, ?, ?, ?, ?, datetime('now'))""",
            (paper_id, meta.get("subject", ""), meta.get("year", 0), meta.get("season", ""), meta.get("filename", ""))
        )

        # Delete old FTS entries for this paper
        conn.execute("DELETE FROM papers_fts WHERE paper_id = ?", (paper_id,))

        # Insert questions
        for q in questions:
            text = q.text if hasattr(q, 'text') else q.get('text', '')
            num = q.number if hasattr(q, 'number') else q.get('number', '')
            conn.execute(
                "INSERT INTO papers_fts (paper_id, question_number, text, subject, year) VALUES (?, ?, ?, ?, ?)",
                (paper_id, num, text, meta.get("subject", ""), meta.get("year", 0))
            )

        conn.commit()
        return {"ok": True, "indexed": len(questions)}

    def search(self, query, limit=20):
        """Full-text search across all indexed papers."""
        if not query.strip():
            return {"ok": True, "results": []}

        conn = self._get_conn()

        try:
            rows = conn.execute(
                """SELECT paper_id, question_number,
                          snippet(papers_fts, 2, '<mark>', '</mark>', '...', 32) as snip,
                          rank
                   FROM papers_fts
                   WHERE papers_fts MATCH ?
                   ORDER BY rank
                   LIMIT ?""",
                (query, limit)
            ).fetchall()
        except sqlite3.OperationalError:
            # FTS query syntax error, try simple LIKE fallback
            rows = conn.execute(
                """SELECT paper_id, question_number,
                          substr(text, 1, 200) as snip,
                          0.0 as rank
                   FROM papers_fts
                   WHERE text LIKE ?
                   LIMIT ?""",
                (f"%{query}%", limit)
            ).fetchall()

        results = []
        for row in rows:
            results.append(SearchResult(
                paper_id=row[0],
                question_number=row[1],
                snippet=row[2] or "",
                rank=row[3],
                metadata={},
            ).to_dict())

        return {"ok": True, "results": results}

    def remove_paper(self, paper_id):
        """Remove a paper from the index."""
        conn = self._get_conn()
        conn.execute("DELETE FROM papers_fts WHERE paper_id = ?", (paper_id,))
        conn.execute("DELETE FROM papers_meta WHERE paper_id = ?", (paper_id,))
        conn.commit()
        return {"ok": True}

    def get_stats(self):
        """Get index statistics."""
        conn = self._get_conn()
        try:
            paper_count = conn.execute("SELECT COUNT(*) FROM papers_meta").fetchone()[0]
            question_count = conn.execute("SELECT COUNT(*) FROM papers_fts").fetchone()[0]
        except Exception:
            paper_count = 0
            question_count = 0

        return {
            "ok": True,
            "total_papers": paper_count,
            "total_questions": question_count,
            "db_path": self._db_path,
        }

    def close(self):
        """Close the database connection."""
        if self._conn:
            self._conn.close()
            self._conn = None

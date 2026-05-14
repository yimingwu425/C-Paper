import json
import os
import pytest
from backend.ai_analyzer import AIAnalyzer, AnalysisResult


def _make_analyzer(tmp_path):
    """Create an AIAnalyzer instance with all paths redirected to tmp_path."""
    analyzer = AIAnalyzer.__new__(AIAnalyzer)
    analyzer._cache_dir = str(tmp_path / "ai_cache")
    analyzer._config_path = str(tmp_path / "ai_config.json")
    analyzer._provider = ""
    analyzer._api_key = ""
    analyzer._model = ""
    analyzer._base_url = ""
    os.makedirs(analyzer._cache_dir, exist_ok=True)
    return analyzer


class TestAIAnalyzerConfigure:
    def test_configure_openai(self, tmp_path):
        """Configuring OpenAI saves provider, key, and model."""
        analyzer = _make_analyzer(tmp_path)

        result = analyzer.configure("openai", "sk-test123456789", "gpt-4o-mini")
        assert result["ok"] is True

        # Verify config file was written
        with open(analyzer._config_path) as f:
            data = json.load(f)
        assert data["provider"] == "openai"
        assert data["api_key"] == "sk-test123456789"
        assert data["model"] == "gpt-4o-mini"
        assert "openai.com" in data["base_url"]

    def test_configure_anthropic(self, tmp_path):
        """Configuring Anthropic saves provider, key, model, and base_url."""
        analyzer = _make_analyzer(tmp_path)

        result = analyzer.configure("anthropic", "sk-ant-test123456789", "claude-sonnet-4-20250514")
        assert result["ok"] is True

        with open(analyzer._config_path) as f:
            data = json.load(f)
        assert data["provider"] == "anthropic"
        assert data["api_key"] == "sk-ant-test123456789"
        assert "anthropic.com" in data["base_url"]

    def test_configure_unknown_provider(self, tmp_path):
        """Configuring an unknown provider returns an error."""
        analyzer = _make_analyzer(tmp_path)

        result = analyzer.configure("unknown_provider", "key", "model")
        assert result["ok"] is False
        assert "Unknown provider" in result["error"]


class TestAIAnalyzerGetConfig:
    def test_get_config_masks_key(self, tmp_path):
        """get_config returns masked API key, not the raw key."""
        analyzer = _make_analyzer(tmp_path)
        analyzer._provider = "openai"
        analyzer._api_key = "sk-abcdefghijklmnop1234"
        analyzer._model = "gpt-4o-mini"
        analyzer._base_url = "https://api.openai.com/v1"

        config = analyzer.get_config()
        assert config["ok"] is True
        assert config["provider"] == "openai"
        assert config["has_key"] is True
        # The raw key must NOT appear in the masked output
        assert "sk-abcdefghijklmnop1234" not in config["api_key_masked"]
        # But parts of it should
        assert config["api_key_masked"].startswith("sk-")
        assert config["api_key_masked"].endswith("234")
        assert "***" in config["api_key_masked"]

    def test_get_config_no_key(self, tmp_path):
        """get_config shows has_key=False when no key is set."""
        analyzer = _make_analyzer(tmp_path)

        config = analyzer.get_config()
        assert config["has_key"] is False
        assert config["api_key_masked"] == "***"


class TestAIAnalyzerMaskKey:
    def test_mask_key_short(self, tmp_path):
        """Short keys return '***'."""
        analyzer = _make_analyzer(tmp_path)

        assert analyzer._mask_key("") == "***"
        assert analyzer._mask_key("abc") == "***"
        assert analyzer._mask_key("1234567") == "***"  # 7 chars < 8

    def test_mask_key_normal(self, tmp_path):
        """Normal-length keys show first 3 and last 3 chars."""
        analyzer = _make_analyzer(tmp_path)

        masked = analyzer._mask_key("sk-1234567890abcdef")
        assert masked == "sk-***def"
        assert len(masked) < len("sk-1234567890abcdef")


class TestAIAnalyzerParseResponse:
    def test_parse_valid_json(self, tmp_path):
        """Parses valid AnalysisResult JSON."""
        analyzer = _make_analyzer(tmp_path)
        raw = json.dumps({
            "paper_info": {"subject": "Mathematics", "year": 2024, "season": "Jun"},
            "topics": [{"name": "Calculus", "questions": [1, 2], "total_marks": 20}],
            "difficulty_distribution": {"easy": 3, "medium": 5, "hard": 2},
            "repeated_from_previous": [],
            "summary": "This paper covers calculus and algebra topics.",
        })
        result = analyzer._parse_response(raw, "test-model", 1500)
        assert result is not None
        assert isinstance(result, AnalysisResult)
        assert result.paper_info["subject"] == "Mathematics"
        assert result.topics[0]["name"] == "Calculus"
        assert result.model == "test-model"
        assert result.elapsed_ms == 1500
        assert result.summary == "This paper covers calculus and algebra topics."

    def test_parse_json_in_markdown(self, tmp_path):
        """Extracts JSON from markdown code block."""
        analyzer = _make_analyzer(tmp_path)
        raw = """Here is the analysis:
```json
{
    "paper_info": {"subject": "Physics", "year": 2023},
    "topics": [],
    "difficulty_distribution": {"easy": 1, "medium": 2, "hard": 1},
    "repeated_from_previous": [],
    "summary": "Physics paper analysis."
}
```"""
        result = analyzer._parse_response(raw, "model", 500)
        assert result is not None
        assert result.paper_info["subject"] == "Physics"
        assert result.summary == "Physics paper analysis."

    def test_parse_invalid(self, tmp_path):
        """Returns None for garbage input that contains no parseable JSON."""
        analyzer = _make_analyzer(tmp_path)
        result = analyzer._parse_response("this is not json at all", "model", 100)
        assert result is None

    def test_parse_json_without_markdown(self, tmp_path):
        """Extracts JSON object embedded in surrounding text."""
        analyzer = _make_analyzer(tmp_path)
        raw = """Sure, here is the analysis:
{"paper_info": {"subject": "Chemistry", "year": 2024}, "topics": [], "difficulty_distribution": {}, "repeated_from_previous": [], "summary": "Chemistry analysis complete."}
Hope this helps!"""
        result = analyzer._parse_response(raw, "model", 200)
        assert result is not None
        assert result.paper_info["subject"] == "Chemistry"

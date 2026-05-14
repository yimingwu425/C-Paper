"""AI paper analyzer using LLM APIs."""
import json
import hashlib
import os
import re
import time
from dataclasses import dataclass, asdict, field
from typing import Callable, Optional

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False


@dataclass
class AnalysisResult:
    paper_info: dict
    topics: list
    difficulty_distribution: dict
    repeated_from_previous: list
    summary: str
    raw_response: str = ""
    model: str = ""
    elapsed_ms: int = 0

    def to_dict(self):
        return asdict(self)


class AIAnalyzer:
    """AI paper analysis engine using LLM APIs."""

    PROVIDERS = {
        "openai": {
            "name": "OpenAI",
            "base_url": "https://api.openai.com/v1",
            "models": ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"],
        },
        "anthropic": {
            "name": "Anthropic",
            "base_url": "https://api.anthropic.com",
            "models": ["claude-sonnet-4-20250514", "claude-haiku-4-20250514"],
        },
        "qwen": {
            "name": "通义千问",
            "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "models": ["qwen-turbo", "qwen-plus", "qwen-max"],
        },
    }

    SYSTEM_PROMPT = """你是一个 CIE (Cambridge International Education) 试卷分析专家。
请分析以下试卷文本，返回严格的 JSON 格式结果。

输出 JSON schema:
{
  "paper_info": {"subject": str, "year": int, "season": str, "paper_number": int, "total_marks": int, "question_count": int},
  "topics": [{"name": str, "questions": [int], "total_marks": int}],
  "difficulty_distribution": {"easy": int, "medium": int, "hard": int},
  "repeated_from_previous": [{"question": int, "similar_to": str, "similarity": float}],
  "summary": str
}

注意:
1. summary 用中文撰写
2. topics 按考点分类（如 Differentiation, Integration, Statistics 等）
3. difficulty 基于题目复杂度和知识点综合判断
4. 如果无法确定某些字段，使用 null
5. 仅返回 JSON，不要包含其他文本"""

    def __init__(self, cache_dir=""):
        self._cache_dir = cache_dir or os.path.join(os.path.expanduser("~"), ".cie_cache", "ai_results")
        self._config_path = os.path.join(os.path.expanduser("~"), ".cie_cache", "ai_config.json")
        os.makedirs(self._cache_dir, exist_ok=True)

        self._provider = ""
        self._api_key = ""
        self._model = ""
        self._base_url = ""

        self._load_config()

    def configure(self, provider, api_key, model, base_url=""):
        """Configure LLM provider."""
        if provider not in self.PROVIDERS and provider != "custom":
            return {"ok": False, "error": f"Unknown provider: {provider}"}

        self._provider = provider
        self._api_key = api_key
        self._model = model
        self._base_url = base_url or self.PROVIDERS.get(provider, {}).get("base_url", "")

        self._save_config()
        return {"ok": True}

    def get_config(self):
        """Get current config with masked API key."""
        return {
            "ok": True,
            "provider": self._provider,
            "model": self._model,
            "base_url": self._base_url,
            "api_key_masked": self._mask_key(self._api_key),
            "has_key": bool(self._api_key),
        }

    def test_connection(self):
        """Test API connection with a simple request."""
        if not self._api_key:
            return {"ok": False, "error": "未配置 API Key"}

        if not HAS_REQUESTS:
            return {"ok": False, "error": "requests 库未安装"}

        try:
            if self._provider == "anthropic":
                resp = requests.post(
                    f"{self._base_url}/v1/messages",
                    headers={
                        "x-api-key": self._api_key,
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json",
                    },
                    json={
                        "model": self._model,
                        "max_tokens": 10,
                        "messages": [{"role": "user", "content": "Say OK"}],
                    },
                    timeout=15,
                )
                if resp.status_code == 200:
                    return {"ok": True, "model": self._model}
                return {"ok": False, "error": f"API error: {resp.status_code}"}
            else:
                resp = requests.post(
                    f"{self._base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self._model,
                        "max_tokens": 10,
                        "messages": [{"role": "user", "content": "Say OK"}],
                    },
                    timeout=15,
                )
                if resp.status_code == 200:
                    return {"ok": True, "model": self._model}
                return {"ok": False, "error": f"API error: {resp.status_code} - {resp.text[:200]}"}
        except requests.exceptions.ConnectionError:
            return {"ok": False, "error": "网络连接失败"}
        except requests.exceptions.Timeout:
            return {"ok": False, "error": "请求超时"}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def analyze_paper(self, text, paper_info=None, progress_cb=None):
        """Analyze exam paper text using LLM."""
        if not self._api_key:
            return {"ok": False, "error": "未配置 API Key，请先在设置中配置"}

        if not HAS_REQUESTS:
            return {"ok": False, "error": "requests 库未安装"}

        # Check cache
        cache_key = hashlib.md5(text[:1000].encode()).hexdigest()
        cached = self._load_cache(cache_key)
        if cached:
            if progress_cb:
                progress_cb(1, 1, "使用缓存结果")
            return {"ok": True, "result": cached.to_dict(), "cached": True}

        start = time.time()

        if progress_cb:
            progress_cb(0, 1, "正在调用 AI 分析...")

        # Truncate if too long (rough token estimate: 1 token ≈ 4 chars)
        max_chars = 48000  # ~12000 tokens
        if len(text) > max_chars:
            text = text[:max_chars] + "\n\n[文本已截断...]"

        try:
            raw = self._call_llm(text, paper_info)
        except Exception as e:
            return {"ok": False, "error": f"API 调用失败: {str(e)}"}

        elapsed = int((time.time() - start) * 1000)

        # Parse response
        result = self._parse_response(raw, self._model, elapsed)
        if result:
            self._save_cache(cache_key, result)
            if progress_cb:
                progress_cb(1, 1, "分析完成")
            return {"ok": True, "result": result.to_dict(), "cached": False}
        else:
            return {"ok": False, "error": "AI 返回格式无法解析", "raw": raw[:500]}

    def get_cached_result(self, paper_id):
        """Get cached analysis result."""
        cache_key = hashlib.md5(paper_id.encode()).hexdigest()
        result = self._load_cache(cache_key)
        if result:
            return {"ok": True, "result": result.to_dict()}
        return {"ok": False, "error": "no cache"}

    def _call_llm(self, text, paper_info):
        """Call LLM API and return raw response text."""
        user_msg = f"试卷文本:\n\n{text}"
        if paper_info:
            user_msg = f"试卷信息: {json.dumps(paper_info, ensure_ascii=False)}\n\n{user_msg}"

        if self._provider == "anthropic":
            return self._call_anthropic(user_msg)
        else:
            return self._call_openai_compatible(user_msg)

    def _call_openai_compatible(self, user_msg):
        """Call OpenAI-compatible API."""
        resp = requests.post(
            f"{self._base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self._api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": self._model,
                "messages": [
                    {"role": "system", "content": self.SYSTEM_PROMPT},
                    {"role": "user", "content": user_msg},
                ],
                "temperature": 0.3,
                "max_tokens": 4096,
            },
            timeout=120,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]

    def _call_anthropic(self, user_msg):
        """Call Anthropic API."""
        resp = requests.post(
            f"{self._base_url}/v1/messages",
            headers={
                "x-api-key": self._api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={
                "model": self._model,
                "max_tokens": 4096,
                "system": self.SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": user_msg}],
                "temperature": 0.3,
            },
            timeout=120,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["content"][0]["text"]

    def _parse_response(self, raw, model, elapsed):
        """Parse LLM response into AnalysisResult."""
        # Try direct JSON parse
        try:
            data = json.loads(raw)
            return AnalysisResult(
                paper_info=data.get("paper_info", {}),
                topics=data.get("topics", []),
                difficulty_distribution=data.get("difficulty_distribution", {}),
                repeated_from_previous=data.get("repeated_from_previous", []),
                summary=data.get("summary", ""),
                raw_response=raw,
                model=model,
                elapsed_ms=elapsed,
            )
        except json.JSONDecodeError:
            pass

        # Try extracting JSON from markdown code block
        m = re.search(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', raw)
        if m:
            try:
                data = json.loads(m.group(1))
                return AnalysisResult(
                    paper_info=data.get("paper_info", {}),
                    topics=data.get("topics", []),
                    difficulty_distribution=data.get("difficulty_distribution", {}),
                    repeated_from_previous=data.get("repeated_from_previous", []),
                    summary=data.get("summary", ""),
                    raw_response=raw,
                    model=model,
                    elapsed_ms=elapsed,
                )
            except json.JSONDecodeError:
                pass

        # Try finding JSON object in text
        m = re.search(r'\{[\s\S]*"summary"[\s\S]*\}', raw)
        if m:
            try:
                data = json.loads(m.group(0))
                return AnalysisResult(
                    paper_info=data.get("paper_info", {}),
                    topics=data.get("topics", []),
                    difficulty_distribution=data.get("difficulty_distribution", {}),
                    repeated_from_previous=data.get("repeated_from_previous", []),
                    summary=data.get("summary", ""),
                    raw_response=raw,
                    model=model,
                    elapsed_ms=elapsed,
                )
            except json.JSONDecodeError:
                pass

        return None

    def _mask_key(self, key):
        """Mask API key for display."""
        if not key or len(key) < 8:
            return "***"
        return key[:3] + "***" + key[-3:]

    def _load_config(self):
        """Load config from disk."""
        try:
            if os.path.exists(self._config_path):
                with open(self._config_path, 'r') as f:
                    data = json.load(f)
                    self._provider = data.get("provider", "")
                    self._api_key = data.get("api_key", "")
                    self._model = data.get("model", "")
                    self._base_url = data.get("base_url", "")
        except Exception:
            pass

    def _save_config(self):
        """Save config to disk."""
        try:
            os.makedirs(os.path.dirname(self._config_path), exist_ok=True)
            with open(self._config_path, 'w') as f:
                json.dump({
                    "provider": self._provider,
                    "api_key": self._api_key,
                    "model": self._model,
                    "base_url": self._base_url,
                }, f)
        except Exception:
            pass

    def _load_cache(self, key):
        """Load cached analysis result."""
        path = os.path.join(self._cache_dir, f"{key}.json")
        if os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                return AnalysisResult(**data)
            except Exception:
                pass
        return None

    def _save_cache(self, key, result):
        """Save analysis result to cache."""
        path = os.path.join(self._cache_dir, f"{key}.json")
        try:
            with open(path, 'w') as f:
                json.dump(result.to_dict(), f, ensure_ascii=False)
        except Exception:
            pass

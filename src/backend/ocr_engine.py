"""OCR engine for extracting text from PDF exam papers.

Converts PDF pages to images via pdfplumber, preprocesses with Pillow,
runs Tesseract OCR, then post-processes and splits into structured questions.

Dependencies: pdfplumber, Pillow, pytesseract (all optional at import time).
"""
import hashlib
import json
import os
import re
import time
from dataclasses import dataclass, field, asdict
from typing import Callable, Optional

try:
    import pdfplumber
    from PIL import Image, ImageFilter
    import pytesseract
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Question:
    """A single question extracted from an exam paper."""
    number: str          # e.g. "1", "2(a)"
    text: str            # extracted text
    marks: str           # e.g. "[5 marks]" or ""
    page: int            # page number (1-indexed)
    formula_positions: list = field(default_factory=list)


@dataclass
class OCRResult:
    """Full OCR output for a PDF document."""
    full_text: str
    pages: list          # list of page texts (str)
    questions: list      # list of Question
    metadata: dict       # page_count, dpi, elapsed_ms, etc.

    def to_dict(self) -> dict:
        d = asdict(self)
        d["questions"] = [asdict(q) for q in self.questions]
        return d


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

class OCREngine:
    """PDF OCR engine.

    Pipeline: PDF -> page images -> preprocessing -> Tesseract -> postprocessing -> structured text.

    Parameters
    ----------
    tesseract_cmd : str
        Path to tesseract binary. Empty string uses system default.
    lang : str
        Tesseract language, default ``"eng"``.
    dpi : int
        Resolution used when rasterising PDF pages.
    cache_dir : str
        Directory for JSON cache files. Defaults to ``~/.cie_cache/ocr_results``.
    """

    def __init__(
        self,
        tesseract_cmd: str = "",
        lang: str = "eng",
        dpi: int = 300,
        cache_dir: str = "",
    ) -> None:
        self._tesseract_cmd = tesseract_cmd
        self._lang = lang
        self._dpi = dpi
        self._cache_dir = cache_dir or os.path.join(
            os.path.expanduser("~"), ".cie_cache", "ocr_results"
        )
        os.makedirs(self._cache_dir, exist_ok=True)

        if tesseract_cmd and HAS_DEPS:
            pytesseract.pytesseract.tesseract_cmd = tesseract_cmd

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def is_available(self) -> bool:
        """Return *True* if all OCR dependencies are importable and Tesseract is reachable."""
        if not HAS_DEPS:
            return False
        try:
            pytesseract.get_tesseract_version()
            return True
        except Exception:
            return False

    def extract_text(
        self, pdf_path: str, progress_cb: Optional[Callable] = None
    ) -> OCRResult:
        """Extract full text from *pdf_path*.

        Parameters
        ----------
        pdf_path : str
            Path to the PDF file.
        progress_cb : callable, optional
            ``cb(current_page, total_pages, message)`` called after each page.

        Returns
        -------
        OCRResult
        """
        if not HAS_DEPS:
            return OCRResult("", [], [], {"error": "dependencies not installed"})

        # Check cache first
        cache_key = self._file_hash(pdf_path)
        cached = self._load_cache(cache_key)
        if cached:
            if progress_cb:
                progress_cb(1, 1, "Loaded from cache")
            return cached

        start = time.time()
        pages_text: list[str] = []
        questions: list[Question] = []

        try:
            with pdfplumber.open(pdf_path) as pdf:
                total = len(pdf.pages)
                for i, page in enumerate(pdf.pages):
                    if progress_cb:
                        progress_cb(i + 1, total, f"Processing page {i + 1}/{total}")

                    # Render page to image
                    img = page.to_image(resolution=self._dpi).original

                    # Preprocess
                    img = self._preprocess(img)

                    # OCR
                    text = pytesseract.image_to_string(
                        img, lang=self._lang, config="--oem 3 --psm 6"
                    )
                    text = self._postprocess(text)
                    pages_text.append(text)

                    # Extract questions from this page
                    page_questions = self._split_questions(text, i + 1)
                    questions.extend(page_questions)
        except Exception as e:
            return OCRResult("", [], [], {"error": str(e)})

        full_text = "\n\n".join(pages_text)
        elapsed = int((time.time() - start) * 1000)

        result = OCRResult(
            full_text=full_text,
            pages=pages_text,
            questions=questions,
            metadata={
                "page_count": len(pages_text),
                "dpi": self._dpi,
                "elapsed_ms": elapsed,
                "file": os.path.basename(pdf_path),
            },
        )

        # Persist to cache
        self._save_cache(cache_key, result)

        if progress_cb:
            progress_cb(len(pages_text), len(pages_text), "Done")

        return result

    def extract_questions(
        self, pdf_path: str, progress_cb: Optional[Callable] = None
    ) -> list[Question]:
        """Convenience wrapper: return only the extracted questions."""
        result = self.extract_text(pdf_path, progress_cb)
        return result.questions

    def get_cached(self, pdf_path: str) -> Optional[OCRResult]:
        """Return a previously cached :class:`OCRResult` for *pdf_path*, or *None*."""
        cache_key = self._file_hash(pdf_path)
        return self._load_cache(cache_key)

    # ------------------------------------------------------------------
    # Image preprocessing
    # ------------------------------------------------------------------

    def _preprocess(self, img) -> "Image.Image":
        """Preprocess image: grayscale -> denoise -> binarize."""
        if not isinstance(img, Image.Image):
            img = Image.fromarray(img)

        # Convert to grayscale
        img = img.convert("L")

        # Denoise with median filter
        img = img.filter(ImageFilter.MedianFilter(size=3))

        # Binarize
        threshold = 128
        img = img.point(lambda x: 255 if x > threshold else 0, "1")

        return img

    # ------------------------------------------------------------------
    # Text post-processing
    # ------------------------------------------------------------------

    def _postprocess(self, text: str) -> str:
        """Clean OCR output and mark formula-like patterns as ``[formula]``."""
        if not text:
            return ""

        # Mark formula-like patterns
        formula_patterns = [
            r"[∫∑√∏∂∇±×÷≈≠≤≥∞πθαβγδε]",
            r"\b(?:dx|dy|dz|dt)\b",
            r"\d+\s*/\s*\d+",       # fractions
            r"[a-z]\s*\^\s*\d+",    # superscripts
        ]
        for pat in formula_patterns:
            text = re.sub(pat, "[formula]", text)

        # Fix common OCR misreads inside words
        text = re.sub(r"(?<=[a-zA-Z])1(?=[a-zA-Z])", "l", text)  # 1 -> l
        text = re.sub(r"(?<=[a-zA-Z])0(?=[a-zA-Z])", "O", text)  # 0 -> O

        # Normalise whitespace
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r"[ \t]+", " ", text)

        return text.strip()

    # ------------------------------------------------------------------
    # Question splitting
    # ------------------------------------------------------------------

    def _split_questions(self, text: str, page_num: int) -> list[Question]:
        """Split *text* into :class:`Question` objects by number patterns."""
        questions: list[Question] = []

        # Match patterns like: 1.  2(a)  Question 3  Q4
        pattern = r"(?:Question\s+|Q)?(\d+(?:\s*\([a-z]\))?)\s*[\.\[:]"

        parts = re.split(f"({pattern})", text)

        current_num: Optional[str] = None
        current_text = ""

        for part in parts:
            m = re.match(pattern, part)
            if m:
                # Save previous question
                if current_num and current_text.strip():
                    marks = self._extract_marks(current_text)
                    questions.append(
                        Question(
                            number=current_num,
                            text=current_text.strip(),
                            marks=marks,
                            page=page_num,
                        )
                    )
                current_num = m.group(1)
                current_text = ""
            else:
                current_text += part

        # Save last question
        if current_num and current_text.strip():
            marks = self._extract_marks(current_text)
            questions.append(
                Question(
                    number=current_num,
                    text=current_text.strip(),
                    marks=marks,
                    page=page_num,
                )
            )

        return questions

    @staticmethod
    def _extract_marks(text: str) -> str:
        """Return the mark allocation substring (e.g. ``[5 marks]``) or ``""``."""
        m = re.search(r"\[(\d+)\s*marks?\]", text, re.IGNORECASE)
        return m.group(0) if m else ""

    # ------------------------------------------------------------------
    # File-hash cache helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _file_hash(path: str) -> str:
        """Compute MD5 hex digest of the file at *path*."""
        h = hashlib.md5()
        try:
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    h.update(chunk)
        except Exception:
            h.update(path.encode())
        return h.hexdigest()

    def _load_cache(self, key: str) -> Optional[OCRResult]:
        """Load a cached :class:`OCRResult` from disk, or *None*."""
        path = os.path.join(self._cache_dir, f"{key}.json")
        if not os.path.exists(path):
            return None
        try:
            with open(path, "r") as f:
                data = json.load(f)
            questions = [Question(**q) for q in data.get("questions", [])]
            return OCRResult(
                full_text=data["full_text"],
                pages=data["pages"],
                questions=questions,
                metadata=data.get("metadata", {}),
            )
        except Exception:
            return None

    def _save_cache(self, key: str, result: OCRResult) -> None:
        """Persist *result* to the on-disk cache."""
        path = os.path.join(self._cache_dir, f"{key}.json")
        try:
            with open(path, "w") as f:
                json.dump(result.to_dict(), f, ensure_ascii=False)
        except Exception:
            pass

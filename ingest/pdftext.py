"""Extract conservative, source-quoted facts from scheme guideline PDFs.

Nothing here is inferred: every fact keeps the sentence it came from, and
anything ambiguous is left out so the app shows it as unknown.
"""
from __future__ import annotations

import io
import re

import pdfplumber

from common import clean

LAKH = 100_000
RS = r"(?:Rs\.?|₹|INR)\s*"
NUM = r"([\d][\d,]*(?:\.\d+)?)"


def pdf_to_text(data: bytes, max_pages: int = 12) -> str:
    try:
        with pdfplumber.open(io.BytesIO(data)) as pdf:
            return "\n".join((p.extract_text() or "") for p in pdf.pages[:max_pages])
    except Exception:  # corrupt / scanned PDFs: no text, no facts
        return ""


def sentences(text: str) -> list[str]:
    flat = clean(text.replace("\n", " "))
    return [s.strip() for s in re.split(r"(?<=[.;])\s+(?=[A-Z0-9(])", flat) if s.strip()]


def _to_rupees(num: str, unit: str | None) -> float | None:
    try:
        v = float(num.replace(",", ""))
    except ValueError:
        return None
    if unit and unit.lower().startswith(("lakh", "lac")):
        v *= LAKH
    return v


def extract_income_limit(text: str):
    """Return (rupees, sentence) for the first sentence stating a family-income ceiling."""
    for s in sentences(text):
        if not re.search(r"income", s, re.I):
            continue
        if not re.search(r"(not\s+(?:exceed|more\s+than|be\s+more)|up\s*to|upto|less\s+than|below|within|maximum|ceiling)", s, re.I):
            continue
        m = re.search(RS + NUM + r"\s*(lakhs?|lacs?)?", s, re.I)
        if m:
            v = _to_rupees(m.group(1), m.group(2))
            if v and 10_000 <= v <= 50 * LAKH:
                return v, s[:400]
    return None


def extract_amount(text: str):
    """Return (amount, period, sentence) only when the sentence has exactly one rupee figure."""
    for s in sentences(text):
        if not re.search(r"(per\s+annum|per\s+year|p\.a\.|per\s+month|monthly|annually)", s, re.I):
            continue
        if re.search(r"income", s, re.I) or not re.search(r"(scholarship|stipend|fellowship|rate|amount|assistance)", s, re.I):
            continue
        if len(s) > 350:  # un-split run of text: not a single quotable sentence
            continue
        figs = {_to_rupees(m.group(1), m.group(2)) for m in re.finditer(RS + NUM + r"\s*(lakhs?|lacs?)?", s, re.I)}
        figs.discard(None)
        if len(figs) == 1:
            period = "per_month" if re.search(r"per\s+month|monthly", s, re.I) else "per_year"
            return figs.pop(), period, s[:400]
    return None


def looks_like_toc(chunk: str) -> bool:
    """Table-of-contents / numbered-heading runs are not prose."""
    if re.search(r"\.{4,}", chunk):
        return True
    nums = len(re.findall(r"(?:^|\s)\d{1,2}(?:\.\d{1,2})*\s+[A-Z]", chunk))
    digits = sum(c.isdigit() for c in chunk) / max(1, len(chunk))
    return nums >= 4 or digits > 0.12


def _first_prose(text: str, heading: str, limit: int, min_len: int) -> str | None:
    for m in re.finditer(rf"(?im)^[ \t]*(?:\d+(?:\.\d+)*[.)]?[ \t]*)?{heading}[^\n]{{0,40}}\n", text):
        chunk = clean(text[m.end(): m.end() + limit * 2])[:limit]
        if len(chunk) >= min_len and not looks_like_toc(chunk):
            return chunk
    return None


def extract_eligibility_excerpt(text: str, limit: int = 900) -> str | None:
    """Verbatim prose following an 'Eligibility' heading, if present."""
    return _first_prose(text, r"eligibility", limit, 80)


def extract_objective(text: str, limit: int = 500) -> str | None:
    return _first_prose(text, r"objectives?", limit, 60)

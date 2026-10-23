"""National Scholarship Portal adapter.

Reads the public "All Scholarships" page (server-rendered HTML) for every
scheme's name, ministry, application window and guideline links, then reads
each guideline PDF for quoted eligibility facts.
"""
from __future__ import annotations

import re
from datetime import datetime
from urllib.parse import urljoin

from bs4 import BeautifulSoup, NavigableString, Tag

from common import Fetcher, clean, ist_end, ist_start, slug
from pdftext import (extract_amount, extract_eligibility_excerpt, extract_income_limit, extract_objective,
                     pdf_to_text)

SOURCE_ID = "nsp"
PAGE = "https://scholarships.gov.in/All-Scholarships"
APPLY = "https://scholarships.gov.in/ApplicationForm/"

DATE = r"(\d{2}-\d{2}-\d{4})"

# Schemes outside Naviq's audience (school level) are skipped.
SKIP = re.compile(r"\bpre[\s-]*matric\b|\bin schools\b|\bschool\b|means[\s-]*cum[\s-]*merit", re.I)
GROUP = re.compile(
    r"girl|specially|disabilit|minorit|scheduled|\bobc\b|\bebc\b|\bdnt\b|\bsc\b|\bst\b|armed|forces|rifles|police|"
    r"martyr|jammu|ladakh|swanath|beedi|cine|iomc|lsdm|railway|\bner\b|ishan|tribal|wards|welfare|\bscs\b|\bobcs\b|"
    r"indian statistical", re.I)
FIELD = [  # (pattern, label) — schemes limited to a field of study
    (re.compile(r"icar|agricultur", re.I), "agriculture and allied subjects"),
    (re.compile(r"renewable energy", re.I), "renewable energy"),
]
PG = re.compile(r"post[\s-]*graduate|\(pgs\)|nts-pg|\bpg\b|\bjrf\b|\bsrf\b|junior research|senior research", re.I)
DIPLOMA = re.compile(r"diploma", re.I)
PG_DEGREES = ["M.Tech", "M.E.", "M.Sc", "MCA", "MBA", "MA", "M.Com", "M.Pharm", "MS"]


def _tokens(soup: BeautifulSoup):
    for el in soup.body.descendants:
        if isinstance(el, Tag) and el.name == "a" and el.get("href"):
            yield ("l", clean(el.get_text(" ")), el["href"])
        elif isinstance(el, NavigableString) and el.parent.name not in ("a", "script", "style", "title"):
            t = clean(str(el))
            if t:
                yield ("t", t)


def parse_page(html: str):
    """Return a list of dicts: ministry, name, windows, spec/faq links."""
    soup = BeautifulSoup(html, "lxml")
    toks = list(_tokens(soup))
    schemes, buf, ministry = [], [], None
    i = 0
    while i < len(toks):
        kind, *rest = toks[i]
        if kind == "t" and re.match(r"Scheme\s+Open from", rest[0]):
            # Collect this scheme's date lines and guideline links.
            window = {"fresh": {}, "renewal": {}}
            links = {}
            j = i
            while j < len(toks):
                k2, *r2 = toks[j]
                if k2 == "t":
                    t = r2[0]
                    which = "renewal" if "Renewal" in t else "fresh"
                    if re.match(r"Scheme\s+Open from", t) and "open" in window[which]:
                        break  # next scheme's block started without a FAQ link
                    m = re.search(DATE, t)
                    if m and re.match(r"Scheme\s+Open from", t):
                        window[which]["open"] = m.group(1)
                    elif m and re.match(r"Student Application", t):
                        window[which]["close"] = m.group(1)
                    elif m and re.match(r"Institute Verification", t):
                        window[which]["inst"] = m.group(1)
                elif k2 == "l" and r2[0] in ("Specifications", "FAQ"):
                    links[r2[0]] = urljoin(PAGE, r2[1])
                    if r2[0] == "FAQ":
                        j += 1
                        break
                j += 1
            # Page order is: scheme name, "<h6>by Ministry</h6>", then the dates.
            name = None
            for k, (_, txt) in enumerate(reversed(buf[-4:])):
                m = re.match(r"<h6>\s*by\s+(.*?)\s*</h6>", txt, re.I)
                if m:
                    ministry = m.group(1)
                    rest = list(reversed(buf[-4:]))[k + 1:]
                    name = rest[0][1] if rest else None
                    break
            if name:
                schemes.append({"ministry": ministry, "name": name, "window": window, "links": links})
            buf = []
            i = j
            continue
        if kind == "t":
            buf.append(("t", rest[0]))
        i += 1
    return schemes


def _title_case(name: str) -> str:
    n = clean(name)
    n = re.sub(r"\s*\(\s*(Merit|Welfare|Need)\s*Based\s*Scheme\s*\)?\s*$", "", n, flags=re.I)
    n = re.sub(r"\(\s+", "(", n)
    n = re.sub(r"\s+\)", ")", n)
    return n.strip()


def _stem(links: dict, name: str) -> str:
    href = links.get("Specifications") or links.get("FAQ") or ""
    stem = href.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    stem = re.sub(r"_[GF]$", "", stem)
    return stem or slug(name)


def build_record(s: dict, fetcher: Fetcher, now: datetime):
    name = _title_case(s["name"])
    if SKIP.search(name):
        return None
    w = s["window"]
    main = w["fresh"] if w["fresh"].get("close") else w["renewal"]
    renewal_only = not w["fresh"].get("close") and bool(w["renewal"].get("close"))
    if not main.get("close"):
        return None  # no stated window; never guess
    ext = f"nsp:{slug(name)}"
    title = f"{name} 2026-27" if not re.search(r"20\d\d", name) else name
    title = f"{title} — Renewal only" if renewal_only else title

    rules, docs = [], []
    description_parts = [
        f"Listed on the National Scholarship Portal under {s['ministry'] or 'the Government of India'}. "
        f"Application window: {main.get('open', '?')} to {main['close']}"
        + (f"; institute verification till {main['inst']}." if main.get("inst") else ".")
    ]
    award = None
    additional = []
    spec = s["links"].get("Specifications")
    note = "Dates read from the NSP All Scholarships page."
    if spec:
        additional.append({"label": "Scheme guidelines (PDF on NSP)", "url": spec})
        try:
            text = pdf_to_text(fetcher.get(spec, binary=True, max_age_hours=24 * 7))
        except Exception as e:  # PDF unavailable: keep scheme with dates only
            text, note = "", note + f" Guideline PDF could not be read ({type(e).__name__})."
        if text:
            obj = extract_objective(text)
            if obj:
                description_parts.append(f"Objective (from the guidelines): {obj}")
            elig = extract_eligibility_excerpt(text)
            if elig:
                description_parts.append(f"Eligibility (quoted from the guidelines): {elig}")
            inc = extract_income_limit(text)
            if inc:
                rules.append({"key": "income", "kind": "max_family_income", "label": f"Family income not above ₹{inc[0]:,.0f} per annum",
                              "mandatory": True, "numberValue": inc[0], "sourceExcerpt": inc[1]})
            amt = extract_amount(text)
            if amt:  # quoted only: one sentence may be just one of several rates
                award = {"amount": None, "currency": "INR", "period": None, "description": f"From the guidelines: {amt[2]}"}
            note += " Eligibility and amount quoted automatically from the guideline PDF; some guideline PDFs on NSP are for earlier years."

    if GROUP.search(name):
        rules.append({"key": "target_group", "kind": "self_declared", "mandatory": True, "restrictsAudience": True,
                      "label": f"You belong to the group this scheme is for (see the scheme name: {name})",
                      "note": "Naviq doesn't collect or infer personal categories. Confirm this yourself."})
    for pat, field in FIELD:
        if pat.search(name):
            rules.append({"key": "field_of_study", "kind": "self_declared", "mandatory": True, "restrictsAudience": True,
                          "label": f"Your field of study is {field} (see the scheme name: {name})",
                          "note": "This scheme is limited to a specific field of study. Confirm it applies to you."})
    rules.append({"key": "guidelines", "kind": "self_declared", "mandatory": True,
                  "label": "You meet every eligibility condition in the official scheme guidelines",
                  "note": "Naviq read only part of the guidelines automatically. Read them on the official source."})
    if renewal_only:
        rules.append({"key": "existing_awardee", "kind": "self_declared", "mandatory": True, "restrictsAudience": True,
                      "label": "You already hold this scholarship (only renewals are open)"})

    degrees = []
    if DIPLOMA.search(name):
        degrees = ["Diploma"]
    elif PG.search(name) and not re.search(r"under[\s-]*graduate", name, re.I):
        degrees = PG_DEGREES

    return {
        "externalId": ext,
        "title": title,
        "organization": s["ministry"] or "National Scholarship Portal (Government of India)",
        "opportunityType": "fellowship" if re.search(r"fellowship|\bjrf\b|\bsrf\b", name, re.I) else "scholarship",
        "officialDescription": " ".join(description_parts)[:3900],
        "sourceUrl": PAGE,
        "applicationUrl": APPLY,
        "additionalSources": additional,
        "sourceType": "government_portal",
        "verificationStatus": "verified",
        "lastVerifiedAt": now.isoformat(),
        "verifiedBy": "naviq-ingest:nsp",
        "verificationNotes": note.strip(),
        "declaredStatus": "open",
        "applicationOpensAt": ist_start(main["open"]) if main.get("open") else None,
        "deadline": ist_end(main["close"]),
        "deadlineNote": "Student application deadline on NSP." + (f" Institute verification till {main['inst']}." if main.get("inst") else ""),
        "eligibleDegrees": degrees,
        "eligibleYears": [],
        "eligibleBranches": [],
        "requiredSkills": [],
        "preferredSkills": [],
        "location": {"country": "India", "isNationwide": True},
        "workMode": "not_applicable",
        "award": award,
        "stipend": None,
        "eligibilityRules": rules,
        "requiredDocuments": docs,
        "tags": ["scholarship", "government", "nsp"] + (["fellowship"] if "fellowship" in name.lower() else []),
        "status": "published",
    }


def run(fetcher: Fetcher, now: datetime):
    html = fetcher.get(PAGE)
    schemes = parse_page(html)
    records, skipped = [], 0
    for s in schemes:
        rec = build_record(s, fetcher, now)
        if rec:
            records.append(rec)
        else:
            skipped += 1
    return records, f"{len(schemes)} schemes on page, {len(records)} imported, {skipped} skipped (school-level or no stated window)"

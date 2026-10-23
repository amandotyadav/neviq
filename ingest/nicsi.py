"""NICSI internship programme adapter (public page + notification PDFs)."""
from __future__ import annotations

import re
from datetime import datetime
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from common import Fetcher, clean, ist_end
from pdftext import pdf_to_text, sentences

SOURCE_ID = "nicsi"
PAGE = "https://nicsi.nic.in/nicsi/internship/"
MONTHS = "January February March April May June July August September October November December".split()


def parse_date(s: str) -> str | None:
    s = clean(s).replace(",", "")
    for fmt in ("%d-%m-%Y", "%d/%m/%Y", "%d.%m.%Y", "%d %B %Y", "%d %b %Y", "%B %d %Y"):
        try:
            return datetime.strptime(s, fmt).strftime("%d-%m-%Y")
        except ValueError:
            continue
    return None


def run(fetcher: Fetcher, now: datetime):
    html = fetcher.get(PAGE)
    soup = BeautifulSoup(html, "lxml")
    for t in soup(["script", "style", "nav", "footer"]):
        t.decompose()
    text = clean(soup.get_text(" "))
    pdfs = {clean(a.get_text(" ")) + "|" + a["href"]: urljoin(PAGE, a["href"]) for a in soup.find_all("a", href=re.compile(r"\.pdf$", re.I))}
    notif = next((u for k, u in pdfs.items() if "Notification" in u), None)
    scheme = next((u for k, u in pdfs.items() if "Scheme" in u), None)

    closed = re.search(r"currently closed|applications? for this batch (are|is) closed|application form is currently closed", text, re.I)
    opened = re.search(r"applications? (are |is )?(now )?open|apply now|open for applications", text, re.I)
    status = "closed" if closed and not opened else "open" if opened and not closed else "unknown"

    deadline, desc, stipend, additional = None, [], None, []
    for label, url in (("Internship notification (PDF)", notif), ("Internship scheme (PDF)", scheme)):
        if not url:
            continue
        additional.append({"label": label, "url": url})
        try:
            body = pdf_to_text(fetcher.get(url, binary=True, max_age_hours=24 * 3))
        except Exception:
            continue
        for s in sentences(body):
            if deadline is None:
                m = re.search(r"last\s+date[^.]{0,100}?(\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}\s+[A-Za-z]+,?\s+\d{4})", s, re.I)
                if m and (d := parse_date(m.group(1))):
                    deadline = d
            if stipend is None and re.search(r"stipend", s, re.I) and re.search(r"(Rs\.?|₹)\s*[\d,]+", s):
                stipend = s[:400]
            if len(desc) < 3 and re.search(r"eligib|duration|internship", s, re.I) and len(s) > 60:
                desc.append(s[:350])

    record = {
        "externalId": "nicsi:internship-programme",
        "title": "NICSI Internship Programme",
        "organization": "NICSI (National Informatics Centre Services Inc.)",
        "opportunityType": "internship",
        "officialDescription": ("Quoted from the NICSI internship page and notification: " + " ".join(desc))[:3900] if desc
        else "See the NICSI internship page for current batches, the scheme document and the application form.",
        "sourceUrl": PAGE,
        "applicationUrl": PAGE,
        "additionalSources": additional,
        "sourceType": "government_portal",
        "verificationStatus": "verified",
        "lastVerifiedAt": now.isoformat(),
        "verifiedBy": "naviq-ingest:nicsi",
        "verificationNotes": f"Application status read from the NICSI page on {now.date()}: {status}.",
        "declaredStatus": status,
        "deadline": ist_end(deadline) if deadline else None,
        "deadlineNote": "From the notification PDF." if deadline else "The page does not state a deadline; batches open periodically.",
        "location": {"country": "India", "isNationwide": True},
        "workMode": "unknown",
        "stipend": {"amount": None, "currency": "INR", "period": None, "description": f"From the notification: {stipend}"} if stipend else None,
        "award": None,
        "eligibilityRules": [{"key": "guidelines", "kind": "self_declared", "mandatory": True,
                              "label": "You meet the eligibility conditions in the NICSI internship scheme document",
                              "note": "Read the scheme PDF on the official page."}],
        "requiredDocuments": [],
        "tags": ["internship", "government", "it"],
        "status": "published",
    }
    return [record], f"page status={status}, deadline={deadline or 'not stated'}, pdfs={len(additional)}"

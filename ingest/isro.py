"""ISRO student programmes page (internships run by individual centres)."""
from __future__ import annotations

import re
from datetime import datetime

from bs4 import BeautifulSoup

from common import Fetcher, clean

SOURCE_ID = "isro"
PAGE = "https://www.isro.gov.in/Internship.html"


def run(fetcher: Fetcher, now: datetime):
    soup = BeautifulSoup(fetcher.get(PAGE), "lxml")
    for t in soup(["script", "style", "nav", "footer", "header"]):
        t.decompose()
    lines = [clean(x) for x in soup.get_text("\n").split("\n") if clean(x)]
    para = clean(" ".join(l for l in lines if re.search(r"intern|project|student|centre", l, re.I)))[:1500]
    centres = [{"label": f"Centre page: {a.get_text(' ', strip=True) or a['href']}"[:80], "url": a["href"] if a["href"].startswith("http") else "https://" + a["href"].lstrip("/")}
               for a in soup.find_all("a", href=re.compile(r"sac\.gov|prl\.res|\.gov\.in|\.res\.in", re.I))][:6]
    record = {
        "externalId": "isro:student-internships",
        "title": "ISRO student internships and projects (apply through individual centres)",
        "organization": "Indian Space Research Organisation (ISRO)",
        "opportunityType": "internship",
        "officialDescription": f"From the ISRO page: {para}",
        "sourceUrl": PAGE,
        "applicationUrl": PAGE,
        "additionalSources": centres,
        "sourceType": "government_portal",
        "verificationStatus": "verified",
        "lastVerifiedAt": now.isoformat(),
        "verifiedBy": "naviq-ingest:isro",
        "verificationNotes": "Programme description read from the ISRO page. Each centre sets its own eligibility and dates; none are stated on this page.",
        "declaredStatus": "unknown",
        "deadline": None,
        "deadlineNote": "Dates and eligibility are published by each ISRO centre, not on this page.",
        "location": {"country": "India", "isNationwide": True},
        "workMode": "onsite",
        "eligibilityRules": [{"key": "centre_rules", "kind": "self_declared", "mandatory": True,
                              "label": "You meet the eligibility and dates published by the ISRO centre you apply to"}],
        "requiredDocuments": [],
        "tags": ["internship", "space", "government", "engineering"],
        "status": "published",
    }
    return [record], "programme page captured (rolling; no dates published)"

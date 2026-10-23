"""Science Academies SRFP: refresh the application deadline of the curated record."""
from __future__ import annotations

import re
from datetime import datetime

from common import Fetcher, clean, ist_end
from nicsi import parse_date

SOURCE_ID = "ias"
PAGE = "https://webjapps.ias.ac.in/fellowship2027/application_instructions.jsp"


def run(fetcher: Fetcher, now: datetime):
    text = clean(re.sub(r"<[^>]+>", " ", fetcher.get(PAGE)))
    m = re.search(r"last date for receipt of applications online is\s*(\d{1,2}\s+[A-Za-z]+\s+\d{4})", text, re.I)
    if not m or not (d := parse_date(m.group(1))):
        raise RuntimeError("deadline sentence not found on the page (layout may have changed)")
    return [{
        "externalId": "ias:srfp-2027", "datesOnly": True,
        "deadline": ist_end(d), "declaredStatus": "open",
        "deadlineNote": f"\"{m.group(0)}\"",
        "lastVerifiedAt": now.isoformat(),
    }], f"deadline {d}"

"""AICTE National Internship Portal.

The public listing page ships no data: listings are loaded from /api/, which
the portal's robots.txt disallows for all crawlers. So this adapter fetches
nothing; it records why, and re-checks robots.txt on every run so it can be
enabled if the portal's policy changes (or a data-sharing agreement exists).
"""
from __future__ import annotations

from datetime import datetime

from common import Fetcher

SOURCE_ID = "aicte_internships"


class Skipped(Exception):
    pass


def run(fetcher: Fetcher, now: datetime):
    if not fetcher.allowed("https://internship.aicte-india.org/api/internships"):
        raise Skipped("robots.txt disallows /api/ (the only place listings are served). Not scraped.")
    raise Skipped("robots.txt now permits /api/ — review the portal's terms, then implement this adapter.")

"""Shared helpers: a polite, robots.txt-aware fetcher with an on-disk cache."""
from __future__ import annotations

import hashlib
import re
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

UA = "NaviqBot/1.0 (student opportunity aggregator; honours robots.txt; daily)"
CACHE = Path(__file__).parent / "cache"
IST = "+05:30"


class Blocked(Exception):
    """Raised when robots.txt disallows a URL for our user agent."""


class Robots:
    """robots.txt rules for one host, using longest-match semantics (as major crawlers do)."""

    def __init__(self, body: str):
        self.rules: list[tuple[bool, re.Pattern, int]] = []
        applies, seen_agent_block = False, False
        specific = False
        groups: dict[str, list[tuple[bool, str]]] = {}
        agents: list[str] = []
        for raw in body.splitlines():
            line = raw.split("#", 1)[0].strip()
            if ":" not in line:
                continue
            key, val = (x.strip() for x in line.split(":", 1))
            key = key.lower()
            if key == "user-agent":
                if seen_agent_block:
                    agents, seen_agent_block = [], False
                agents.append(val.lower())
                groups.setdefault(val.lower(), [])
            elif key in ("allow", "disallow"):
                seen_agent_block = True
                for a in agents:
                    groups[a].append((key == "allow", val))
        mine = next((g for a, g in groups.items() if a != "*" and a in UA.lower()), None)
        chosen = mine if mine is not None else groups.get("*", [])
        for allow, path in chosen:
            if path == "":
                continue
            pat = re.escape(path).replace(r"\*", ".*")
            if pat.endswith(r"\$"):
                pat = pat[:-2] + "$"
            self.rules.append((allow, re.compile(pat), len(path)))

    def can_fetch(self, path: str) -> bool:
        best = None
        for allow, pat, length in self.rules:
            if pat.match(path) and (best is None or length > best[1] or (length == best[1] and allow)):
                best = (allow, length)
        return True if best is None else best[0]


class Fetcher:
    def __init__(self, min_interval: float = 1.0):
        self.session = requests.Session()
        self.session.headers["User-Agent"] = UA
        self.min_interval = min_interval
        self._last: dict[str, float] = {}
        self._robots: dict[str, Robots | None] = {}
        CACHE.mkdir(exist_ok=True)

    def _robots_for(self, url: str):
        p = urlparse(url)
        host = f"{p.scheme}://{p.netloc}"
        if host in self._robots:
            return self._robots[host]
        rp = None
        try:
            r = self.session.get(f"{host}/robots.txt", timeout=20)
            body = r.text.strip()
            # Some portals answer with an HTML page instead of robots rules: treat as "no rules".
            if r.status_code == 200 and body and not body.lstrip().startswith("<"):
                rp = Robots(body)
        except requests.RequestException:
            rp = None
        self._robots[host] = rp
        return rp

    def allowed(self, url: str) -> bool:
        rp = self._robots_for(url)
        if rp is None:
            return True
        p = urlparse(url)
        return rp.can_fetch(p.path + (f"?{p.query}" if p.query else ""))

    def _throttle(self, url: str):
        host = urlparse(url).netloc
        wait = self.min_interval - (time.time() - self._last.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        self._last[host] = time.time()

    def get(self, url: str, *, binary: bool = False, max_age_hours: float = 0):
        """GET with robots check, throttling, retries and optional file cache."""
        if not self.allowed(url):
            raise Blocked(f"robots.txt disallows {url}")
        key = CACHE / hashlib.sha1(url.encode()).hexdigest()
        if max_age_hours and key.exists() and (time.time() - key.stat().st_mtime) < max_age_hours * 3600:
            data = key.read_bytes()
            return data if binary else data.decode("utf-8", errors="ignore")
        last_err: Exception | None = None
        for attempt in range(3):
            try:
                self._throttle(url)
                r = self.session.get(url, timeout=40)
                r.raise_for_status()
                if max_age_hours:
                    key.write_bytes(r.content)
                return r.content if binary else r.text
            except requests.RequestException as e:  # noqa: PERF203
                last_err = e
                time.sleep(2 * (attempt + 1))
        raise last_err  # type: ignore[misc]


def ist_start(d: str) -> str:
    """dd-mm-yyyy -> ISO datetime at start of day IST."""
    dd, mm, yy = d.split("-")
    return f"{yy}-{mm}-{dd}T00:00:00{IST}"


def ist_end(d: str) -> str:
    """dd-mm-yyyy -> ISO datetime at end of day IST."""
    dd, mm, yy = d.split("-")
    return f"{yy}-{mm}-{dd}T23:59:59{IST}"


def clean(s: str) -> str:
    return re.sub(r"\s+", " ", s or "").strip()


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")

# Naviq ingest — daily refresh from official sources

Python scrapers collect scholarships and internships; the Node server merges them into MongoDB.

## Setup (once)
```bash
cd /Applications/naviq/ingest
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

## Run
```bash
.venv/bin/python run.py          # scrape only → out/records.json (nothing touches the database)
cd ../server && npm run refresh  # scrape + merge into MongoDB + retire vanished + link check
```
Automatic: the API server runs the refresh daily at 03:00 IST when `ENABLE_DAILY_REFRESH=true`
(default **true in production**, and on in `npm run dev:memory`). `REFRESH_ON_START=true` also runs it at boot.
Alternative: system cron → `0 3 * * * cd /path/to/server && node scripts/daily-refresh.js`.
Each run is stored in the `ingestruns` collection (platform admins: `GET /api/admin/ingest-runs`).

## Sources
| id | what | how |
|---|---|---|
| `nsp` | National Scholarship Portal — every college-level scheme (≈27) | Public HTML page (names, ministry, windows, guideline links) + guideline PDFs parsed with pdfplumber |
| `nicsi` | NICSI internship programme | Public page (batch status) + notification/scheme PDFs |
| `isro` | ISRO student internships (via centres) | Public programme page |
| `ias` | Science Academies SRFP | Refreshes the deadline of the curated record only |
| `aicte_internships` | AICTE National Internship Portal | **Not scraped.** Listings load only from `/api/`, which its robots.txt disallows. Re-checked every run. |

NCS (ncs.gov.in) is a JavaScript app with no static listings and is not scraped. Adding it needs permission or an official feed.

## Rules the scrapers follow
- `robots.txt` is honoured with longest-match semantics (`common.Robots`); 1 request/second/host; identifiable User-Agent; PDFs cached 3–7 days.
- No CAPTCHA/login bypass. School-level schemes (pre-matric, NMMS) are skipped.
- Only quoted facts are stored: income ceilings with the source sentence, amounts as quoted text (never as a number), objective/eligibility prose (table-of-contents text is rejected). Anything uncertain stays unknown.
- Group- or field-restricted schemes (girl students, SC/ST/OBC, disability, agriculture…) get a `restrictsAudience` criterion and are **never recommended** automatically.
- Every auto-ingested scheme has a mandatory "You meet every eligibility condition in the official guidelines" criterion, so it can never read as "all criteria met".

## Merge policy (server/src/ingestion/importer.js)
- New `externalId` → inserted. Auto-ingested record → fully refreshed.
- Hand-verified/admin record → **only dates and status** refreshed (`datesRefreshedAt`), never rules or amounts.
- A listing missing from its source is flagged `needs_review` (not deleted) — unless the source returned < 50% of what we hold (assumed layout change).

## Known limits
- If NSP or a PDF changes layout, parsing degrades to "dates only"; check `ingestruns` for `partial`/`error`.
- NSP still links older guideline PDFs for some schemes; quoted text may predate 2026-27.
- Internship coverage is small (NICSI, ISRO, Science Academies) until AICTE/NCS data can be used with permission.

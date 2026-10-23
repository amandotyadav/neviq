# Naviq — Feature Inventory (built vs. remaining)

Status as of 2026-10-24. Legend: ✅ built and verified · 🟡 built, not fully verified · ❌ not built.

Product: **Naviq — "Your future, better navigated."** AI-powered Smart Campus app for Indian college students.
Stack: native SwiftUI iOS app (`/Applications/naviq/naviq/`) + Node/Express/Mongoose backend (`/Applications/naviq/server/`).

---

## 1. Backend (`server/`) — 69 automated tests passing (Vitest + Supertest + in-memory MongoDB)

### Auth & accounts
- ✅ Register / login / logout / me (`/api/auth/*`). bcrypt hashing, JWT with `tokenVersion` (logout revokes all tokens).
- ✅ Registration is strict: any `role`/admin field is rejected (400). Admins are provisioned only via `npm run admin:create`.
- ✅ Same error for unknown email and wrong password. Auth rate limiting.
- ✅ Profile GET/PATCH (`/api/profile`), account deletion with password confirmation (deletes saved items, applications, roadmaps, drafts).
- ✅ Colleges directory + "my institution isn't listed" (creates unlisted College record).

### Opportunities & real data
- ✅ Opportunity model with source URL, source type, verification status, `lastVerifiedAt`, `verifiedBy`, deadline, per-criterion `eligibilityRules`, award/stipend with currency+period, `dedupeKey`, college scoping.
- ✅ `GET /api/opportunities` with real server-side search/filter (q, type, workMode, location, skills, verifiedOnly, includeClosed, campusOnly, deadlineWithinDays, sort relevance/deadline/recent) + pagination.
- ✅ Visibility rules: students see published public listings + their own college's only; other colleges / drafts return 404.
- ✅ Save/unsave, `/api/saved`.
- ✅ Verified seed dataset (`server/data/verified-opportunities.json`, 6 records): Science Academies SRFP 2027, AICTE Pragati, AICTE Saksham, PM-USP CSSS renewal, Smart India Hackathon 2026 (closed), Google Summer of Code (dates unknown). Each cites an official source; unknown fields left null.
- ✅ 8 curated colleges (`colleges.json`, URLs checked) and 14 learning resources (`resources.json`, URLs returned HTTP 200).
- ✅ Importer with Zod validation, dedupe upsert, rejects "verified" records lacking verifier/date. `npm run seed`.
- ✅ Source link-health checker (`npm run sources:check`) — marks 404/410 sources `needs_review`. (Checks links only, not page facts.)

### Eligibility engine (deterministic, no LLM)
- ✅ Per-criterion met/unmet/unknown with explanation, next step, source excerpt.
- ✅ Overall states: all criteria met / missing information / likely ineligible / insufficient source info.
- ✅ Caveats: closed, deadline unknown, unverified, stale (>30 days).
- ✅ `self_declared` criteria (answers used per-check, never stored). Income/home state only checked if student opted to share.
- ✅ `restrictsAudience` flag (girl-student, disability, existing-awardee criteria): never inferred; such listings are NOT recommended until confirmed, but still appear in Discover with an "Only for: …" reason.
- ✅ Degree/branch alias normalisation (BTech = B.Tech, CSE = Computer Science…).

### Matching & "Your next move"
- ✅ Explainable heuristic score (skills, interests, education, preferences, timing, uncertainty penalty). Labelled "not a probability". Hard-blocked listings always ranked below eligible ones.
- ✅ `/api/matches` = verified + open/upcoming + not blocked + not audience-restricted; reports `excludedIneligible`, `excludedRestricted`.
- ✅ `/api/me/next-moves` and `/api/me/deadlines` built from real tracker/saved/roadmap/profile state. Day counts use IST calendar days (`utils/dates.js`).

### Applications, roadmap, drafts
- ✅ Application tracker CRUD with 9 statuses, status history, notes, deadline, next action + due, archive. Owner-scoped (cross-user → 404). Duplicate opportunity → 409. "Applied" only set by the student.
- ✅ Roadmap: manual milestone create/update/delete (status, priority, target date), persisted, owner-scoped, works without AI.
- ✅ Drafts CRUD (`/api/drafts`), `reviewedAt` gate.

### AI (Saathi) — Google Gemini via official @google/genai SDK (models.generateContent)
- ✅ Provider abstraction (`ai/provider.js`), timeout, 1 retry, error mapping (503 AI_UNAVAILABLE / 504 timeout / 502 invalid output), per-user hourly rate limit.
- ✅ `/api/ai/chat` tool-calling agent: read tools (profile, search, recommendations, opportunity, eligibility, deadlines, next moves, roadmap, applications) run as the signed-in user; write tools are **propose-only** (`propose_save_opportunity`, `propose_track_application`, `propose_generate_roadmap`, `propose_draft_email`) — student confirms in app. Source text marked untrusted.
- ✅ `/api/ai/roadmap` (structured output, Zod-validated, only catalogue resource IDs kept as "verified"), `/api/ai/draft-email`, `/api/ai/resume` (resume / cover letter / summary, `[ADD: …]` placeholders + missingInformation), `/api/ai/explain-match/:id`, `/api/ai/status`.
- ✅ Tested with a fake provider (tool flow, no cross-user leakage, malformed output rejected, provider failure, no key → 503).
- ❌ **Never run against a real Gemini key.** Default model `gemini-3.8-flash` (from Google docs fetched in-session; docs now also describe a newer stateful `interactions` API — we use stateless `models.generateContent`). Set `GEMINI_API_KEY` and verify chat tool-calling, roadmap, and drafts.

### Campus admin
- ✅ Role + college-scoped admin API: list/create/patch opportunities, verify (requires `sourceConfirmed: true`), fact edits reset verification to pending, cannot move listing between colleges, announcements CRUD (draft/published/archived/expiry), `/api/admin/metrics` (aggregates only, counts <3 suppressed, no emails).
- ✅ Student sees only published, unexpired announcements for their own college.
- ✅ Verified end-to-end against the live dev server: admin publishes for KIET → KIET student sees it; other college → 403; student on admin route → 403.

### Platform
- ✅ Zod env validation, Helmet, CORS allow-list, rate limits, central error handler, redacting logger, `/health`, `/ready`, graceful shutdown, `.env.example`, syntax lint script.
- ✅ `npm run dev:memory` — persistent local MongoDB (no install needed), seeds data, optional demo admin.

---

## 2. iOS app (`naviq/`) — builds with zero errors/warnings (Xcode 27.1, iOS 27 target)

### Design system "Naviq Editorial"
- ✅ Semantic colour tokens with dark variants (paper/ink/cobalt/coral/jade/amber), serif editorial titles, tracked-caps kickers, compass-needle logo mark + wordmark (vector, in code), reusable components (rows, deadline/verification labels, chips, flow layout, skeletons, empty/error/notice states, status badges).
- 🟡 Reduce-motion respected in key animations; Dynamic Type via text styles. No formal accessibility audit done; dark mode not visually checked.

### Screens
- ✅ Welcome, register/sign-in (Keychain token, session restore, expired-session handling).
- ✅ 4-step onboarding (college search incl. "not listed", course, skills/interests/goal, preferences + optional private income/state); skippable; shared with Edit Profile.
- ✅ Home: next-move lead card, coming-up deadlines, relevant matches, roadmap progress, campus notices, Ask-Saathi entry, note about held-back group-restricted listings.
- ✅ Discover: search, type chips, filter sheet, sort, infinite pagination, empty/error/skeleton states, official portal links.
- ✅ Opportunity detail: verified facts grid, Save (optimistic + haptic), Track sheet, official-source links (opening never marks applied), "Why this opportunity?" factors + optional AI explanation, **"What am I missing?"** expandable eligibility report with Yes/No self-declaration, documents, drafts.
- ✅ Saathi chat with confirm-before-write action cards (success shown only after server confirms), citations, AI-unavailable handling.
- ✅ Roadmap: generate with AI or add manually, start/pause/complete/reprioritise/target date/delete, verified vs. AI-suggested resources separated.
- ✅ Applications tracker (grouped, detail editor, archive/delete, add external application), Drafts list, draft composer/editor with review gate, share, PDF export.
- ✅ Profile & Settings: edit profile (incl. projects/links), notification prefs, privacy page, developer server-URL, sign out, delete account.
- ✅ Campus admin UI: announcements (draft/publish/archive), listings editor + verify, engagement metrics.
- ✅ Local deadline/next-action reminders (UserNotifications), permission asked at first dated tracking, denied-state banner.

### Verified on the iOS simulator (subagent walkthrough, live backend)
- ✅ Register → onboarding → Home → detail → eligibility Yes → Save → Track → Applications/Roadmap/Saathi/Discover tabs all worked; no crashes.
- 🟡 After that walkthrough these fixes were built but **not re-verified in the UI**: Track sheet now `.large` only (Due toggle previously unreachable at half height), form styling (`naviqForm`), eligibility Yes/No selected-state with checkmark, counts line wording, Roadmap/Saathi AI-unavailable polish, "Only for:" reason lines (partly confirmed on Discover).
- ❌ Admin screens in the iOS UI never exercised on the simulator (API side is verified).
- ❌ Roadmap manual-milestone UI flow not exercised on the simulator (API side tested).

---

## 2b. Automated daily refresh (new)
- ✅ Python scrapers in `ingest/` (NSP page + guideline PDFs via pdfplumber, NICSI, ISRO, Science Academies deadline); `npm run refresh`; in-process scheduler daily 03:00 IST (`ENABLE_DAILY_REFRESH`, default on in production).
- ✅ Discover grew from 6 to ~32 records (27 NSP schemes + NICSI + ISRO). Idempotent (second run: 0 inserts), hand-verified records only get dates refreshed, vanished listings flagged `needs_review`, `IngestRun` history + `GET /api/admin/ingest-runs`.
- ✅ robots.txt honoured with longest-match parser. AICTE internship portal deliberately NOT scraped (listings only via disallowed `/api/`); NCS is a JS app — see `ingest/README.md`.
- ✅ Recommendations now require ≥1 criterion confirmed from the profile; group/field-restricted schemes are held back (still in Discover).
- 🟡 Auto-extracted text is quoted, not interpreted; some PDF excerpts are partial. No iOS UI change except Home footnote wording.
- ❌ Not built: more internship sources (needs permission/feeds), admin UI for run history, alerts on failed runs.

## 3. Remaining work (priority order)

1. **Re-verify on simulator**: Track sheet, eligibility Yes state, roadmap add/start/complete, admin sign-in → publish notice → student sees it on Home.
2. **Real AI test** with `GEMINI_API_KEY` in `server/.env`; confirm model id; test chat tools, roadmap, email drafts end-to-end; tune prompts.
3. **Known UI issues** (from the walkthrough): floating toolbar buttons (compass/profile/back) overlap scrolled content on iOS 27 — adjust toolbar/safe-area; onboarding pickers (graduation year, home state) lack visible labels; CGPA hint hidden behind fixed bottom bar; sign-up spinner overlaps button label; Discover search bar sits above the title; first tap on an eligibility row sometimes scrolls to top; stipend/date text wrapping.
4. **Tests**: no iOS unit/UI tests yet (Swift Testing + XCUITest for onboarding, tabs, save, track, AI-failure states); backend suite is complete for current scope.
5. **Docs**: README/setup, API documentation, deployment guide (Render/Railway + MongoDB Atlas), source-verification guide, judge demo script — `server/docs/` is empty.
6. **Deployment**: MongoDB Atlas + hosted API (HTTPS) and point the app at it (Settings ▸ Developer or Info.plist `NaviqAPIBaseURL`). Currently only local dev works.
7. **Assets**: app icon / launch branding (mark is code-drawn only; AppIcon set is empty).
8. **More verified data**: no verified cybersecurity internship exists in seed (NCIIPC 2026 closed; ISEA is per-university). Research more official sources (NCS, AICTE internship portal needs interactive browsing — no API). Never invent.
9. **Accessibility pass** (VoiceOver labels, Dynamic Type at AX sizes, contrast in dark mode) and Reduce Motion checks.
10. **Optional**: password change/reset, push for announcements, scheduled source refresh job, college admin invitation flow, token-based sign-in alternatives (Sign in with Apple only if fully implemented).

## 4. Honest data caveats
- NSP still links the **2020-21** Pragati/Saksham guideline PDFs for AY 2026-27; recorded in verification notes.
- CSSS listing is **renewal only** for 2026-27 per NSP.
- GSoC next-edition dates unpublished → availability "unknown".
- SIH 2026 nominations closed 9 Oct 2026 (shown as closed).
- Seed `lastVerifiedAt` is 2026-10-23; listings turn "stale" after 30 days — re-verify.

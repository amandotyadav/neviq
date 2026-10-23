# Naviq — Session Handoff (keep this file updated every session)

Give this file + `NAVIQ_FEATURES.md` to the next AI agent. Last updated: 2026-10-24.

## Project layout
```
/Applications/naviq/
  naviq.xcodeproj            Xcode project (file-system-synchronized: new files in naviq/ auto-added)
  naviq/                     SwiftUI app: App/ Core/ Design/ Features/{Auth,Onboarding,Home,Discover,Opportunity,Saathi,Roadmap,Applications,Drafts,Profile,Admin}
  server/                    Node 24 + Express 5 + Mongoose + Zod (ESM, no TypeScript)
    src/{config,middleware,models,routes,services,validators,auth,ai,eligibility,matching,ingestion,utils}
    data/                    verified-opportunities.json, colleges.json, resources.json
    tests/                   Vitest suites (69 tests)  scripts/ seed, create-admin, check-sources, dev-memory, lint
  NAVIQ_FEATURES.md          features built / remaining
  NAVIQ_HANDOFF.md          this file
```
Not a git repository (consider `git init`; add `.gitignore` for `server/.env`, `server/.data`, `node_modules`).

## Daily refresh (scrapers)
`ingest/` (Python venv at `ingest/.venv`, see `ingest/README.md`). `cd server && npm run refresh` runs it now; the server also runs it daily at 03:00 IST (`ENABLE_DAILY_REFRESH`). Dev DB URI for one-off scripts: `MONGODB_URI=mongodb://127.0.0.1:27027/naviq JWT_SECRET=<32+ chars>`. Curated records carry `externalId` (e.g. `nsp:aicte-pragati-…`, `ias:srfp-2027`) so scrapes merge instead of duplicating.

## Run it
```bash
cd /Applications/naviq/server
npm install
npm test                         # 69 tests, in-memory Mongo, expects all pass
npm run lint                     # syntax check
DEMO_ADMIN_PASSWORD='kiet-demo-admin-2026!' npm run dev:memory
#  → local persistent MongoDB (server/.data/mongo, port 27027), seeds data, API on http://localhost:4000
#  → provisions admin campus.admin@kiet.demo for KIET (dev only)
```
Production: copy `.env.example` → `.env`, set `MONGODB_URI` (Atlas), `JWT_SECRET` (32+ chars), optional `GEMINI_API_KEY`, then `npm run seed` and `npm start`.
iOS: open `naviq.xcodeproj`, run on iPhone simulator (reaches `http://localhost:4000`; ATS allows local networking). Physical device → change server URL in Profile ▸ Developer.

## Dev-only accounts (local DB; not secrets worth protecting, rotate if reused anywhere)
- Student: `riya.demo.4817@example.test` / `demo-pass-2026` (KIET, B.Tech CSE yr 2, Python/Linux/Networking, interests Cybersecurity/Research; has a tracked SRFP application)
- Student: `demo.student@example.test` / `demo-pass-123`
- Admin: `campus.admin@kiet.demo` / `kiet-demo-admin-2026!` (college_admin for KIET)
- A "Scholarship help desk this week" KIET notice is already published in the local DB.

## Key design decisions (do not undo)
- Never invent opportunities/deadlines; unknown stays null. Seed records require an official source + verifier + date.
- Eligibility is deterministic; LLM may only narrate it. Group-restricted criteria (`restrictsAudience`) are never inferred and block recommendations until the student confirms.
- Saathi write actions are propose-only; the app executes them after the student taps Confirm and shows success only on server confirmation.
- Opening an external link never changes application status. "Applied" is student-set only.
- Admin privileges only via `scripts/create-admin.js`; every admin route re-checks role + college on the server.
- Income/home state: optional, used only in eligibility checks, never sent to the LLM or shown to admins.
- Admin metrics: aggregates only, counts < 3 hidden.
- Day counts use IST calendar days on both server (`utils/dates.js`) and app (`Dates.daysUntil`).

## Tooling gotchas
- Swift 6-style isolation: model types are `nonisolated`; project default actor isolation is MainActor. `@State` is a macro in SDK 27 (don't pre-assign + reassign in init).
- Use `navigationDestination` outside lazy containers.
- `JSONBody.object([...])` builds request bodies; use `NSNull()` for explicit null.
- Device interaction through Xcode MCP must run in a subagent; sessions expire (~20 min) — start a new session (`DeviceInteractionStartWorkspaceSession`) then `InstallAndRun`.
- The Bash tool occasionally fails with "PreToolUse hook did not respond"; retrying or using Edit/Write works.
- Subagent rate limits were hit in the last session; keep simulator walkthroughs short and targeted.

## Last known state
- Backend: 80/80 tests pass (incl. refresh/merge/scheduler). iOS: last `BuildProject` succeeded (before the final `countsLine` edit in `EligibilityReportView.swift` — **rebuild first**).
- Dev server may not be running; restart with the command above.
- Last subagent walkthrough was cut off by a rate limit while on the Profile → Sign out step; steps 2–6 of the pending verification list were not completed.

## Next steps (in order)
1. `BuildProject`; fix any errors.
2. Start the dev server; run a short simulator pass: eligibility Yes/No state, Track sheet (large), Roadmap manual milestone start/complete, admin sign-in → publish notice → student sees it.
3. Fix UI issues listed in `NAVIQ_FEATURES.md` §3.3.
4. Test AI with a real `GEMINI_API_KEY` (verify model id).
5. Write README, API docs (`server/docs/API.md`), deployment guide, source-verification guide, judge demo script.
6. Add iOS tests, app icon, accessibility pass, Atlas + hosted deployment.
7. Update this file and `NAVIQ_FEATURES.md` after each step.

## Judge demo path (works today without AI)
Register → onboarding (KIET, B.Tech CSE, year 2, cybersecurity/research) → Home shows SRFP as top verified match (honest: no verified cybersecurity internship exists) → open it, follow official link, see "What am I missing?" → Save + Track with next action → Applications shows deadline → admin publishes campus notice → student Home shows it. With an AI key add: Saathi "what should I do next?", roadmap generation, email draft.

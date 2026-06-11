# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace overview

This is a collection of independent web projects, each in its own subfolder. There is no shared build system or monorepo tooling — each project is self-contained.

| Project | Stack | Entry point |
|---|---|---|
| Amex Credits Maximizer | React 19 + TS 6 + Vite 8 + Tailwind v4 | `src/` |
| behavioral-prep | Next.js 16 + React 19 + shadcn/ui + Drizzle (libSQL) + ts-fsrs + Anthropic SDK | `app/` (port 5960) — STAR story bank for MBA behavioral interview prep, auth |
| Dream Career Picker | Python/Flask + Vercel Edge | `server.py` / `api/careers.js` |
| Foundry | Next.js 16 + React 19 + Drizzle (libSQL) + Anthropic SDK + MDX | `app/` (own `README.md`, port 5900) — "zero to scale" startup learning app, auth |
| Golf range | Vanilla HTML/Canvas | `index.html` (open directly) |
| Golf swing assessor | Vanilla HTML/JS + MediaPipe Tasks Vision | `index.html` (serve via http, port 5800) |
| Google extensions/Tab Grouper | Chrome MV3 extension | load unpacked via `chrome://extensions` |
| Famous Quotes | React 18 + TS + Vite + Tailwind + react-router | `src/` (port 5850) |
| History Learning Platform | React 18 + TS + Vite + Tailwind + react-simple-maps | `src/` |
| italian-tutor | Next.js 15 + React 19 + Drizzle (libSQL) + Anthropic SDK | `app/` (own `CLAUDE.md`) |
| language-tutor | Next.js 16 + React 19 + Drizzle (libSQL) + Anthropic SDK | `app/` (own `CLAUDE.md`) — Italian+French combined, auth, port 5620 |
| Job finder app | Vanilla HTML | `job-ledger_5.html` (open directly) |
| Learn Claude Code | Vanilla HTML | `index.html` (open directly) |
| personal-finance-tracker | React 18 + TS + Vite + Tailwind | `src/` |
| Personal Doctor | React 18 + TS + Vite + Tailwind + Recharts + Vercel Edge | `src/` / `api/analyze.js` |
| PeOps-Prep | Next.js 16 + React 19 + shadcn/ui + Drizzle (libSQL) + ts-fsrs + Anthropic SDK | `app/` (own `CLAUDE.md`, port 5550) — PE portfolio-ops interview prep, FSRS + quizzes + AI-graded cases, per-user auth |
| PGA Championship Tracker | React 18 + TS + Vite + Tailwind | `src/` |
| Post-MBA Career Explorer | React 18 + TS + Vite + Tailwind | `src/` (data in `src/data/careers.ts`) |
| Penalty shootout | Vanilla HTML/SVG + Vercel KV | `index.html` (open directly) |
| quant-stock-trading | Python 3.12 + uv + Makefile (pandas/quant) | `make` targets (own `README.md`) |
| Resume website | Vanilla HTML | `index.html` (open directly) |
| Santorini website | Vanilla HTML | `santorini.html` (open directly) |
| Stadium Run | Vanilla HTML + Three.js + Vercel KV | `index.html` (open directly) |
| Startup Idea Generator | Python/Flask + Vercel Edge | `server.py` / `api/ideas.js` |
| Tower defense game | Vanilla HTML/Canvas | `index.html` (open directly) |
| Travel Itinerary App | Vanilla HTML/JS + Node dev server + Claude `api/` | `server.js` (port 5400, own `CLAUDE.md`) |
| World Cup Bracket Picker | Python/Flask + Vercel serverless | `server.py` / `api/` |

## Running projects locally

**Vanilla HTML projects** (Golf range, Job finder app, Resume website, Santorini website, Tower defense game): open the HTML file directly in a browser — no server needed.

**Flask projects** (Dream Career Picker, World Cup Bracket Picker, Startup Idea Generator):
```bash
pip3 install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...
python3 server.py
```

**React/Vite projects** (Amex Credits Maximizer, PGA Championship Tracker, personal-finance-tracker) — `node` is at `/opt/homebrew/bin/node`, not on PATH by default:
```bash
PATH=/opt/homebrew/bin:$PATH npm run dev      # Vite dev server
PATH=/opt/homebrew/bin:$PATH npm run build    # tsc + Vite production build
PATH=/opt/homebrew/bin:$PATH npm run lint     # ESLint
PATH=/opt/homebrew/bin:$PATH npm install      # install deps
```

Preview ports: `amex-credits` → 5175, `pga-tracker` → 5173, `finance-tracker` → 5174, `personal-doctor` → 5177, `stadium-run` → 5350, `career-explorer` → 5250.

**Next.js projects** (italian-tutor, language-tutor, foundry, PeOps-Prep, behavioral-prep) — `npm run dev` (Next dev server), `npm run build`, `npm run lint`. Use Drizzle ORM over libSQL; the tutor apps + foundry + behavioral-prep + PeOps-Prep use **per-user email/password auth** (jose JWT + bcryptjs, `proxy.ts` route guard); see each project's own `CLAUDE.md`/`AGENTS.md`/`README.md`. Ports: `italian-tutor` → 5600, `language-tutor` → 5620 (combined Italian+French, dark-slate login, `[lang]` routing), `foundry` → 5900 (startup learning app — MDX curriculum + Anthropic AI mentor/VC-tracker; for local dev `TURSO_DATABASE_URL=file:local.db` works), `PeOps-Prep` → 5550 (PE portfolio-ops interview prep — Tailwind v4 + **shadcn/ui**, ts-fsrs spaced repetition, quiz engine, AI-graded cases; per-user auth — `lib/user.ts`'s `currentUserId()` is now async, returning `requireAuth()`; `file:local.db` for dev), `behavioral-prep` → 5960 (STAR story bank for MBA behavioral recruiting — stories ↔ seeded 84-question bank with per-pairing "angle" notes, company/industry Targets with per-target answers, FSRS practice decks, AI story coach + question matcher; auth; `file:local.db` for dev — note `TURSO_AUTH_TOKEN` must be non-empty even for the file DB).

**Shared scripts** (`_scripts/`): `add-auth.sh` scaffolds the italian-tutor auth pattern (session lib, login/register/account pages, route guard) into *another* Next.js App Router + Drizzle/Turso app, then prints the manual per-schema steps. It does **not** apply to Flask, vanilla-HTML, or localStorage-only React apps — those store progress per-browser already (no shared backend to gate). Read the script header before running.

**Node dev-server project** (travel-app): `node server.js` (port 5400) serves the static HTML and proxies `api/` to Claude; needs `ANTHROPIC_API_KEY` in the environment.

**Python/uv project** (quant-stock-trading): `make setup` (uv sync), `make test`, `make backtest`/`make momentum`/`make factor`, `make notebook`. Requires `python@3.12` + `uv`. Has its own `README.md`.

Several larger projects carry their own per-project `CLAUDE.md` (Golf swing assessor, italian-tutor, language-tutor, travel-app) — read it before working in that subfolder.

**Tailwind v4 note (Amex Credits Maximizer only)**: uses `@tailwindcss/vite` plugin instead of PostCSS. All theme customization (colors, fonts) is done via `@theme { }` in `src/index.css` — there is no `tailwind.config.js`. The `shadcn` CLI was used to initialize CSS variables and dark-theme base styles; `src/lib/utils.ts` exports the `cn()` helper. However, no shadcn UI primitive components (Card, Button, Badge, etc.) are installed in `src/components/ui/` — all component styling uses raw Tailwind classes directly.

**TypeScript strict mode** applies to all Vite projects (`noUnusedLocals`, `noUnusedParameters`). Prefix unused parameters with `_` rather than deleting them from function signatures.

## Deployment pattern

All deployed projects use **Vercel** via GitHub auto-deploy (push to `main` → redeploy). `ANTHROPIC_API_KEY` must be set in Vercel Project Settings → Environment Variables for any project using Claude.

- **Amex Credits Maximizer**: Vite SPA → `dist/` → Vercel. Has `vercel.json` with `/* → /index.html` rewrite for client-side routing. Deployed at `amex-credits-maximizer.vercel.app`.
- **Dream Career Picker**: dual-target — Flask for local, Vercel Edge (`api/careers.js`) for production. `index.html` and `public/index.html` are identical; keep both in sync when editing the UI. Same for the Claude prompt in `server.py:build_prompt()` and `api/careers.js:buildPrompt()`.
- **World Cup Bracket Picker**: Flask for local; `api/simulate.py` and `api/final.py` are Vercel Python serverless functions for production.
- **PGA Championship Tracker**: Vite build → `dist/` → Vercel SPA (rewrite `/* → /index.html`).
- **behavioral-prep**: Next.js → Vercel at `behavioral-prep.vercel.app` (project `behavioral-prep`, GitHub `aidanlconnolly/behavioral-prep` auto-deploy). Own Turso DB `behavioral-prep`. Env: `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, `AUTH_SECRET`, `ANTHROPIC_API_KEY` (optional — AI coach/matcher hide without it).
- **Santorini website**: source is `santorini.html` here; deploy by copying to `/tmp/santorini-guide/index.html`, then committing to the `aidanlconnolly/santorini-guide` repo.

## Preview server

`.claude/launch.json` in this working directory configures the Claude Code preview tool. Current entries: `World Cup Bracket` (3000), `pga-tracker` (5173), `finance-tracker` (5174), `amex-credits` (5175), `personal-doctor` (5177), `tower-defense` (5200), `penalty-shootout` (5300), `stadium-run` (5350), `travel-app` (5400), `learn-claude-code` (5500), `italian-tutor` (5600), `rankings` (5700), `history-platform` (5750), `golf-swing` (5800), `famous-quotes` (5850), `foundry` (5900), `peops-prep` (5550). Add new entries here when a project needs a preview server. Note: a couple of entries serve from `/tmp` (`rankings`, `stadium-run`) — those are scratch preview copies, not the source of truth.

## Chrome extensions (`Google extensions/`)

Each extension lives in its own subfolder and is a self-contained Chrome Manifest V3 package. To load during development:
1. `chrome://extensions` → enable **Developer mode**
2. **Load unpacked** → select the extension's subfolder

**Tab Grouper** (`Google extensions/Tab Grouper/`): groups open tabs by hostname. Key files:
- `background.js` — service worker; listens to `chrome.tabs.onCreated` / `onUpdated`, debounces 800 ms, then calls `chrome.tabs.group()` + `chrome.tabGroups.update()`. Colors assigned by `hashColor(hostname)`.
- `popup.js` — same grouping logic runs directly from the popup context (no message passing needed); reads/writes `autoGroup` flag via `chrome.storage.local`.
- `create-icons.js` — one-time Node script (`node create-icons.js`) that writes `icons/icon{16,48,128}.png` from raw pixel data; only needs re-running if icons change.

## Architecture patterns used across projects

**Single-file apps**: Golf range, Tower defense game, Santorini website, Resume website, and Job finder app are entirely self-contained HTML files with inline `<style>` and `<script>`. No build step, no external dependencies (except CDN fonts where noted).

**Canvas games** (Golf range, Tower defense game): game state lives in a single `state` object reset by a `createState()` factory. Game loop runs via `requestAnimationFrame` with delta-time (`dt`) so speed multipliers work by scaling `dt` rather than changing tick rate.

**Claude API streaming**: Dream Career Picker streams SSE from both Flask (`/api/careers`) and the Vercel edge function. The client reads the stream via `fetch` + `ReadableStream` (not `EventSource`) since the request is a POST. Each chunk is `data: "<text>"\n\n`; the sentinel is `data: [DONE]\n\n`.

**URL state sharing**: World Cup Bracket Picker encodes the full bracket in the URL hash (client-side only). PGA Championship Tracker encodes picks in URL params, synced to `localStorage` on every change.

**localStorage + custom hook pattern** (Amex Credits Maximizer, personal-finance-tracker): state lives entirely in `localStorage`. A single `useXxx` hook (e.g. `useCredits`) owns all state: it loads from storage on mount, exposes granular updater functions, and calls `saveState()` on every change. Pure business logic (date math, derived values) lives in `src/lib/` and is imported by the hook — components stay free of logic and only call hook functions.

**Static data files** (Amex Credits Maximizer `src/data/benefits.ts`, PGA Tracker `src/data/players.ts`): the source of truth for domain constants is a typed TS file, not fetched from an API. Keep these in sync when benefit amounts or player data change.

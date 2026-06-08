# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Santorini Travel Guide

Single self-contained HTML file (`santorini.html` / deployed as `index.html`) — no build step, no dependencies except Google Fonts (Cormorant Garamond + Lato via CDN).

```bash
open santorini.html   # preview locally
```

### Deploy workflow

`santorini.html` is the source of truth here. It deploys to a separate GitHub repo at `/tmp/santorini-guide/` as `index.html`:

```bash
cp santorini.html /tmp/santorini-guide/index.html
cd /tmp/santorini-guide
git add index.html && git commit -m "..." && git push origin main
# Vercel auto-deploys from aidanlconnolly/santorini-guide → production
```

Always edit `santorini.html` here, then copy-commit-push. Never edit `/tmp/santorini-guide/index.html` directly.

### Architecture

Everything is inline in one `<style>` block and one `<script>` tag. Sections in order: `#hero` → `#atvs` → `#beaches` → `#cliff-jump` → `#hotels` → `#restaurants` → `#tips` → `footer`.

**CSS patterns:**
- All colors as `:root` custom properties (`--navy`, `--gold`, `--warm-white`, etc.)
- `.fade-in` / `.fade-in.visible` — Intersection Observer drives scroll animations; `transition-delay` set per nth-child for card grids
- `#navbar.scrolled` — JS-toggled class adds `backdrop-filter: blur` once hero scrolls out of view
- Section backgrounds use `background-image: linear-gradient(...), url(...)` so a dark overlay sits on top of the photo

**Photos:**
All images are Unsplash via `https://images.unsplash.com/photo-{ID}?auto=format&fit=crop&w={w}&q=80`. Width is 1920 for full-bleed sections, 800 for beach cards, 600 for hotel card headers, 400 for restaurant thumbnails. Before adding a new photo ID, verify it exists: `curl -I "https://images.unsplash.com/photo-{ID}?w=10"`.

**Hotel cards** are `<a>` tags linking to each hotel's direct booking page. Card image lives in `.hotel-card-img` (a `div` with `background-image`), content in `.hotel-card-body`.

**Restaurant items** use a two-column grid: `.restaurant-img` (200px thumbnail) + `.restaurant-text` (text + link). Fine dining has direct website links; casual spots link to Google Maps search URLs.

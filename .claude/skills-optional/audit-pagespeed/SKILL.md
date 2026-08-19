---
name: audit-pagespeed
description: Use when the developer says 'audit pagespeed', 'run pagespeed', 'check pagespeed insights', 'test on pagespeed.web.dev', 'are we 100', or 'why are we not 100' — drives pagespeed.web.dev with the Playwright MCP, lifts the full Lighthouse JSON for BOTH form factors straight off the page, and turns every failing audit into a source-mapped fix list tied to the metric it actually moves. Carries the full road-to-100 playbook (dead-weight audit, prototype discipline, variance math, the automated 100-hunt).
model: opus
---

# audit-pagespeed — real PageSpeed Insights scores, with the failing elements

Google's own scoring, on the deployed URL, for **mobile and desktop in one run** — then every
failing audit resolved down to the file that causes it. This skill also carries the
**road-to-100 playbook** learned the hard way (a full day, 40+ samples, 4 prototyped levers):
follow it in order and the next project gets there in hours, not a day.

## Trigger

- `"audit pagespeed"` / `"run pagespeed"` / `"check pagespeed insights"`
- `"test on pagespeed.web.dev"` / `"are we 100 on pagespeed"` / `"why are we not 100"`

## Prerequisites

- **Playwright MCP** (`mcp__playwright__*`). If a call fails with "not configured", prompt:
  "The Playwright MCP isn't set up — run `/setup-mcp playwright`, then re-run."
- A **publicly reachable deployed URL**. PSI is a hosted service; it cannot see `localhost`.
  Target: [GROUND: this project's canonical production URL, e.g. `https://example.com`].

---

## Step 0 — Do NOT reach for the PSI REST API first

`pagespeedonline.googleapis.com/.../runPagespeed` looks like the clean path. Without an API key it
runs on a **shared anonymous quota that is usually already exhausted** (`429 Quota exceeded`).
**Drive the web UI instead** — no quota, and (Step 2) it hands you the same Lighthouse JSON the API
would. Use the REST API only if the developer has set a real `PAGESPEED_API_KEY`.

## Step 1 — Run the analysis

Deep-link straight to the result so no form interaction is needed:

```
https://pagespeed.web.dev/analysis?url=<URL-ENCODED-TARGET>&form_factor=mobile
```

Analysis takes **30–60 s**; `wait_for({text:'Performance'})` fires on the page *shell* — too early.
Wait for real scores. **One run covers both form factors.**

Two Google-side failure modes to expect (seen repeatedly): the desktop lane errors with
_"failed to retrieve the LHR"_ while mobile succeeds (treat desktop as optional per sample, retry
later), and whole-service degraded windows (stalls, absurd outliers like a desktop 78 after ten
100s). When PSI itself is sick, stop sampling and say so — don't diagnose the site with a broken
ruler.

## Step 2 — Extract the full Lighthouse JSON (the whole trick)

The rendered report is painful to scrape and truncates element tables. **The complete LHR for both
form factors is on `window`:**

```js
mcp__playwright__browser_evaluate({ function: `() => {
  const out = {};
  for (const [k, lhr] of [['mobile', window.__LIGHTHOUSE_MOBILE_JSON__],
                          ['desktop', window.__LIGHTHOUSE_DESKTOP_JSON__]]) {
    if (!lhr) { out[k] = null; continue; }
    const scores = {};
    for (const c of Object.keys(lhr.categories))
      scores[lhr.categories[c].title] = Math.round(lhr.categories[c].score * 100);
    const failing = [];
    for (const [id, a] of Object.entries(lhr.audits)) {
      if (a.score !== null && a.score < 1) failing.push({
        id, score: a.score, title: a.title, displayValue: a.displayValue,
        items: a.details?.items?.slice(0, 10),
      });
    }
    out[k] = { fetchTime: lhr.fetchTime, scores, failing };
  }
  return out;
}`, filename: 'lhr-both.json' })
```

Pass `filename:` so the payload lands in a file, then parse it with a short `node -e` script.
`fetchTime` is your freshness proof — PSI caches; identical fetchTime = one analysis served twice.
Failing a11y/BP items carry a `node` (`selector`, `snippet`, `nodeLabel`) — grep the repo for the
`nodeLabel` text to land on the source. Read the **whole** report including "unscored" insights:
they name real causes (a non-composited `text-shadow` animation on the LCP element was found there,
not in any scored audit).

## Step 3 — The score math, including the 100-point endgame

**Performance = 0.30·TBT + 0.25·LCP + 0.25·CLS + 0.10·FCP + 0.10·SI** (each metric scored 0–1 on a
log-normal curve, sum ×100). INSIGHTS/DIAGNOSTICS are advisory — tie every fix to the metric it
moves, or it moved nothing. Never report "fixed 6 diagnostics" as progress.

**The endgame arithmetic:** the displayed score rounds the weighted sum, so 100 needs **≥ 99.5**.
With TBT and CLS at 1.0 (achievable and mandatory), FCP+LCP+SI must average ~0.99. Google's
calculator (googlechrome.github.io/lighthouse/scorecalc) shows *rounded* metric scores — a run the
calculator displays as "100" can truly be 99.4x and print 99. Do the math with raw `numericValue`s.

**Deterministic-ceiling detection — the single most valuable diagnostic:** collect 10+ samples and
look at the *clean* rolls (low TBT). If a metric repeats the **exact same millisecond value** run
after run (e.g. LCP = 1876ms thirteen times), that is not variance — it is a structural byte on the
simulated critical path, and no amount of re-rolling will print 100. Find the bytes (Step 4).
If clean rolls straddle 99/100 instead, you're at the rounding knife-edge — sample, don't operate.

The other three categories are pass/fail sums — clear every failing audit and they pin at 100.

## Step 4 — AUDIT FOR DEAD WEIGHT FIRST (the day-saver)

**Before optimizing how anything loads, verify it actually renders.** The costliest field lesson: a
site carried a complete self-hosted web-font pipeline — subset faces, two `<head>` preloads, ~35KB
on every cold visit — for a font that **never painted a single glyph** (a CSS-framework default
family utility on a root wrapper had overridden it since day one). That dead weight sat in the
pre-LCP window and WAS the deterministic mobile-99. Removing it: LCP −500ms, instant quad-100.

Run this on the live page before anything else:

```js
// In a mobile-emulated Playwright page, after load+3s:
() => ({
  lcpFont: getComputedStyle(document.querySelector('<LCP-selector>')).fontFamily,
  loadedFaces: [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family + ' ' + f.weight),
  // For EVERY <link rel=preload>: does deleting the asset change any pixel?
})
```

- Webfont declared but `document.fonts` empty / computed family is the system stack → the font
  machinery is 100% dead weight. Delete it (faces, preloads, files). System-ui stacks are a
  *feature* for PSI: no font transfer, and **no font-swap LCP re-record** (a late web font re-stamps
  text LCP at swap time — the W3C LCP spec counts the repaint).
- Audit every `preload`/`modulepreload`/`prefetch` the same way: a hint for a resource not needed
  before LCP steals LCP bandwidth. SSR frameworks may emit a `modulepreload` per rendered chunk
  even for lazily-hydrated components — strip non-entry ones at the HTML-render hook; even
  `rel=prefetch` demotions steal bandwidth on the simulated 1.6Mbps pipe. (Chunk BYTES still
  download via the module graph — only hydration WORK defers; that is fine and optimal.)

## Step 5 — Fixes that recur, by the metric they move

- **Theme/state flip at hydration** (~800ms TBT): a pre-paint inline script and the hydration-time
  store must agree on what EMPTY storage means — PSI always runs empty-storage + light-preference.
  A mismatch mutates `<html>` and re-styles the whole DOM every run. Fix the DEFAULTS to agree.
- **LCP element hygiene**: read `lcp-breakdown-insight` to identify it first (it is often TEXT, not
  the hero image). It must carry **no entrance animation, no JS opacity gate, no animated
  text-shadow** — any repaint re-records LCP. Animate the rest with CSS `both` fill, never JS gates.
- **Single-render responsive DOM**: never render mobile+desktop variants twice (`hidden md:block`
  duplicates). One list: CSS scroll-snap carousel below the breakpoint, grid above. Field result:
  HTML 367→271KB, DOM 2452→1625, FCP −0.2s.
- **Third-party origins**: every extra origin = DNS+TLS on Slow 4G. Self-host, `immutable` cache
  headers, CSP `'self'` — also the only way to pass "efficient cache lifetimes".
- **LCP image**: preload with `imagesrcset`/`imagesizes` mirroring the `<img>` exactly,
  `fetchpriority=high`, explicit `width`/`height`, right-sized variants.
- **Inline critical CSS** (verify what the framework already does): all CSS in the prerendered HTML
  = zero render-blocking requests. Nuxt 3 inlines by default — PIN IT (`features.inlineStyles:
  true`; Nuxt 4's granular default un-inlines global CSS). Critters/beasties on an already-inlined
  page is a regression.
- **Mobile-DPR raster trap (Best Practices)**: any visible raster image needs natural size ≥
  displayed CSS px × ~2.6 DPR or `image-size-responsive` fails BP *on mobile only* (a 32px header
  logo needs ~84px natural — never reuse a favicon as a logo; desktop DPR 1 masks the bug).
- **Decorative layers**: `pointer-events-none` on every absolute glow/overlay — not a score item,
  but hit-testable decorations swallow taps and carousel swipes.
- **Head diet**: JSON-LD to end-of-body, minimal head — bytes before content delay first paint.
- **`color-contrast` / `target-size` / `link-name`**: compute contrast (white@50% on near-black is
  the 4.5:1 floor), 24×24 tap targets, `sr-only` text on icon-only links — check BOTH responsive
  variants of each component.

Project-specific recurring causes: [GROUND: the fixes that actually recur on this stack — the
image pipeline, the font strategy, the hydration-heavy components, and the CSP location.]

## Step 6 — Prototype discipline (never ship a "should help")

Every candidate lever gets: an **isolated git worktree**, the change, a functional proof, and an
**interleaved** Lighthouse A/B (alternate base/proto in ONE loop, 3–4 pairs — sequential rounds get
confounded by machine drift; it once manufactured a fake 7-point regression). Local runs:
`npx lighthouse <url> --form-factor=mobile --screenEmulation.mobile --screenEmulation.width=412
--screenEmulation.height=823 --screenEmulation.deviceScaleFactor=1.75 --throttling-method=simulate`.
Absolute localhost numbers differ from PSI; the base-vs-proto DELTA is the signal.

**Lantern's limits:** localhost CAN measure resource-graph changes (add/remove a preload/request —
trustworthy). It CANNOT measure load-event-relative tricks (locally `load` fires *before* first
paint, inverting the premise) — those need a preview deploy + PSI.

**Levers measured NEGATIVE on an already-tuned page — do not re-try without new evidence:**

1. **Defer entry JS until `load`** — dead interactions until hydration (e2e caught a dead button);
   unmeasurable locally; rejected on the UX regression alone.
2. **`content-visibility: auto` on below-fold sections** — ~0 gain (first paint is network-bound,
   not layout-bound), +TBT bookkeeping, and fragile per-viewport `contain-intrinsic-size` constants
   that broke anchor navigation twice.
3. **Deeper component code-splitting** — +requests/+split overhead contends with hero assets (FCP
   +192ms/LCP +278ms in every pair). Framework entry JS is a floor; the "unused JavaScript" PSI
   flags usually lives there and is unreachable without changing frameworks.

## Step 7 — Variance: measure like Google says to

- Google's own docs: a 100 "is extremely challenging **and not expected**"; treat performance as a
  **distribution**. Only ~zero-JS sites (Qwik/Astro/11ty) hold 100, and even they report 98–100
  bands. A hydrating-framework site *visits* 100 on clean rolls — that is the win condition.
- PSI's shared VMs randomly spike TBT (~500ms on runs whose network numbers are pristine → score
  dips to high-80s). Officially acknowledged in PSI's release notes. Not your code. Judge by the
  **median of 3–5 fresh samples** (check `fetchTime` advanced), never a single run.
- PSI tests from 4 Google datacenters picked by the *requester's* IP — a global CDN mostly
  neutralizes it, but check TTFB on bad runs.
- Report honestly: before→after medians per category per form factor, named remaining audits,
  outliers labeled as outliers. Never round up.

## Step 8 — The automated 100-hunt (when the goal is a screenshot of 100)

Once clean rolls compute to ≥99.5, catching the printed 100 is a sampling problem. Automate it:

1. **One-shot sampler script** at the repo root (needs the repo's `node_modules` for
   `@playwright/test`): headed chromium → the Step-1 deep link → `waitForFunction` for the MOBILE
   LHR global (desktop optional — its lane fails sporadically) → extract categories + 5 metrics +
   fetchTime → **screenshot BOTH form-factor tabs** (the proof standard: never claim 100 without
   the report-page screenshot) → print one `RESULT {json}` line.
2. **Loop it** (Workflow tool or a burst agent): sequential samples ~4 min apart, fetchTime dedupe,
   **early-stop when one sample shows the full win condition** (Performance 100 AND a11y/BP/SEO
   100), 3-consecutive-failure circuit breaker, screenshots kept per sample. Deliver the winning
   pair immediately.
3. Between hunts, fix structure (Steps 4–6). A hunt against a deterministic 99 ceiling wastes
   hours — 24 samples proved it once; the structural fix then swept 100 on the **first** sample.

## Report format

```
| Category       | Mobile    | Desktop   |
| -------------- | --------- | --------- |
| Performance    | 91 → 100  | 98 → 100  |
| Accessibility  | 89 → 100  | 96 → 100  |
| Best Practices | 100 → 100 | 92 → 100  |
| SEO            | 100 → 100 | 100 → 100 |
```

Then: what changed, which metric each change moved (+ms), screenshot paths for any claimed 100, and
**what is still short and why**.

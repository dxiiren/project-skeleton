---
name: audit-pagespeed
description: Use when the developer says 'audit pagespeed', 'run pagespeed', 'check pagespeed insights', 'test on pagespeed.web.dev', 'are we 100', or 'why are we not 100' — drives pagespeed.web.dev with the Playwright MCP, lifts the full Lighthouse JSON for BOTH form factors straight off the page, and turns every failing audit into a source-mapped fix list tied to the metric it actually moves.
model: opus
---

# audit-pagespeed — real PageSpeed Insights scores, with the failing elements

Google's own scoring, on the deployed URL, for **mobile and desktop in one run** — then every
failing audit resolved down to the file that causes it.

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
runs on a **shared anonymous quota that is usually already exhausted**, and returns:

```json
{ "error": { "code": 429, "message": "Quota exceeded for quota metric 'Queries' ..." } }
```

Burning a turn discovering this is the most common way to waste time here. **Drive the web UI
instead** — no quota, and (Step 2) it hands you the same Lighthouse JSON the API would.

Use the REST API only if the developer has set a real `PAGESPEED_API_KEY`.

## Step 1 — Run the analysis

Deep-link straight to the result so no form interaction is needed:

```
https://pagespeed.web.dev/analysis?url=<URL-ENCODED-TARGET>&form_factor=mobile
```

```js
mcp__playwright__browser_navigate({ url: 'https://pagespeed.web.dev/analysis?url=<ENCODED>&form_factor=mobile' })
mcp__playwright__browser_wait_for({ text: 'Performance' })
```

Analysis takes **30–60 s**. `wait_for({text:'Performance'})` returns as soon as the page *shell*
renders — too early; the body still reads `loading`. Wait ~30 s more, then confirm real scores are
present before parsing.

> **One run covers both form factors.** PSI analyses mobile *and* desktop and retains both — no
> second navigation needed for desktop.

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

Pass `filename:` so the payload lands in a file instead of flooding the transcript, then parse it
with a short `node -e` script.

Items for `color-contrast` / `link-name` / `target-size` carry a `node` with `selector`, `snippet`,
`nodeLabel`, and an `explanation` naming the measured ratio or pixel size. Grep the repo for the
`nodeLabel` text to land on the source.

## Step 3 — Know what actually moves the score

**The Performance score is a weighted function of five metrics and nothing else:**

| Metric | Weight |
|---|---|
| Total Blocking Time | 30% |
| Largest Contentful Paint | 25% |
| Cumulative Layout Shift | 25% |
| First Contentful Paint | 10% |
| Speed Index | 10% |

Everything under **INSIGHTS** and **DIAGNOSTICS** — "Reduce unused JavaScript", "Use efficient cache
lifetimes", "Improve image delivery", "Minimize main-thread work" — is **advisory**. Lighthouse says
so itself: *"These numbers don't directly affect the Performance score."* They matter only insofar
as they move one of the five.

So **never report "fixed 6 diagnostics" as progress.** Tie every proposed fix to the metric it
moves, then re-measure. Compute the split to find where the points actually are:

```
score ≈ 0.30·TBT + 0.25·LCP + 0.25·CLS + 0.10·FCP + 0.10·SI   (each term 0–1, ×100)
```

The other three categories are plain pass/fail sums — clear every failing audit and they reach 100.

## Step 4 — Fixes that recur, by the metric they move

- **Third-party asset CDNs** (icon CDNs, Google Fonts, analytics) — every extra origin is a DNS +
  TLS round trip on Lighthouse's Slow-4G mobile profile. Self-host into the static dir and serve
  `immutable, max-age=31536000`. Moves **SI, LCP, FCP** — and it is the *only* way to pass "Use
  efficient cache lifetimes", since you cannot set a third party's headers.
- **LCP element** — size the image to what it renders at, add `fetchpriority="high"` plus explicit
  `width`/`height`, and `rel=preload` it so the fetch starts before the parser reaches the tag.
- **Client-side carousel / slider / chart libraries** — each instance does a layout pass at
  hydration, which shows up as a **forced reflow** and is usually the biggest **TBT** lever. Mount
  below-the-fold ones lazily.
- **`color-contrast`** — decorative low-opacity text. On a near-black background, white at 50%
  opacity is roughly the 4.5:1 floor; below that it fails. Compute, don't eyeball.
- **`target-size`** — tap targets under 24×24 CSS px, or spaced closer than 24 px. Common in
  carousel pagination dots and icon-only buttons. Keep the dot small, grow the hit area.
- **`link-name`** — an icon-only `<a>` with no visually-hidden text. Mobile and desktop variants of
  a card get edited separately, so one often has it and the other doesn't.
- **CSP vs. redirects** — `img-src`/`connect-src` must allow the host a URL *redirects to*, not just
  the one you wrote. A blocked redirect logs console errors and costs **Best Practices** points.

Project-specific recurring causes: [GROUND: the fixes that actually recur on this stack — the
image pipeline, the font strategy, the hydration-heavy components, and the CSP location.]

## Step 5 — Re-measure, honestly

Re-run Steps 1–2 against the **deployed** URL after the deploy lands, and report before → after per
category for both form factors.

- PSI is **noisy**: ±3–5 points run to run on mobile. A 2-point move is not a result — re-run before
  claiming either a win or a regression.
- Verify against the live URL, never a local build. The point of this skill is Google's number on
  the real deployment.
- If a category is short of 100, **say so and name the remaining audits**. Do not round up, and do
  not present diagnostic fixes as if they were score movement.

## Report format

```
| Category       | Mobile    | Desktop   |
| -------------- | --------- | --------- |
| Performance    | 91 → 97   | 98 → 100  |
| Accessibility  | 89 → 100  | 96 → 100  |
| Best Practices | 100 → 100 | 92 → 100  |
| SEO            | 100 → 100 | 100 → 100 |
```

Then: what changed, which metric each change moved, and **what is still short and why**.

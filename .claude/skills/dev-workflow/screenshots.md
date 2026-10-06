# `needs/screenshots` from an agent session

Contents: the flow · traps by step. An agent has no browser session and no live customer data; this is the proven substitute
(FE PR#165 onward, ~15 PRs). The review-image ref is deleted in post-merge cleanup (SKILL.md step 11).

## The flow
1. **Render** — a TEMP page in the worktree (`app/<issue>-preview/page.tsx`) rendering the real component; fixtures pick the
   scenario. Delete it before committing, then `git checkout -- CLAUDE.md` AND `rm -rf .next`.
2. **Serve** — `pnpm dev` in the worktree on :3000 (AFTER); the BEFORE tree on another port. Copy the MAIN checkout's
   `.env.local` into a fresh worktree first.
3. **Sign in** — a Clerk dev sign-in token consumed by the real `/sign-in` page.
4. **Fixtures** — Playwright `context.route` serves every backend call; nothing reaches a backend or prod telemetry.
5. **Shoot** — Playwright (global install) element screenshots; read the rendered text back from the DOM for the proof table.
6. **Host** — an orphan ref `refs/heads/screenshots/<issue>` via the Git data API; raw URLs in the PR body.
7. **PR body** — say the frames come from a local preview with fixture payloads and the live click-through remains for Lin.

## Traps by step
**Render** — Next 16 `next dev` rewrites the tracked `CLAUDE.md` and bakes the temp route into `.next/dev/types/validator.ts`
(`pnpm type-check` fails on the phantom module until `.next` is removed) (FE#551, FE PR#253). A portal-mounted surface renders
on a plain preview route when the component reads its data from the API (FE PR#558).

**Serve** — `PORT=3100 pnpm dev` (`pnpm dev -- -p 3100` dies with "Invalid project directory") (FE PR#165). Another port fails
Clerk's `azp` check unless appended to `NEXT_PUBLIC_CLERK_AUTHORIZED_PARTIES` in the tree's `.env.local` (FE PR#438). Next dev
falls back to :3001 silently when :3000 is busy — read the dev log's `Local:` line before every run (FE PR#448).

**Sign in** — `POST https://api.clerk.com/v1/sign_in_tokens {"user_id": <rig user>, "expires_in_seconds": 900}` with the dev
`CLERK_SECRET_KEY` from `.env.local`, then `goto(/sign-in?__clerk_ticket=<token>)`. Tokens are single-use: one per run
(FE PR#508). Rig identity on the Clerk DEV instance: `user_3IkrunMFithM6qQh4mvgHK6b1mX` (`fe425-preview-test@agentmail.to`),
`org:admin` of "Acme Networks" `org_3IkrwYU1wxeQnrbFVaXWUaE7qem`; org-scoped surfaces need `window.Clerk.setActive({organization})`
(FE PR#558). Sessions stale across dev-server restarts and a saved `storageState` stales in ~10 min — sign in and shoot inside
ONE browser session per run (FE PR#426, PR#439). Turnstile blocks automated sign-UP and a hand-minted `__clerk_db_jwt` fails
the middleware — the token flow is the only headless path (FE PR#426).

**Fixtures** — intercept by PATH, never by host (`NEXT_PUBLIC_API_URL` comes from several env files; a host match let the real
call through to `ECONNREFUSED`, FE PR#558): `pathname === "/api/v1/users/me/limits"` → fixture, `startsWith("/api/v1/")` →
404. Unhandled calls answer 404, never 401 (a 401 trips `SessionExpiryGuard`, FE PR#508); `/api/backend-status` →
`{"isOutage": false}`. The limits fixture carries `onboarding_completed_at` or the onboarding modal paints over every frame; a
non-team fixture OMITS `org` (`org: null` crashes the page) — copy the component test's `createMockLimits`/`createMockOrg`
(FE PR#557, PR#558). Abort telemetry by HOSTNAME (`posthog|sentry`) + the local `/ingest/` path — a whole-URL regex also aborts
the app's own `posthog-js` chunks (FE PR#429).

**Shoot** — `ln -s "$(npm root -g)" node_modules` in the rig dir for ESM imports; the global Playwright has no browsers
downloaded — `chromium.launch({ channel: "chrome" })` drives the installed Chrome, no download (mkt PR#205). Below-the-fold panes are element screenshots
(FE PR#517); hide the dev overlay with `<style>nextjs-portal{display:none!important}</style>`. Headless Chrome CLI
(`--virtual-time-budget`, `--timeout`) blanks rAF-gated UI and freezes timers — use Playwright (mkt PR#148, FE PR#431).
`--dump-dom` reads `content-visibility:auto` rows in their SKIPPED state (heights = `contain-intrinsic-size`) — measure with
`getBoundingClientRect` after `waitForFunction` + one frame (FE PR#557). A stretched overlay button intercepts pointer events —
click the container or `{force: true}` (FE PR#524). StrictMode double-mount: `test.md`.

**Host** — build `{"encoding":"base64","content":…}` with python and pass `--input <file>`; `gh api -f content=@file` sends the
literal string and every blob uploads identical (mkt PR#148). Reject the empty blob SHA
`e69de29…` for every upload. Require different SHAs only when the intended source data differ;
byte-identical states and before/after frames are legitimate when the source data match (FE PR#517). Raw URLs 404 for anonymous `curl` on a private
repo — verify with `gh api "repos/<o>/<r>/contents/<f>?ref=<sha>"`.

**Production app frames (marketing)** — when the frame must show the real app with real data and no fixture rig exists, Lin signs
into a Playwright persistent Chrome profile once (`launchPersistentContext("profile", { channel: "chrome" })`, headed for the sign-in,
headless after) and every frame is masked in the DOM first: sidebar name + plan badge, Recents, and any card, menu item or lab row
naming a customer, removed before the shot (Lin's rule, no name or username in public content; mkt PR#243). Review each frame
afterwards anyway. Rig facts for app.netpilot.io live in memory (`project-app-screenshot-rig`).

**BEFORE tree** — read `origin`’s remote default branch first, then `git worktree add --detach …/<issue>-before origin/<default>`, served on the alternate port with the
authorized-parties line — never `git stash` under a live dev server (FE PR#522, PR#528). Run the rig once per tree with two
explicit commands; a `for run in …; do set -- $run` loop hits zsh's no-word-splitting (FE PR#558).

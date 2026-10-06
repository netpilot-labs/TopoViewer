# Deploy — the post-merge watch (part of the merge, never optional)

Contents: watcher rules · Railway (Backend/LB) · Vercel (Frontend/Marketing) · CORS · freshly booted VM

`postmerge.sh <repo> <merge-sha>` executes the Railway/Vercel watch below (exit 0 clean · 1 RED · 2 broken · 3 REVIEW).
**RED is judged by its IMPACT, never reverted by reflex** (Lin, 2026-10-01 — replaces "red = revert"; a `dependency-updates`
pass follows the same rule). The script's `RESULT` line names which signal fired:
- **Roll back first** — production is unavailable (health or the route load failing, the service not serving, a core flow —
  sign-in, chat, VM start, billing — failing for everyone) or MANY users are hit (count them: users/events on the new Sentry
  groups, the 5xx share in `railway logs`). `git revert`, self-merge, re-watch — the platform's one-click rollback buys the
  minutes — then report to Lin with logs. Impact you cannot measure on a core flow counts as many.
  A probe sample with no HTTP answer (DNS, connect, timeout on this machine) is `BROKEN`, not an outage — probe from another
  network first; a RED next to a `BROKEN` or `REVIEW` line is impact UNKNOWN until that line is read (Sentry users/events).
- **Fix forward** — everything else: a failed `main`-run test that shows no core flow broken (the real-Clerk job runs only
  there: read it — sign-in itself failing is the roll-back case), a failed deploy that left the previous build serving, a
  production fault few users can reach. Keep working it and merge nothing else in that repo until `RESULT: clean`. A failed
  test is read first (`gh run view <id> -R <o>/<r> --log-failed`); in a suite the merged diff cannot reach, with the PR's run
  green on the same tree, re-run it (`gh run rerun <id> -R <o>/<r> --failed`) and re-run `postmerge.sh` (BE PR#942: a 1.0 s
  wall-clock bound read 1.026 s on a Markdown-only merge).
**Repos without a deploy on merge** (containerlab-mcp, netpilot-skills, netpilot-probe-lab): `postmerge.sh` prints ONE
`RESULT: no deploy on merge` line with the `main` push runs for the sha (read once — follow any not yet green) and exits 0;
it records no hold, and frees one already kept for that sha only when those runs are all green (or the repo has no
workflows). Then the repo's own step: containerlab-mcp — none
(its release is tag-gated; merge.md); netpilot-skills — `sync-all.sh` + a commit in each consumer it changed
(skill-maintenance ship duty), and confirm both consumers read current.

## Rules for any watcher you write by hand
- **Self-test the status source first and fail LOUDLY** (`exit 2 WATCHER-BROKEN`); N consecutive empty/error reads mid-loop =
  the same exit, never "keep waiting". Never `2>/dev/null` the source; never pipe a background watcher through `tail`/`head`.
- Extract with the API's server-side `--jq`; separate "the value differs" from "I got no value". Elapsed from `date +%s`, never
  a loop counter; thresholds from observed latency.
- **Wait for a run/deploy an action is ABOUT to create by baseline-diffing ids before the action, never by a predicted
  timestamp** (BE PR#586: 50 min of dead air on a passed run). Compare only timestamps the API reported; never a `Z` stamp
  against fractional `createdAt`.
- Deployments API: FULL 40-char oid (`?sha=<short>` returns `[]`); `jq '.[0].id // empty'`.
- Escalate, don't observe: a rule with a deadline is the watcher's job.

## Railway (Backend / LB)
- `railway logs --tail 50` until the new deploy serves, then `/health` with `curl` (a `urllib` UA gets a Cloudflare 403 on every
  sample, BE PR#745): ~5 samples a few seconds apart — a single 503 at cutover is the drain-aware replica; revert only on
  SUSTAINED failure (BE#261). Sample again ~5 min later.
- Settle by the deployment list keyed on `meta.commitHash`, never elapsed time: a Python-only change reaches SUCCESS in ~1 min,
  docs-only in ~30 s (BE PR#842).
- **CLI logged out** (`railway login` is interactive; the backboard token dies with it)? Watch through GitHub:
  `gh api "repos/o/r/deployments?sha=<merge oid>"` → newest id → `…/deployments/<id>/statuses --jq '.[0].state'` walks
  `in_progress → success`. Read only the `success`; the later `inactive`/re-`success` churn is normal, not a rollback (BE PR#879).
- **`NEEDS_APPROVAL`** (author not a workspace member) never builds — approve via
  `mutation { deploymentApprove(id:"<dep-id>") }` on `https://backboard.railway.com/graphql/v2`, token from
  `~/.railway/config.json` (BE PR#270).
- **`QUEUED` >10 min = platform:** `query { deployment(id:"<id>") { status meta } }` → `meta.queuedReason`; truth is
  `status.railway.com` (the instatus mirror lies). Confirm `/health` 200 on the prior deploy and wait on a 15-min poll;
  cancel/retry loops only spam alerts (BE PR#539).
- **`502 Application failed to respond` on SUCCESS with uvicorn up and NO request logged** = bound to `::` (IPv6-only);
  bind `0.0.0.0` (2026-04-25, peeringdb-mcp).
- `railway` answers for the directory's linked service — pass `-s <service>`; its `--json` is not valid JSON
  (`python3 json.loads(strict=False)`; a status must match `^[A-Z_]+$`).
- Prove WHAT deployed: `railway ssh -- sh -lc "cd /app; .venv/bin/python -c \"import importlib.metadata as m;
  print(m.version('<pkg>'))\""` (BE PR#688).
- **New service:** `railway add --repo` says `repo not found` when the Railway GitHub app lacks the grant — create an Empty
  Service, `railway up --detach`, connect the repo in the dashboard; a GraphQL-created service needs
  `serviceConnect(id, input: {repo, branch: "main"})` before pushes deploy, and `repoTriggers` on the service answers "is it wired"
  (peeringdb-mcp, BE#858). A custom start command runs WITHOUT a shell — literal port or `sh -c` (BE#858).

## Vercel (Frontend / Marketing)
- **A 200 route load is NOT verification** (a failed build leaves the previous deployment serving). First
  `gh api "repos/<owner>/<repo>/deployments?sha=<full merge oid>"` → newest id → `…/statuses --jq '.[0].state'` = `success`;
  then load `https://app.netpilot.io/sign-in` (the root 404s signed-out by design) or `/version.json` for the build sha (FE PR#192).
- **No deployment record after ~3 min = event miss:** push an empty commit to main authored
  `lz-networks <50209324+lz-networks@users.noreply.github.com>` and watch the new sha (FE PR#309). GitHub outage (webhooks
  down): in the repo's MAIN checkout on `main`: `cp .env.local /tmp/envlocal.bak`, `npx -y vercel link --yes --scope netpilot
  --project <name>`, `npx -y vercel deploy --prod --yes` (builds remotely from that directory), then `cp /tmp/envlocal.bak
  .env.local && git checkout .gitignore && rm -rf .vercel` — the CLI edits the tracked `.gitignore` and rewrites `.env.local`
  (FE PR#376; setup.md).
- **"An unexpected error occurred when running this build" AFTER `Build Completed`** = platform: `npx vercel redeploy <dpl_id>`
  (no `--yes`); a CLI redeploy creates no GitHub deployment record — confirm with `npx vercel ls --prod` (FE PR#550).
- **Frontend capture proof** (netpilot-skills PR#78): after the verified live version, `postmerge.sh` prints a unique
  deployment-probe URL. Open it in a fresh browser tab with normal analytics enabled; verify the current version and
  loaded client assets, and retain that receipt with the URL. The helper reads its real `$pageview`
  [Current URL](https://posthog.com/docs/product-analytics/paths). Never fake capture through the API. No matching event
  = REVIEW; attribute browser blocking, delayed ingestion, or broken capture before acknowledging the hold.
- **Frontend `postmerge.sh` exit 2 whose ONLY `BROKEN` line is the posthog one, preceded by `posthog: not configured
  (POSTHOG_PERSONAL_API_KEY missing …)`** = a machine without the key (the WSL workstation): not a revert signal — confirm the
  deployment `success` and `/version.json` = the merge sha by hand and record both (FE PR#586, 2026-09-30); the next
  Frontend merge there then takes `MERGE_SLOT_ACK=<that pr>` (merge.md). Any other posthog
  line (`query failed`, `POSTHOG_PROJECT_ID missing`) leaves capture unread on a machine that should read it: still BROKEN.

## CORS (any PR changing what the browser SENDS cross-origin)
Curl the prod-edge OPTIONS with `Access-Control-Request-Headers` naming every header the client now sends BEFORE merging (the
LB answers preflights; no deploy needed) and check `Access-Control-Allow-Headers` CONTAINS THEM ALL — a 204 is not a pass, the
browser enforces the subset. Never pin a header list on the LB (FE#121: ~1 h chat outage).

## Freshly booted VM
SSH up ≠ service up: gate on `ss -tlnp` showing :8082 and :8083 bound before any health probe (fastmcp crash-loops until
containerlab creates `/run/netns`; tusd waits for `/etc/tusd.env`) — early probes produce false failures (fleet sweep 2026-07-28).

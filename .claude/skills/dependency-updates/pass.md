# Dependency pass procedure

Contents: [Checklist](#the-checklist) · [Always-on rules](#always-on-rules).

## The checklist

Copy it into the pass and tick as you go:

```
Dependency pass:
- [ ] 0. Read the ledger — `netpilot-devops/ledgers/dependency-updates.md` (snapshot, trust,
        blocked triggers, proposals). Sync + clean tree
        in the canonical skills repo.
- [ ] 1. Inventory every repo: `scripts/inventory.sh` (mechanics §1). Every FINDING
        line is an item to tier or a ledger row to write.
- [ ] 2. Re-check every blocked/dismissed ledger row's TRIGGER first
        (`scripts/trigger.sh`, mechanics §7): a fired trigger becomes a work item this
        pass. Then tick the SAFE Pending-Approval entries (tiers §5) — every pass, so
        their PRs are green by the window. A RED PR open midweek is diagnosed midweek
        (mechanics §4), so the window is merges, not diagnosis.
- [ ] 3. Tier every item (tiers.md). A grouped PR takes its highest member's tier.
        Anything touching a never-auto surface (dev-workflow Guardrails) is T4 no matter
        what Renovate's group says — then apply tiers §2's risk split (bug-fix = T2/T3
        + surface check; major = full §3; dev-only major = §3 step 1 + CI + Codex, any
        matching surface's own check kept) and the T5 decision test.
- [ ] 4. Order: T0 security first, then T1 (red: diagnose; green and still
        open: merge it first in its repo), then the repo's runtime candidates by BLAST
        RADIUS — T4 framework/auth groups first, then T2/T3 libraries by age — T5 desk
        lines last. One dep merge in flight per repo; the next waits for the previous
        deploy watch to close. Per pass, per repo: tooling-only PRs first, then at most
        ONE runtime-affecting PR, last (Always-on rules).
- [ ] 5. Per item: audit (mechanics §3–4) → adopt/label (§2) → Codex + CI via
        pr-gates.sh → endpoint per tier → `scripts/merge.sh <repo> <owner> <pr>` (base
        check → gate → squash-merge → `dev-workflow/scripts/postmerge.sh` watch; exit 1 = RED: impact
        decides — `dev-workflow/deploy.md`; a roll back is `scripts/revert-pr.sh`, §9). `--wait-codex` for a Renovate PR the pass just asked
        Codex to review.
- [ ] 6. Alerts with no PR path: the disposition ladder (below) — fix, surgical bump,
        blocked-with-trigger, or dismiss-with-reason. Never leave an alert without a
        ledger row that says what happens next and when.
- [ ] 7. Desk: every T5 decision (tiers §2 test) and every policy proposal for Lin, one
        line each with the recommendation — attended: the turn summary; unattended: the
        DevOps loop's `REVIEW.md` via `review-desk` (the only place he reads). A major
        break = an incident line there with the roll back already done. Nothing waits
        silently. A PR held on a T5 line is refreshed onto current `main` after the last
        self-merge (mechanics §2) so the merge that follows his answer is a tested one.
        Open post-deploy watches (svix first delivery, clab actions at next tag) go to
        `WATCHES.md` so every 2-hourly pass re-checks them. At the closeout pass (Where it
        runs) a mergeable PR still open is a desk line naming why — never a silent carry.
- [ ] 8. LEARNING PASS (learning.md) — before the report, not after.
- [ ] 9. Report (exemplar in learning.md). Canonical repo committed, pushed, synced;
        `git status` clean.
```

## Always-on rules

- **The fleet is CLOSED — five repos: `NetPilot-2-Backend`, `NetPilot-2-Frontend`,
  `netpilot-marketing`, `containerlab-mcp`, `NetPilot-2-LB`.** Every org-wide sweep
  (`gh search prs/issues --owner lz-networks`, Dependabot alert counts, any Sentry/CI/PR
  listing) MUST filter to this list — a bare `--owner lz-networks` surfaces legacy repos
  that are not deployed and not tracked. `lz-networks` still hosts dead repos whose only
  churn is org-wide bot onboarding (Renovate/Vercel); those are permanently out of scope
  (ledger §7). A legacy-repo PR/alert is not the pass's work — do not adopt, triage, or
  re-surface it. (Lin, 2026-09-14: 10 legacy onboarding PRs closed; fleet-only sweeps from
  now on.)
- **A dep merge is a production deploy.** No staging exists. Serial merges per repo,
  deploy watch to completion, post-merge signals read (mechanics §8), then the next —
  and "previous" includes ANOTHER session's merge: read the repo's latest deployment
  (`SUCCESS` + healthy) before merging, whoever triggered it (first pass, 2026-09-08:
  BE PR#737 from an attended session was still `DEPLOYING` when the pass opened its PR).
- **Hand-made bumps respect the same 7-day release age Renovate enforces** — Renovate's
  cooldown does not see a lockfile the agent re-resolved by hand; read the age from
  `uv.lock`'s `upload-time` / `npm view <pkg>@<ver> time`. Security-driven bumps are
  the only exemption (mirrors `vulnerabilityAlerts.minimumReleaseAge: null`).
- **A security bump goes to the LATEST stable patched version, not the minimum `first_patched`**,
  when that version stays inside the same major (on 0.x: the same minor line), is admitted by
  every OTHER package's declared range on it (the bump edits its own pin; a framework's range is
  never overridden — ladder #3), and the intervening changelogs, migration guide and deprecation notices (mechanics §3
  step 1) carry no Breaking / Changed / Removed / Deprecated entry on a path we use; otherwise
  the newest version that passes, down to the minimum, and the rest rides the normal cooldown. Renovate's `[SECURITY]` PR already arrives at the highest version (fleet
  `vulnerabilityFixStrategy: highest`, P16, 2026-10-06): when that version FAILS the test,
  rebuild the PR at the newest version that passes on current `main` and comment the
  supersession on Renovate's; when that would push a critical fix past the pass, merge the
  minimum first and the follow-up bump rides the normal tier
  (P14, Lin 2026-10-05: pyjwt went to the minimum 2.14.0 and was re-bumped to 2.15.1 hours
  later for a second CVE, pass-882/883).
- **Audit the lockfile, not the PR table.** A Renovate branch re-resolves transitives
  inside ranges; a red PR whose listed packages look innocent can be failing on an
  unlisted one (FE#337/#338, 2026-09-08: 15 shared transitive moves, identical failure).
  Mechanics §4 has the diff.
- **Never weaken, skip, or delete a test to green a dep PR** (`dev-workflow` Guardrails).
  A red T1 PR is a diagnosis task, not a merge task.
- **The `claude-agent-sdk` pin never rides along** (billing-class; BE CLAUDE.md rule 7).
  A grouped PR that touches it is split before anything else happens.
- **Renovate Dependency Dashboard issues stay open** (one per repo; Renovate reopens them
  anyway — `dependabot-fleet-zero`, 2026-07-16).
- **A pass that finds nothing to do still re-checks triggers and stamps the ledger
  snapshot.** Silence is not a state.
- **Dependency merges land inside the weekend window when unattended** — Friday 21:00
  through Sunday 22:00 America/New_York, the product's low-traffic span (Lin, 2026-09-29;
  supersedes P11's Monday 03:00–06:00 window): Renovate's T1 automerge owns the first six
  hours (Friday 21:00–Saturday 03:00, `automergeSchedule`), the loop's own merges start at
  the Saturday 03:00 pass. T0 security is the only exception. Attended passes are Lin's
  call, default off-peak.
- **One runtime-affecting merge per repo per pass, last in that repo** (Lin, 2026-09-29).
  Tooling-only PRs — dev/test/lint/type deps, package-manager pins, CI actions: nothing that
  ships in the runtime bundle or image — merge first, serially. Then at most ONE PR that
  changes shipped code, as the pass's last deploy in that repo, so its ride-out carries no
  other deploy; a slow-burn signal then names one PR and the revert pulls one PR. The next
  runtime merge in that repo starts only when **≥60 min have elapsed since that deploy went
  live** (the deployment's own timestamp — never "the next pass", which can arrive minutes
  after a late merge) AND a gate read covering the WHOLE ride-out is clean:
  `postmerge.sh <repo> <sha> --sentry-window <N>h` with N ≥ the hours elapsed since the
  deploy went live, rounded up — the script's default is a rolling hour, which misses the
  first part of a 2 h gap; a failed Sentry query or an unavailable PostHog signal is BROKEN
  (exit 2), and a `REVIEW:` line makes it exit 3 — not clean until every such line is
  attributed (Codex, netpilot-skills PR#45). A pass that arrives earlier works
  another repo or waits. Inside that ride-out nothing the loop controls deploys in the repo:
  Renovate's T1 automerge is confined to before the loop's first pass (`automergeSchedule`
  Friday 21:00–Saturday 03:00), and a green T1 open during the window is the pass's own
  merge, tooling-first. **An intervening deploy the loop does not control (an attended
  merge) ends single-PR attribution:** the gate read first confirms the repo's newest
  deployment is still the dep merge's sha (Railway deployment list / Vercel `version.json`
  — `postmerge.sh` prints the mismatch as a NOTE, it does not fail on it); a newer sha
  restarts the ≥60 min clock from THAT deploy, and a signal inside the span is attributed
  by reading both diffs before any revert. netpilot-marketing has no Sentry project and no `version.json`, and `postmerge.sh` looks up the deployment BY the merge sha (SHA-blind to anything newer): its gate read is the newest production deployment with NO sha filter — `gh api "repos/lz-networks/netpilot-marketing/deployments?environment=Production&per_page=1"` (the feed `postmerge.sh` reads, minus `?sha=`; a preview or failed record never replaced the site, so its newest status must be `success`) — its `sha` must still be the dep merge's, else the clock restarts from it — then `postmerge.sh` re-run and `/` loaded again; no other signal exists there. NetPilot-2-LB takes ONE runtime merge per window (its only runtime dependency is the
  haproxy image; mechanics §8's CORS + sticky-cookie probes run at the merge), so the
  next-merge gate never arises there. A repo with no deploy on merge (containerlab-mcp,
  mechanics §8) has no runtime ride-out: `dev-workflow` postmerge still requires default-branch
  push workflow verification and merge-slot settlement before completion. Blast radius orders the runtime candidates within a
  repo (checklist step 4) so the framework or auth bump lands with the most window left.
- Headless runs obey the DevOps loop's watchdog: never start a merge whose deploy watch
  cannot close inside the pass deadline — record it as in-flight in WATCHES and finish next
  pass.


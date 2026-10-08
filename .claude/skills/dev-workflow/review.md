# Review — the Codex loop

Contents: the loop · reading the verdict · disposition (exposure test, the four outcomes) · round cap · closing

## The loop
0. **The PR body carries a `## Scope and accepted limits` section BEFORE the first request** (Lin, 2026-10-04): what the PR
   deliberately does not do, and the residual classes it accepts — the evasion class of anything that scans, validates or
   reads text a user or shell wrote never converges (mkt PR#181; clab PR#266; BE PR#959: 10 rounds; BE PR#966: declared at
   R2). A finding inside a declared class is answered by pointing at the section.
1. Open the DRAFT PR, comment a bare `@codex review`, and in the SAME breath arm the canonical watcher:
   ```bash
   env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment <n> -R <owner>/<repo> --body "@codex review"
   <skill-dir>/scripts/pr-gates.sh <n> --repo <owner>/<repo> --watch   # run_in_background, stdout to a FILE — never a pipe
   ```
   `pr-gates.sh` owns the three verdict channels, head matching, the 5-min no-👀 re-request, HEAD-MOVED and loud failure.
   Hand-rolled pollers are banned — every shape has failed (review-only, comment-only, REST page 1, timestamp filters).
2. **A round closes ONLY by a new verdict on the CURRENT head.** Replying, resolving and disposition comments are bookkeeping.
   After every push the last two actions are: re-request, then re-arm the watcher (BE#308) — arm only once
   `gh pr view --json headRefOid` reads the pushed SHA: the API lagged ~40 s and armed a stale head three times
   (BE PR#915, 2026-09-29).
3. Triage each finding (below), push fixes, then reply + resolve with `scripts/pr-threads.py <owner/repo> <pr> <oid> replies.json`
   (`<oid>` = the full 40-char head from `--json headRefOid` — head7 is refused, the opposite of merge.md's `local-check` line,
   skills PR#200; replies.json is an OBJECT keyed by comment id, shape in its header — not an array, netpilot-dev PR#4;
   `pr-threads.py <owner/repo> <pr> --dry-run` — two args, no oid, no replies path — lists thread ids) — only after
   `git diff --stat HEAD~1` lists every file the replies claim.
4. `pr-gates.sh <n>` READY = verdict on head + 0 unresolved + CI green (+ latest request answered, non-draft). READY means
   dispositioned, never zero findings — read the substance. **A clean pass never retracts an open finding from an earlier pass on
   the same head**; two passes on one head can disagree — trust the open thread (BE#308).
5. **Cap ~5 rounds** (harness-only PRs ~3; lab PRs once the replay gate covers them, BE#711), then decide below — never drift.
   A script that mutates customer VMs is not harness: no ~3 cap, every real edge is fixed (skills PR#59: 8 rounds, all real) —
   the round-5 disposition table is still posted, and each further round names what is left.

## Reading the verdict (encoded in the script; audit its answer with these)
- Three channels: a formal review on the head (findings, P1–P3 inline threads); a clean ISSUE comment `Codex Review: Didn't
  find any major issues` carrying `Reviewed commit: <10-char sha>`; or inline threads only. `gh pr view --json comments` is
  issue comments ONLY — a PR with findings shows nothing there. Never say "no verdict" without the three-channel read
  (`pr-gates.sh` channels 1–3; BE#308).
- **A review can also arrive as ONE issue comment that carries the findings** (`### 💡 Codex Review`, a P-badge and a blob
  link each, no threads): the script counts them and stays NOT READY until a fix push or a comment line
  `codex-comment-findings: <head7> dispositioned` + the per-finding dispositions. Read the verdict comment itself before
  any closure comment — it was matched as the clean pass and "READY" was repeated over six P2s (skills PR#60 R6).
- A "Codex Review Summary" issue comment (🔄 Running → ✅ Completed, 7-char sha) is Codex's STATUS line, not a verdict —
  the script ignores it by design (PR #21, 2026-09-28).
- 👀 on the request = picked up (verdict ~2–15 min); no 👀 after ~5 min = re-request; 👀 is removed when done. Codex OFTEN
  auto-reviews a push but not always — a pushed head is unreviewed until a verdict on it exists. "Something went wrong" is
  transient — re-request once. **"You have reached your Codex usage limits" is the shared review quota, spent until it resets:**
  no re-request — `pr-gates.sh` exits NOT READY on it (five re-requests got five copies, netpilot-dev PR#4, 2026-10-07) — post ONE hold comment naming it, and
  report the state `pr-gates.sh` prints — PR-ready only with a verdict already on the head, else NOT READY until the quota resets
  and one lands; never merged past it. The wave budgets its rounds (lanes.md).
- **Repeated re-requests with no 👀 = Codex is down: HOLD.** No delegation breadth covers a reviewer outage (Lin, 2026-08-19).
- **`pr-gates.sh` BROKEN on its OWN re-request can be GitHub, not Codex:** comment writes answered HTTP 500 for ~4 min with no
  status incident (skills PR#200, 2026-10-07). Not a reviewer outage — post the `@codex review` by hand once a write lands,
  then re-arm the watcher.
- A round is a ~20-min wait: push and request before a pass ends; never re-request an unchanged, reviewed head (the post-flip
  request in `merge.md` is the one exception).
- A finding that assumes CLI/API/library behavior: validate at the cheapest tier before acting (`probe-testing`).
- A round's fix that changes mechanics stales the PR BODY — re-sync its safety claims before PR-ready (BE PR#481).

## Disposition — every finding ends as exactly one of: fix · accept as residual · defer to an issue · product/policy issue
**FIRST read the code path the finding names.** The severity label is a hypothesis (BE#435: one finding accepted too alarmed,
one dismissed too safe, neither read the code). Then the exposure test, in order:
1. **Who can reach it?** unauthenticated → any user → the owner → an operator by hand → nobody (unshipped). **A race finding is
   answered here:** name the actor and whether they are real or can be shut out for the run (a few lines); if not real, never
   build per-window hardening (Lin, 2026-09-27; BE PR#892: 11 rounds, one shape). The process dying IS real: a resumable step.
2. **Blast radius?** other users' data → own data → own VM → an error message.
3. **Anyone using the surface today?**
4. **Reversible and detectable?**
Baseline on every concurrency finding: does our behavior match the platform's native semantics for the same operation? Match =
not our defect. A sync read-modify-write with no `await` cannot interleave on one loop — refute with the mechanism (BE PR#592).
- **Fix now**, any round: cross-user reach, credential exposure, silent permanent loss, a correctness bug on a real path.
  Profile a PERF finding's mechanism before its suggested fix (FE PR#397: the real bug was a quadratic trim).
- **Accept as residual** (name the revisit trigger): owner-only hardening, attacker-already-has-access, unshipped surfaces.
  Harness/test-code findings are inexhaustible by construction — accept at round ~3 unless blast radius leaves the harness
  (BE PR#401).
- **Defer to an issue:** real, not urgent, or wants a bigger design. `residuals.md` owns what happens next.
- **Product/policy decision** (out of scope, a pre-existing gap re-exposed, a choice between real alternatives): file an
  `agent/stop` issue with mechanism + exposure + 2–4 options, reply with the number, resolve, let the merge proceed under its
  existing grant (Lin, 2026-09-03).
- **Escalating is NOT a disposition.** Route to Lin only when the option you RECOMMEND needs his authority (Lin, 2026-09-17).
  A wrong BLOCK costs as much as a wrong merge.
- Content files with an owner (persona, customer copy): fix only what validation requires, route the rest to the owner as
  residuals from round 1 (BE PR#803). Scanners, validators, class-pin TESTS that scan text, hooks parsing a command line,
  traps loaded into a user's script: the evasion class and the fix-now side of the line go in "Scope and accepted limits".

## Round cap — at round 5 the disposition table, and the decision in the same comment (Lin, 2026-07-28; teeth 2026-10-04)
**No round 6 without it:** ONE PR comment carrying a table — finding · fix / accept / defer · why — for every finding still
open, and the decision (a–d) taken in that same comment. First re-ask the actor question for every race fix so far; fixes
against unreal actors come out. Then:
- **(a) Merge and accept** — the default when what remains fails the exposure test; document each open finding + trigger
  (say so if a release gate sits after the merge, clab#45).
- **(b) Split** — land the converged part; the class goes to its own issue.
- **(c) Continue** — only for fix-now classes; say why, and POST the endpoint criteria on the PR before the next request (an
  unstated line was overridden three times, PR#322).
- **(d) Redesign** — persistent NEW findings past the cap is a design problem, never a review problem (Lin, 2026-08-16). Stop
  signals: a round's own fix produces the next round's P1; the defensive code GROWS every round; findings pull in OPPOSITE
  directions (stop even before 5). Ask "what makes this state unreachable" — say the premise aloud and test whether it is a
  platform constraint or a default someone can flip (BE PR#832→#845: 2,041 lines → 105, one Pulumi option). Redesign note =
  what is structurally wrong, 2–4 alternatives with pros/cons, a recommendation. Honour a stated stopping rule the FIRST time.
- **A SECOND finding on one heuristic is the signal to change the method, at round 2** — swap the heuristic for a quantity
  the code measures exactly, or a precondition check that falls back to the weaker true statement; one more caveat earns
  the next finding (BE PR#958: 7 of 10 findings on one sentence; clab PR#266). After decision (a) the same signal ends
  the loop: a post-flip finding inside the mechanism just fixed that FAILS the exposure test is a residual, not another
  fix — the fix-now categories above still fix, any round (BE PR#1008: five result-cap P2s fixed one per round, each fix
  drawing the next, ~20 min a round).
- **Merge right after the verdict while main is still the base; a rebase-only re-review runs under the cap decision already
  posted.** On a no-CI repo every rebase is a new head needing a fresh verdict, and a verdict on an UNCHANGED diff produces new
  findings each time (skills PR#180, 2026-10-07: 9 verdicts on 9 heads; two rebase-only re-requests brought 6 and 4 findings):
  leak-path or correctness-breaking findings are fixed, the rest dispositioned on the PR under that decision exactly as any
  round's findings are (Disposition above; `pr-gates.sh` reads it) — never a new open-ended round.
**Fork ownership** (Lin, 2026-09-19; default mode — under full delegation the agent decides inside its scope, SKILL.md
Delegation modes; a cross-phase scope move stays his in both modes, `project-management` Scope discipline): the TICKET's owner decides. A loop-owned item decides itself when the surface is off the
never-auto list, the redesign diff sits inside the loop's intake gate (risk ≤ 25 / confidence ≥ 85), and no user-visible policy is added. Lin decides never-auto surfaces, p1/p2 user-visible policy, lane changes;
p3-cosmetic forks go to the desk as a stated default with a 24 h opt-out.
**Board-owned work:** at every checkpoint re-read the wave in the readme and record "Stage-fit: within <wave> because …" — the
reviewer's frame pulls you off-plan (BE#320: 15 rounds).
**The guardrails are not risk-acceptable:** accepting findings never moves a merge gate.

## Closing
- PR-ready = CI green + a verdict on the CURRENT head + every finding dispositioned. A pending re-review is in-flight:
  record "round N pending".
- **PUSH the final fix BEFORE the closure comment** — Codex reads the closure and stands down (BE PR#234). Post the disposition
  as the last comment ("loop CLOSED at round N; open findings + judgment; merge gate = …") and mirror it to the status doc.
  A closed loop reopens only by Lin or a new push.
- Oscillation (a round reversing an earlier ask) or re-litigation (re-filing dispositioned findings) closes the loop early,
  even under a continue-until-clean mandate.
- Handing Lin a held PR with documented open findings IS the endpoint.

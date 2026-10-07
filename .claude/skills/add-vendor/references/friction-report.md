# Friction report — format spec + template

Contents: disposition principles · deliverable contract · Lin's review page (the summary)
· item format (order, labels, exhibits) · decision & defer rules · record structure ·
markdown template. Read at 1-h exit BEFORE writing the report; the format was shaped
item-by-item by Lin on the AOS-CX review (2026-08-18, revs 3–6) — every rule below is one
of his explicit asks.

## Disposition principles (Lin, ratified item-by-item on the AOS-CX review, 2026-08-18)

Pre-filter EVERY recommendation through these before writing it — Lin ordered them
documented after re-ruling four consecutive tool proposals (C-2, C-6, C-7, C-8) to
skill/decline:

1. **Skill before code; build only missing primitives.** If existing tools + prompt/skill
   deliver the outcome — even at detection-not-enforcement assurance — document the
   pattern. A new tool needs a capability that cannot exist agent-side (a missing
   primitive like interactive dialogs) or truth only the server holds (partial-batch
   state, spawn-failure visibility).
2. **No per-vendor lists in code.** Vendor knowledge lives in guides. Per-kind data rides
   ONLY the one existing registry, and only under a generic mechanism. Any code surface
   that grows per vendor is vetoed by default.
3. **Teach at the moment of need.** Guidance rides the RESPONSE (spill pointers, deny
   texts) at zero standing tokens; always-loaded prompt lines must individually earn
   their place.
4. **Lab semantics: fast and smooth wins.** Don't import production-style caution that
   only costs time in a lab (e.g. auto-confirm defaults ON; redeploy recovers anything).
5. **Fold related work; design each contract once.** One issue + one PR per design
   problem; per-item traceability is NOT a goal. Simple uniform schemas beat powerful
   polymorphic ones; a smaller tool set is itself agent UX.
6. **$0 now + an armed trigger beats speculative building.** Decline or watch with a
   NAMED promotion trigger (typically: proven fumble/leak in ≥2 runs, or a product lane
   needs the capability). Build on evidence, not anticipation.
7. **Native competence before platform features.** If the agent's training data already
   covers a native way (device CLI filter pipes, standard Unix tools), use that — a
   parallel platform tool for the same purpose adds tool-choice confusion, not
   capability (C-9: declined output_filter params; agents pipe `| include` natively).
8. **Autonomy tie-breaker — prefer a platform fix over a guide workaround (Lin,
   2026-08-23).** Principles 1/6 still govern: don't build speculatively, and a
   MISSING primitive is the bar for a NEW tool. But when a BUILT primitive is broken
   for its whole class, FIX it rather than paper over it in the guide — a guide crutch
   is agent-discipline debt EVERY future vendor re-pays, and the North Star (one-shot
   autonomy, SKILL.md) needs the platform correct, not a fat guide of workarounds.
   Weigh the DEBT, not just the immediate fix cost: dellos10 C-2 (the dialog engine,
   21-finding review) overrode the draft's document-around lean → the fix let guide
   v11 DELETE the PTY banner workaround. Use the North Star to break a genuinely
   balanced disposition: prefer the option that shrinks future human-decision +
   guide-crutch surface. A fix that only a workaround-free future justifies still
   needs Lin if its blast radius is large.

## Deliverable contract

- **Open items = Lin-only decisions.** Every candidate item takes the test "could I decide
  this from the runs or a known fact?" — yes → DECIDED by the principles above: a known fix
  is fixed, re-probed and certified inside the arc (SKILL.md 1-h; mechanics in its
  friction-fix-wave bullet) and reported SHIPPED under "Decided (FYI)" with its evidence;
  WATCH / DEFER carry trigger + economics there too. "Needs Lin" holds only what the data
  cannot settle — product/policy calls, cost/blast-radius calls, pass-bar rulings with no
  standing default (Lin, 2026-09-29, SONiC arc: 13 labeled items read as 13 asks; 1 was real).
- **A friction list that appears AFTER this report is under the same contract, and the arc owns it** —
  Lin's smoke runs, a feedback lane's re-probe, the short prompts' after-run. Decide every row the day it
  appears, by the test above: a known fix becomes a PR-sized sub-issue and ships (a guide row is
  bench-verified first: 2 of 8 SONiC candidates did not reproduce, BE PR#955), a WATCH / DEFER / DECLINE
  is recorded with its trigger and economics, and only a product call goes to Lin — inside the ONE close
  plan (SKILL.md Project close).
  Never "a triage list for Lin, nothing started", and "outside the delegated lane" is no reason to park
  a known fix (BE#940, 2026-10-01: 12 rows parked; Lin had each explained and approved 9 one by one —
  all 9 shipped, 3 stay parked).
- TWO artifacts, both committed and pushed in `netpilot-dev/projects/<slug>/` (a git repo —
  never a machine-local folder): `friction-review-<date>.md` is the engineering RECORD
  (source of record); the published Artifact page is the summary Lin reviews (next
  section), written to its own file `friction-summary-<date>.html` there and
  linking to the record (same URL across revisions — republish that summary file's
  path). The cloud tag covering ALL project code must be built and verified BEFORE
  presenting (SKILL.md 1-h owns that gate).
- One consolidated disposition surface: bench-probe findings, production self-reports, and
  scenario-ledger items all merge here — never make Lin read two lists. Cross-check every
  item against EXISTING guides first; already-covered items are disposed as guide-adoption
  in the appendix, not filed as open.

## Lin's review page — the summary (Lin, 2026-09-30; SONiC + SR Linux reports ran 500+ lines)

The page Lin reviews is a SHORT plain-language summary of the value shipped and the key
results — never the engineering record. The item-format rules below govern the markdown
record (`friction-review-<date>.md`), which the page links to and Lin never has to read.

- **One screen, about 40 lines**, in this order:
  1. **What shipped** — 2–4 bullets, each a capability in the customer's words and where it
     stands (live in production, in the verified cloud tag, or bench-validated only).
  2. **Key results** — one small table (4–7 rows): the numbers that prove it works, each with
     a plain label and, where useful, the before → after.
  3. **What we found and fixed** — at most 5 bullets, one sentence each: the problem, what we
     did, and the proof.
  4. **Needs you** — the Needs-Lin items, usually "Nothing."; each one plain sentence with
     its options and the recommended pick, so Lin can rule from this page.
  5. **Next** — at most 3 bullets.
  6. **Footer** — a link to the full record and the list of PRs.
- **Plain words only.** No item codes (C-4, P-1), no disposition chips (WATCH, DEFER,
  SHIPPED), no exhibits, no file names or PR numbers in the body, no scenario numbers
  outside the results table. Every line answers "why does this matter to the product or the
  customer?"
- A limit we tested and confirmed is a result ("proven not supported: …"), not a problem.

## Item format (the six Lin-shaped rules)

1. **Group by REPO** (containerlab-mcp / NetPilot-2-Backend / probe-lab+guides / …), with a
   per-repo one-line framing count.
2. **Per item, IN THIS ORDER**: head → agent-UX impact → verbatim exhibit → fix-in →
   why-this-fix. Impact comes FIRST — it is what Lin weighs.
3. **Head labels**, every item: disposition chip — terminal outcomes only under Decided
   (SHIPPED / DECLINED / WATCH / DEFER; a known fix is SHIPPED, never "to fix"), YOUR CALL
   only under Needs Lin · priority **P0–P3** (P0 = shipped a wrong answer to a user or blocks the
   pass bar; P1 = recurring cost or correctness risk; P2 = recurring annoyance; P3 = polish)
   · complexity **small / medium / high** · type **prompt(system|tool|skill) / code / other**.
4. **Agent-UX impact, quantified then exhibited**: calls burned, turn stalls (seconds),
   wrong-answer risk, trust damage — followed by a VERBATIM exhibit from the runs (tool
   output, transcript quote, event ref) in a mono block with a one-line source citation.
   The exhibit does the arguing; never paraphrase where you can quote.
5. **Decisions carry ALL options**: any item that is not finalized — new capability, design
   boundary, scoring policy — lists every viable option (and the rejected ones with why),
   marks ONE recommendation, and ends with a "Why <pick>" line. A pass-bar question with no
   standing default is a Needs Lin item with options; Ruling 0 itself states the settled bar.
6. **Defers and watches carry economics**: why-not-today + the fix-now cost vs the
   defer/watch cost, ending with the armed TRIGGER that converts it to work. A defer
   without a named trigger is a limbo item — not allowed (decide-or-drop rule).

## Record structure (the markdown record, top to bottom)

Header (project · rev · sources · guide/tag state) with a stat row → **Needs Lin (N)** —
the Lin-only decisions, expected N = 0–2, each with its option set → Ruling 0 (the pass bar
as SETTLED: gate scores vs the bar plus the standing defaults applied — witnessed-lines,
hunter-exemption, the non-target-residual waiver, per `convergence.md`; a
genuinely-new pass-bar question is a Needs Lin item, not an options block here) →
**Decided (FYI)** grouped by repo (SHIPPED / DECLINED / WATCH + trigger / DEFER + economics;
items per the format above) → score
matrix (final + vendor-only split per scenario, roll history, guide version per roll) →
"Already adopted + confirmations" appendix (collapsed; guide sections with provenance,
cross-guide lines flagged for review, what-worked confirmations).

## Markdown template

```markdown
# Friction review — Add vendor: <NOS> (1-h loop end)

as-of <date> · sources: <N> judge reports, <probes>, <production reports> · guides
cross-checked: <vendor>-guide v<N> (disk) · fleet tag: cloud-v<X.Y.Z> (verified)

## 1. Executive summary
- Loop numbers: runs, guide v1→vN, score trajectory, cost
- The N dominant non-vendor blockers
- Headline platform discoveries

## 2. Needs Lin (<N>) — only what the runs and known facts could not settle
### <repo name> (<n>)   ← same per-repo grouping + count as §4
#### <KEY>. <Title> [YOUR CALL · P<n> · <complexity> · <type>]  (item format below + Options)

## 3. Ruling 0 — pass bar (settled)
- Gate scores vs bar; standing defaults applied: <witnessed-lines / hunter-exemption / non-target waiver (residual cited)>
- (a genuinely-new pass-bar question is an item under Needs Lin, with options)

## 4. Decided (FYI) — <repo name> (<count>: SHIPPED n · DECLINED n · WATCH n · DEFER n)

### <KEY>. <Title> [SHIPPED|DECLINED|WATCH|DEFER · P<n> · <complexity> · <type>]
**Agent UX impact:** <quantified: calls burned / stall seconds / wrong-answer / trust>
> verbatim exhibit (tool output / transcript quote)
> — source: <run/report, line ref>
[SHIPPED items:]
**Fix in:** `<repo-relative file>` (+ `<file>`) — <one-line fix shape> · **Re-probed:** <scenario(s) + score>
**Why this fix over alternatives:** <dismissed alternatives + why the pick wins>
[YOUR CALL items instead:]
**Options:** A (rec) … / B … / C (rejected) … · **Why A:** … · **If A, validated by:** <scenario / flow to re-run>
[declined items instead:]
**Why declined · economics:** <principle applied + fix cost vs. what it would buy>
[defer/watch items add:]
**Why not today · cost now vs defer:** <fix-now cost> vs <defer cost> · **Trigger:** <named>

## 5. Score matrix
| # | Scenario | Roll history (final) | Latest · guide | Final | Vendor-only | Bar |

## 6. Already adopted (guide-adoption appendix)
- <guide section>: <one-line provenance per earned block>
- Cross-guide lines (flagged for after-the-fact review): <file: line, provenance>
```

## Provenance

AOS-CX first execution: the 2026-08-18 friction review (+ its artifact, revs 1–6) — the worked
example for every rule above. Lin's shaping asks,
in order: repo grouping + file-level fixes + rationale (rev 3) · agent-UX impact (rev 4) ·
impact-first order + verbatim exhibits (rev 5) · labels + option-sets + defer economics
(rev 6).

# Acceptance, loading and shipping

14. **Process: every prompt change is a review-umbrella row.** Decided change → sub-issue →
    PR citing evidence (probe/binary/transcript) → merged row flipped to SHIPPED on the
    umbrella (BE#331 pattern). After material changes, re-render the walkthrough artifact so
    the documented prompt never lies about production.
15. **A skill that does not LOAD cannot help — check loading before rewriting its body.** The
    frontmatter `description:` is the only trigger, so it names the task in the USER's own
    words: the failure-drill baseline never loaded `network-experiment-guide` until its
    description said "shutting down a node" and "bond member" (BE PR#933, 2026-10-01). The
    description is YAML — an unquoted `any of: …` fails `yaml.safe_load` although the CLI
    tolerates it — so a parse test pins it beside the trigger-word pins (backend
    `test_network_experiment_guide.py` is the pattern); the truncation check for a longer one
    is `probe-testing/probe-recipes.md` §I.
16. **A rule that fires on ONE tool result rides that result — and no prompt line ships on reasoning
    alone.** Two one-line L2 rules written for a single moment failed their acceptance probes: "first
    check after a deploy: wait, do not diagnose" (2 of 7 clean against 1 of 3 on main, never cited —
    the same sentence appended to the deploy RESULT by a PostToolUse hook's `additionalContext` was
    quoted and held 3 of 3; BE#948) and a closing-report honesty line (26 of 167 claims unsupported
    without it, 25 with it, on the same forked sessions; BE#922). So: the sentence goes on the result
    (L4; a hook reaches every VM package) and L2 keeps what no result can carry; it states the READING
    as well as the action ("is still coming up, not a fault"); a state-dependent note leads with its
    CONDITION and is never a top-level imperative field (`action_required: "Cisco IOL not available…"`
    was obeyed by a SONiC request; BE#947); and every key the guidance names is checked against the
    keys the formatter emits — a line listing a result's forms against every value the source can
    print, its initial one included (BE PR#961). The acceptance probe and its decision rule are
    written BEFORE the edit (`probe-testing` checklist step 1), and a rule that fails it is re-homed
    or dropped, not reworded a third time.
17. **Agent-facing text is written for the CURRENT VM package only** (Lin, 2026-10-02: "we don't even
    need to add any fallback text during the project … focus on ship fast, not spend too much time on
    old compatible problems"). No "from package X on; on an older package …" clause in a prompt, tool
    text or guide — not during a project, not at its close, and none waits for a fleet sweep to be
    removed; a user on an older package gets the Update VM prompt. The backend's class pin is
    `tests/unit/test_agents/test_no_older_vm_package_text.py`.

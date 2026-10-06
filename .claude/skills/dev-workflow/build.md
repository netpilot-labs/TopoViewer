# Build — before designing the change

- **Locate the owning LAYER before designing a behavior fix** — our hooks/prompt/tools vs the pinned CLI binary. A "hook" that
  was really the CLI's native behavior collapsed a whole fix to one prompt sentence (BE#329).
- **A new endpoint accepting config-like TEXT needs a Cloudflare WAF check before it ships:** replay a REALISTIC payload (a real
  router config) unauthenticated against the prod edge — expect the endpoint's 401, not a 403 HTML page (no CORS headers,
  nothing in backend logs). Fix = zone custom rule skipping managed rules for that method+path (BE#420; still latent on
  `/api/v1/lab-bundles/import`).
- **An MCP tool's RESULT shape is a cross-repo contract** with `components/assistant-ui/tools/tool-mcp-*.tsx`, and nothing
  links the repos. Change a containerlab-mcp result shape → sweep the FE renderer in the same arc; FE detects special entries
  by SHAPE (FE#375).
- **Renaming a user-visible label:** grep the ROOT word, synonyms, "X tab/page/panel" forms, and other repos' guidance strings
  (FE PR#309).
- **De-blocking an async path removes accidental atomicity** — every check-then-act around the converted call is now a race;
  collapse into one sync hop or use idempotency (BE#366); a predicate that gates a write on a DEDICATED session is
  re-evaluated in FULL under that write's row lock, from one shared function (BE PR#903).
- **Move-only refactors are not behavior-identical:** `Path(__file__).parents[N]`, `getLogger(__name__)` (Sentry filters), and
  test `patch("old.module.symbol")` targets that silently stop intercepting (BE PR#215).
- **Narrowing a shared predicate widens every caller that leaned on the removed condition** — restore the requirement at the
  consumers that own it, not in the helper (FE PR#230).
- **A "never lose X" restore needs a bound** (generation token or owner check, same commit) or it re-delivers X into the NEXT
  user's context (FE#217 R10).
- **Never resolve a user by a provider-echoed identifier** (payer email, OAuth email) on a billing/auth surface unless the app
  BINDS it at creation; the anchor is the id WE persist. A fallback-capable resolver also breaks every downstream re-lookup by
  the original key — switch them to the resolved row's id (BE#316).
- **A new concurrency primitive: write the protocol table BEFORE coding** — grep every writer/reader of the guarded columns,
  precondition + failure path per site, in the design issue (BE PR#698→#716: 11 rounds otherwise).
- **A step that CLAIMS a key before an external write** (Stripe/Clerk/cloud) writes its crash-window table before the first
  commit; a table that does not fit one screen wants a ledger row with a status column (BE PR#882).
- **A minutes-long operator run composing DESTRUCTIVE product paths** (VM destroy, Clerk delete, release) writes its
  RESUME-OWNERSHIP table before R1: per step, what is durable before the destructive call (markers with a generation id per
  (owner, resource) and a retirement row after each destroy — names are reused), what a retry re-reads under the lock, and
  what it must never target (anything not in the recorded set, anyone bound elsewhere or released before the run). Findings
  against a posted table are dispositions; against one never written, rounds (BE PR#892: 11 rounds, one family).
- **A new guard matches its SIBLING branches' contract** (what they do besides `continue`, e.g. adding to `handled`); on the
  third path reaching the same destructive call, guard where the inputs are BUILT (BE#847).
- **A multi-side-effect operation converges UNCONDITIONALLY:** never branch on "did anything change?" to pick WHICH side
  effects run — every apply/retry converges every effect idempotently and `changed` is display only; otherwise each retry
  interleaving is its own review finding (BE PR#631, #637: both loops 6→2 after the restructure).
- **A code comment that states what a THIRD-PARTY tool does is a claim:** observe it on the pinned version before the first
  push, or word it as unverified ("containerlab reports an exec with any stderr as failed" was false on 0.77.0, passed five
  Codex rounds and cost a second PR — clab PR#266 → #267).
- **"Code reduction" is app-only:** `git diff --stat <base> <head> -- app`, never the full stat (PR#716).
- **Customer-copy changes: grep a 3–4 word fragment over `docs/`**, not the sentence — Markdown wraps (BE PR#841).
- **Promise-tightening across repos:** merge + deploy the COPY reduction first, enforcement last; loosening is the mirror
  (BE PR#454).
- **Migrations:** never a bind parameter inside an ON CONFLICT target — render literals (`literal_column`); the plan-cache bug
  fires on execution 6 (BE#325). `CREATE INDEX CONCURRENTLY` gets its own revision (BE PR#624). Autogen: strip the recurring
  `permission_requests_cleanup_idx` drop (BE#176) and NAME every FK added to an existing table (`<table>_<column>_fkey`) or
  `downgrade()` cannot run; prove `downgrade -1` + `upgrade head` locally (BE PR#763). `%` in `DATABASE_URL` breaks alembic;
  `env.py` already sets `lock_timeout = 5s` — edit it to change the bound (BE PR#807).

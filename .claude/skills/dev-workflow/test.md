# Test — red-proof, local CI-parity, harness traps

Contents: red-proof · CI-parity · frontend harness · backend harness · local infra

## Red-proof (every regression test; Lin, FE PR#195)
- **A regression test counts once you have SEEN it fail without the fix.** Cheapest: TESTS FIRST — write the assertions on the
  unchanged tree, run red, then implement (FE PR#544). Fix already written: `<skill-dir>/scripts/redproof.sh <file> --ref
  origin/main -- <test cmd>` (`--ref HEAD` for an uncommitted fix; `--sub <old> <new>` for one exact mutation) — it first runs
  the command GREEN on the unmutated file (a test that is already failing proves nothing: exit 3, no proof; BE#962), runs
  bounded and puts the file back byte-checked even when the red run hangs; exit 0 = red seen. A NEW harness errors at
  fixture setup against `main`, which proves little: one `--sub` mutation per mechanism instead (clab PR#266, BE PR#953).
- **Never `git stash` for a red-proof:** it no-ops on a committed fix (exit 0, the "proof" tests the fix itself) and a `pop`
  after a broken chain applies another lane's WIP (BE PR#454, #675, #777). Say in the PR body which run proved which tests.
- **Red-proof ONCE, when the test is written;** later rounds re-prove only tests they add or change (BE PR#630).
- **Read the red run:** `Transform failed` / "no tests" proves nothing, and an EMPTY log is a run that never happened
  (`timeout 300 pytest … | grep` on a Mac: no `timeout`, exit 0, BE PR#961) — the script prints the run's last lines.
  A proof done by hand reverts in the SAME tool round, purges the module's `.pyc` (a same-second, same-length edit leaves
  a stale one, BE#260) and is bounded: a red run that HANGS leaves the MUTATED file on disk (BE PR#904, 2026-09-29).
- **Never mock the transform under test** — at least one test drives the REAL pipeline from raw inputs (#195). A fixture that
  encodes your BELIEF about an external system proves nothing: match what the program actually writes (tusd `.info`, clab#39;
  `httpx.MockTransport` buffers, BE#258).
- A "defaults to X" test after a `beforeEach` that sets X is vacuous; module singletons need `vi.resetModules()` + dynamic
  import (FE PR#309). Cancellation tests need a real suspension point (BE#258). Prepared-statement/plan-cache behavior: loop the
  statement ≥10× on ONE pooled connection (BE#325).

## Local CI-parity
- **Run CI's EXACT commands** (flags from the workflow yml) on the FINAL tree — any edit after the parity run voids it, and a
  green test run never stands in for the type check (FE PR#198, PR#267).
- **Backend** = ruff + mypy + `uv run pytest tests/unit`, never `-m "not claude_api"` (runs integration against live infra);
  never two backend suites at once (shared `netpilot_test` DB) — beside sibling lanes every run goes through
  `<skill-dir>/scripts/with-db-lock.sh` (lanes.md). **Frontend** = full `pnpm test:coverage`, not changed-file
  suites — a store-shape change breaks every partial `getState` mock (37 failures, FE#255).
- **Text-only pin files** (guide/prompt pins whose tests take no fixture and only read text) run as `uv run pytest
  --noconftest -p no:cacheprovider <files>`: no DB, no lock, under a second. Only those — `conftest.py` also carries the
  prod-credential scrub and the network kill-switch — and the full suite still runs once on the final tree (BE PR#958: a
  5 s pin run waited 25 min for the lock).
- **Enumerate blast radius by what EXERCISES the changed symbol, not by directory;** never call an unverified full-suite
  failure "environmental" (BE#327).
- Scope by change type: lockfile-only bump → type-check + lint; framework bump → also `pnpm build`; source → full parity.
- **Killed harness tasks orphan pytest grandchildren** — check `\.venv/bin/pytest` processes from a script FILE before
  diagnosing a "flaky" failure; wait for a sibling lane's suite, never abort it (BE#315, #756).
- `pytest -p no:logging` removes `caplog` (105 phantom errors, BE#772) — quiet with `-q`.

## Frontend harness
- **A Next dev server runs StrictMode** (mount effects fire twice): red-proof an effect-ordering fix with
  `reactStrictMode: false` (temporary) or a prod build (FE PR#516).
- Testing Library `rerender(el)` with the SAME element re-renders nothing over a non-reactive mocked store — build the element
  per call (FE PR#523). The `runtime-provider-*` harness's `onNew` bypasses the composer enqueue — assert the turn-end signal via
  `vi.mock` of `useQueueFlush` with `importOriginal` (FE PR#531). The session store's `setError` keeps only `{name, message}` —
  discriminate by `name`, never `instanceof` (FE PR#531).
- `AbortSignal.timeout()` ignores fake timers — `AbortController` + `setTimeout` (FE#497). `beforeEach(() => mock.mockReset())`
  RETURNS the mock and vitest calls it as an after-hook — brace it (FE PR#506). TanStack Query re-renders only for props the
  test already READ — touch `result.current.data` before asserting a cache write (FE PR#506).

## Backend harness
- **A test of a wake-up path asserts WHAT woke it** (the event set, a spy on the poll never awaited) under a generous hang
  guard (`asyncio.wait_for(…, 10)` → `pytest.fail`), never an upper wall-clock bound near the expected latency: a 1.0 s
  bound read 1.026 s on a shared runner and turned `main` red on a Markdown-only merge. A LOWER bound is safe (BE PR#953).
- One MonkeyPatch per test is shared with conftest autouse fixtures — `monkeypatch.undo()` undoes the conftest too (BE PR#322).
  `monkeypatch.setattr(mymodule.os, …)` patches the GLOBAL `os` — use an arg-aware fake (BE#416).
- `await db.rollback()` expires every loaded object → `MissingGreenlet` in a pool frame; wrap the raising call in
  `async with db.begin_nested()`. Rows created in one transaction share `created_at` — `commit()` between creates (BE PR#767).
- A `MagicMock` session hides `expire_all()` → `MissingGreenlet`; `MagicMock(spec=Model)` makes every property truthy — set
  them (BE PR#800).
- Pattern-matched bulk inserts can land inside commented-out code (a `defer mu.RUnlock()` at function scope = deadlock;
  TopoViewer PR#6) — eyeball every insertion site.

## Local infra
- The local `netpilot` DB is shared by every lane and moves under a sibling's migration (`Can't locate revision …`). Bring
  `netpilot_test` to YOUR head and both autogenerate and validate the up/down/up roundtrip there (`revision --autogenerate`
  needs a DB at your head too); leave the shared DB alone (BE PR#799, PR#898).
- **Docker Desktop (macOS) does not share the session scratch dir** (`/private/tmp/…`): a `-v` bind from it arrives EMPTY (a
  file as an empty directory) with no error. Bind only paths under `/Users`; pass a scratch script on stdin
  (`docker run -i … bash -s < script`) or a tree as `tar -cf - . | docker run -i … tar -xf - -C /work` (clab PR#265, PR#266).

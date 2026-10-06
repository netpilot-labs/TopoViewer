## Impact model — memorize this line

Phases 1–9 have **zero customer impact** (throwaway VMs and a staged image only).

**Three gates:**
1. the optional Phase-0 live de-risk on `linzhu-vm` (a real user VM — his own): Lin's explicit OK.
2. **Phase 10 `--family` promotion**, which reaches every new user VM instantly: STANDING direction
   for the code-only rebuild after each `cloud-v*` tag (Lin, 2026-10-02) — no separate go, provided
   Phase 9 passes on EVERY check; a deviation stops and reports. A build with an image-level delta
   needs his explicit direction — inside a vendor project `add-vendor`'s touchpoints carry it.
3. **Phase 10b fleet patch**, which touches existing user VMs: always Lin's explicit direction.
   Inside a vendor project that direction IS his "close the project" — it covers the final cut,
   its promotion and the one close-time sweep, no per-action go (Lin, 2026-10-02; `add-vendor`
   Project close).

Default endpoint for a gated build without direction: finish Phase 9 including VM cleanup, report, and
hold. **A staged image keeps zero impact indefinitely** — there is never a reason to promote to
"finish the job".

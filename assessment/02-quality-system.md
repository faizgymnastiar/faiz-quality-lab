# Quality System — Workflow Gate + CI Regression Net

This net has two halves, per the brief: a **workflow gate** that hardens the
process (no change ships without its inputs), and a **CI regression net**
that hardens the code (real defects from `01-audit.md` go red automatically).
Both are wired into a single `quality-gate.yml` workflow that runs on every
PR against `main`.

## 1. Workflow gate (Definition of Ready)

**Files:** `.github/PULL_REQUEST_TEMPLATE.md`, `scripts/check_dor.py`

A PR template alone cannot block a merge — it's a UI hint, not enforcement;
a developer can delete it or leave every section blank and GitHub will not
notice. `check_dor.py` closes that gap: it reads the PR body via
`github.event.pull_request.body` and fails the build unless four sections
are present with real content (not just template placeholder comments):

- **Spec / PRD** — link, or an explicit `NO SPEC EXISTS` declaration
- **Acceptance Criteria**
- **Solution / Design Plan**
- **Testing** — which spec(s) cover this change, or an explicit `docs only`
  exemption, plus a checked "I ran the full test suite locally" box

This directly targets the case study's core problem: *work that starts from
a ghost spec*. No inputs, no green — enforced automatically, no human has to
remember to check.

**What it deliberately does not cover:** it cannot judge whether the spec
or acceptance criteria are *good*, only whether something real was written.
Quality of the answer is still a human review job. This is a conscious
trade-off — a cheap, unambiguous check beats a subjective one CI can't
actually adjudicate.

## 2. No Test No Merge

**File:** `scripts/check_test_coverage.py`

For every changed file under `api/app/**/*.rb`, requires a correlated
change under the mirrored `api/spec/**/*_spec.rb` path in the same PR.
A short, explicit `EXEMPT_PREFIXES` list (views, mailers, db, config)
keeps this from producing false positives on files that genuinely don't
need a unit spec.

**What it deliberately does not cover:** existence of a spec file, not
quality of its assertions. A one-line placeholder spec would technically
pass this check — that's why it's paired with human review and with the
targeted regression specs below, which assert real invariants rather than
just "a test ran."

## 3. Regression specs — targeting the real issues from `01-audit.md`

These are not generic scaffolding; each one encodes an invariant that the
current codebase violates, per the audit's evidence, and is expected to be
**red** until Task 3 lands the fix.

| Spec | Audit finding | What it asserts |
|---|---|---|
| `api/spec/services/portfolios/generator_spec.rb` | **F1** (P1) | An assessor's manual override survives portfolio regeneration — currently destroyed via `destroy_all` + recreate with a new primary key |
| `api/spec/models/session_spec.rb` | **F4** (P0) | `Session#invite_url` points at the web app's `/interview/:token` route, never at the API's own port |
| `web/src/utils/internetSpeedTest.test.ts` | **F5** (P1 conditional) | Every speed-test measurement function settles within a bounded time even when the underlying `fetch` hangs — currently unbounded |

F1 and F4 were chosen because they are the highest-severity, highest-confidence
findings with unambiguous evidence (exact method, exact line, reproduced
end-to-end). F5's timeout sub-bug was chosen because it is the one part of
that finding that's cleanly unit-testable in isolation, without needing a
live network to reproduce.

**Findings intentionally not covered by an automated check yet, and why:**

- **F3** (coverage-state threshold mismatch) — the audit itself frames this
  as `[MISSING SPEC]`, not a confirmed bug: there's no PRD defining what
  "covered" should require, so a test would be encoding a guess, not a
  contract. This is flagged in the DoR gate's domain (send it upstream for
  a spec), not the regression net's.
- **F6** (tenant scoping unenforced in Sidekiq workers) — the audit notes
  this needs *live verification* (seed two orgs, trigger a worker, inspect
  what it touches) before it's a proven, testable regression rather than a
  structural risk. Writing a test against an unconfirmed exploit path risks
  encoding a false sense of safety — worse than no test. This is the next
  regression spec to add once that verification happens.
- **F7** (JWT trusted without DB lookup) — audit recommends confirming
  intended token TTL with whoever owns the shared auth layer before treating
  it as a defect to fix unilaterally; not something CI should silently gate.

This is the "small and sharp, not a thousand trivial tests" principle in
practice: every check here maps to a real, evidenced class of failure, and
the ones left out are left out for a stated reason, not an oversight.

## 4. CI wiring

**File:** `.github/workflows/quality-gate.yml`

```
Create Pull Request
        │
        ▼
Definition of Ready ──── FAIL ───► blocked, no spec/criteria/plan
        │ PASS
        ▼
No Test No Merge ──────── FAIL ───► blocked, app change with no spec change
        │ PASS
   ┌────┴────┐
   ▼         ▼
Backend    Frontend
RSpec      lint/test/build
(incl.     (incl. F5 spec)
F1/F4
specs)
   └────┬────┘
        ▼
Quality Gate Summary ──► required status check for branch protection
```

The two workflow-gate checks run first and gate the expensive checks —
no point spinning up Postgres/Redis and running the full suite on a PR
that doesn't even have a linked spec.

## How to run it locally

```bash
# Backend
cd api
bundle install
bin/rails db:create db:schema:load
bundle exec rspec                          # F1 and F4 specs will fail (red) until Task 3

# Frontend
cd web
npm ci
npm run lint
npx vitest run                             # F5 spec will fail (red) until Task 3

# The gate scripts themselves (can be run against any PR body for a dry run)
PR_BODY="$(gh pr view <PR_NUMBER> --json body -q .body)" python scripts/check_dor.py
python scripts/check_test_coverage.py main
```

## How to extend it

- New Definition-of-Ready requirement → add a heading to
  `REQUIRED_SECTIONS` in `check_dor.py` **and** to the PR template — the two
  must stay in sync, since the script parses the template's own headings.
- New file type that should never need a spec → add its prefix to
  `EXEMPT_PREFIXES` in `check_test_coverage.py`, with a one-line reason in
  the commit message.
- New confirmed regression → add a spec named after the audit finding ID
  (`spec/.../whatever_spec.rb` with a comment block citing the finding),
  the same pattern as F1/F4/F5 above, so the next engineer can trace every
  check back to the evidence that justified it.

## Demonstrating the gate (two PRs)

Per the brief, the workflow gate is demonstrated, not just described:

- **PR that the gate blocks:** a change to an `app/` file with no
  correlated spec change and a PR body with an empty Acceptance Criteria
  section — `no-test-no-merge` and `dor-check` both fail.
- **PR that the gate passes:** the same kind of change, this time with a
  correlated spec file and a fully-filled PR body — both checks go green.

Both PRs are left visible in the repo (see links in the PR list) so the
gate can be seen firing red and green on its own, without a human forcing
either outcome.

## Red-to-green story (updated in Task 3)

_To be filled in once Task 3 lands the fixes: what was red here, what
changed, and confirmation that each check is now green because the defect
was fixed, not because the check was weakened._

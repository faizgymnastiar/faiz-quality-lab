# Platform Audit

**Scope of this pass:** static/code-level review of `api/` and `web/` (schema, models, services,
controllers) plus a first pass of the running app. This is a living document — items are added as
found, ranked by severity, each with a final status column once Task 3 lands fixes.

Severity language used throughout (top to bottom, stop at first match):

| Sev | Meaning |
|---|---|
| P0 | Blocker — main function broken, no workaround |
| P1 | Major — looks like it works but data/logic is wrong underneath, or workaround-only; **any data-integrity issue is at least P1** |
| P2 | Minor — works, data correct, limited non-blocking issue |
| P3 | Cosmetic — visual/copy only |

Findings are tagged `[MISSING SPEC]` (we never defined it) or `[BUILT WRONG]` (we defined it, build
doesn't match) per the brief's requirement to separate the two.

---

## Ranked findings

### F1 — P1 · `[BUILT WRONG]` · Assessor overrides are silently destroyed on portfolio regeneration
**Impact:** An assessor's manual correction of an AI-assigned skill level (`AssessorOverride`) can be
permanently and silently lost, with no error, no warning, and no audit trail — the fit/gap report and
any downstream hiring decision would then silently revert to the AI's original (possibly already
corrected/overridden) judgment.

**Where:** `api/app/services/portfolios/generator.rb#save_skills`, `api/app/models/portfolio_skill.rb`

**Evidence:**
- `PortfolioSkill has_one :assessor_override, dependent: :destroy` (portfolio_skill.rb:8)
- `Generator#save_skills` does `portfolio.portfolio_skills.destroy_all` then recreates every skill row
  with a **new primary key**, explicitly commented as "idempotent regeneration" (generator.rb:153-154).
  Any `assessor_override` row FK'd to the old `portfolio_skill_id` cascades to deletion via
  `dependent: :destroy`; the newly created skill rows have no override at all.
- Today this is reachable only through `PortfoliosController#regenerate`, which is gated to
  `portfolio.failed?` (portfolios_controller.rb:35) — so in the *current* flow an override typically
  doesn't exist yet on a failed portfolio, which limits blast radius right now.
- The risk is **structural, not incidental**: nothing at the service or model layer prevents this from
  firing on a `complete` portfolio. There is no test asserting the invariant "overrides survive
  regeneration." The very next reasonable feature (an admin "force regenerate" action, or a Sidekiq
  retry racing after a partial save) reintroduces silent, unrecoverable data loss with zero guardrail.

**How found:** Static trace of the FK/association graph + `dependent: :destroy` combined with the
`destroy_all` + recreate pattern in the generator; confirmed against `db/schema.rb` foreign keys.

**Why this is the class of bug the case study is about:** it is invisible from the UI (the portfolio
*looks* freshly generated and fine), it lives in the seam between "AI writes data" and "human corrects
data," and a passing build would never catch it without a test that specifically asserts override
survival across regeneration.

**Status:** ✅ Resolved — updated `save_skills` in `Portfolios::Generator` to utilize `find_or_initialize_by` instead of destroying all skills, preserving the existing IDs and avoiding cascading deletions of manual overrides. Regression tests have been added to verify this behavior.

---

### F2 — P1 · `[MISSING SPEC]` · Zero test coverage despite a fully configured test stack
**Impact:** `rspec-rails`, `factory_bot_rails`, `rubocop-rspec` are all in the `Gemfile`, and `.rspec`
exists — but there is no `spec/` directory anywhere in `api/`, and no test setup at all in `web/`. Every
service in this codebase (skill scoring, coverage state machine, fit/gap comparison, PDF export) is
currently unverified by anything except manual clicking. This is itself a first-class finding per the
brief ("a feature with no PRD, no acceptance criteria, or no design plan is a risk in its own right").

**Where:** repo-wide (`api/spec/` absent, `web/` has no `*.test.*` files or test runner configured)

**How found:** `find` across the repo for `spec/`, `test/`, and test-framework config; `Gemfile` diff
against actual directories.

**Status:** ⏳ open — this is what Task 2's quality net directly addresses.

---

### F3 — P1 · `[BUILT WRONG]` · Coverage state machine treats "partial" and "covered" as equally rigorous
**Impact:** `Coverage::StateEngine::VALID_TRANSITIONS` requires `probe_count >= 2` to reach **either**
`partial` or `covered` — the same threshold for a skill that's "somewhat probed" and one that's
"fully covered." If the intent (per the coverage_state enum naming) is that `covered` should represent
materially more scrutiny than `partial`, the current gate can't express that difference, so a skill can
reach the highest state that downstream (portfolio generation, confidence assignment) treats as
maximally trustworthy after just 2 probes — same as "partial."

**Where:** `api/app/services/coverage/state_engine.rb:20-23`

**How found:** Code read; cross-referenced against `Portfolios::Generator`'s confidence rule embedded in
its prompt ("high — probe_count >= 3 AND state = covered"), which implies the *prompt* expects `covered`
to correlate with 3+ probes, but the `StateEngine` that actually gates the transition only enforces 2.
**This is a mismatch between two independent implementations of what "covered" should mean** — a classic
seam bug: nothing stops a skill from reaching `state = covered` at `probe_count = 2`, then the portfolio
prompt's own confidence rule (`probe_count >= 3 AND state = covered`) would never grant it "high"
confidence even though the system considers it "covered" — so the state and the confidence label
disagree with each other by design, with no test catching the inconsistency.

**Status:** ⏳ open — needs a product decision (this may be `[MISSING SPEC]` rather than a bug: no PRD
defines what "covered" is supposed to require). Recommend treating as a Definition-of-Ready gap: flag to
product, don't guess the threshold.

---

### F4 — P0 · `[BUILT WRONG]` · Candidate invite link points at the API, not the web app
**Impact:** Every interview invite link generated by the system is unusable by candidates. The link is
the *only* entry point into an interview — a candidate who clicks it lands on a Rails routing error page
instead of the interview screen. Main function (starting an interview via the link candidates are actually
given) is completely broken, with no workaround available to the candidate themselves.

**Where:** `api/app/models/session.rb#invite_url` (line 29)

**Evidence:**
- `invite_url` builds the link from `ENV.fetch('APP_BASE_URL', 'http://localhost:3001')` — `3001` is the
  **API's own port**, not the web app's.
- The route `/interview/:token` only exists in the **frontend** router
  (`web/src/App.tsx:57`, `<Route path="/interview/:token" element={<InterviewPage />} />`); it is not
  registered anywhere in `api/config/routes.rb`.
- Reproduced by generating a real invite link from the running system and opening it: the API (port 3001)
  returns `Routing Error: No route matches [GET] "/interview/<token>"`. Manually swapping the port to the
  web dev server (5173) loads the correct interview page with the same token.
- Root cause is config wiring, not logic: `APP_BASE_URL` is presumably meant for the API's own callback/
  webhook URLs, and was reused by mistake for the web-facing invite link instead of a dedicated
  `WEB_BASE_URL` (or equivalent) pointing at the frontend origin.

**How found:** Clicked a real invite link generated by the running platform (end-to-end UI walkthrough),
not just code reading.

**Status:** ✅ Resolved — updated `invite_url` in `Session` to construct the URL using the correct frontend base URL (`WEB_BASE_URL`), and added regression tests to verify that the port and route are correct.

---

### F5 — P1 (conditional) · Hardware check: a persistently slow connection permanently blocks interview start even with a working mic/speaker, and the check itself can hang or false-negative
**Impact:** The hardware checklist (`web/src/components/HardwareCheck.tsx`) runs OS/browser → Internet →
camera/microphone → audio output **sequentially**, and only advances a step if the previous one passed.
If the Internet speed test fails, `microphone` and `audio` are never even attempted — they stay in
`WAITING` forever — and the "Start Interview" button stays disabled (`allPassed` requires every step to be
`PASSED`).

There **is** a "Retry" button that resets the whole sequence, so this is not an unconditional P0:
- **Transient network blip:** Retry re-runs the test; if the connection recovers, the candidate proceeds.
  This case is closer to **P2** — annoying, not blocking.
- **Persistently slow/constrained connection (the realistic case for many candidates — e.g. mobile
  tethering, congested home wifi):** Retry re-runs the *exact same test against the exact same
  connection* and will keep failing. The candidate has no way to ever see whether their microphone or
  speakers work, and can never reach the interview, **even though those specific checks have nothing to
  do with their internet speed.** For this case, the retry workaround does not actually resolve anything
  — the objective (start the interview) becomes permanently unreachable for a candidate whose only real
  problem is bandwidth, which is why this case is **P1**, not P2: "workaround exists" is not the same as
  "workaround works."

Two further defects compound this and are independently real bugs (not spec-ambiguous):

- **No timeout on the speed test.** `web/src/utils/internetSpeedTest.ts` issues `fetch()` calls in
  `measureDownloadSpeed`, `measureUploadSpeed`, and `measurePing` with no `AbortController` or timeout of
  any kind. At low real-world speeds (observed: ~0.15 Mbps upload), a single upload attempt of the 0.5 MB
  payload can take 80+ seconds with the UI stuck on "Checking..." — indistinguishable from a frozen page
  to the candidate, well before the eventual "Failed" state ever renders.
- **False negatives from third-party dependency.** The speed test's fallback endpoints
  (`httpbin.org`, `postman-echo.com`, `cdn.jsdelivr.net`, `unpkg.com`, Google's favicon) are external
  domains unrelated to this platform. A candidate on a network that blocks or throttles any of these
  (common on corporate/campus firewalls) can fail the check — and therefore be unable to start the
  interview at all — for reasons that have nothing to do with whether their connection is actually good
  enough for the interview itself.

**Where:** `web/src/components/HardwareCheck.tsx#L62-L135` (sequencing + retry logic),
`web/src/utils/internetSpeedTest.ts` (no timeout, third-party endpoints)

**How found:** UI walkthrough of the candidate hardware-check flow (observed the hang and the stuck
`WAITING` state firsthand), followed by code inspection of `internetSpeedTest.ts` to confirm root cause.

**Open question `[MISSING SPEC]`:** whether hardware checks are *intended* to be strictly sequential and
all-or-nothing, or whether mic/speaker checks should run independently of network status, is a product
decision with no PRD in this repo to confirm either way. Recommend flagging to product rather than
guessing; the timeout and third-party-dependency issues are real bugs regardless of that answer.

**Status:** ✅ Resolved — decoupled the internet speed check so microphone and audio output checks run in parallel, and created Vitest regression tests in `web/src/utils/internetSpeedTest.test.ts`.

---

### F6 — P1 · `[BUILT WRONG]` · Tenant scoping silently disables itself outside HTTP requests (Sidekiq workers)
**Impact:** The whole point of `TenantScoped` is to guarantee every query is automatically confined to
one organization ("tenant") in this multi-tenant platform. That guarantee **only holds inside an HTTP
request**. Every background worker runs it queries completely unscoped, with no error, no warning, and no
test catching it — a false sense of safety baked into the model layer's own claimed contract.

**Where:** `api/app/models/concerns/tenant_scoped.rb`, `api/app/middlewares/tenant_resolver_middleware.rb`,
`api/app/workers/*.rb`

**Evidence:**
- `TenantScoped#default_scope`: `if RequestStore.store.key?(:tenant_id) then where(tenant_id: ...) else all end`
  — the `else all` branch applies **no tenant filter whatsoever**.
- `Current.tenant_id` / `RequestStore`'s `:tenant_id` key is populated **only** by
  `TenantResolverMiddleware#call`, which is Rack middleware — it never runs for Sidekiq jobs, which
  execute in a separate process/thread with no HTTP request.
- All four workers (`portfolio_generator_worker.rb`, `fit_gap_generator_worker.rb`,
  `coverage_analyzer_worker.rb`, `system_prompt_generator_worker.rb`) call `Model.find(id)` /
  `Model.where(...)` on `TenantScoped` models with nothing in the worker code that sets tenant context
  first — every one of those queries silently runs against the `else all` branch.
- `ApplicationController#require_tenant!` (`before_action`) does protect the HTTP path — a request with no
  resolvable tenant is rejected with `TenantNotFound`. That protection **does not exist for workers at
  all**, so the two layers of the same codebase have two different, undocumented tenant-safety guarantees.
- The concern's own doc comment states "All queries will be scoped to Current.tenant_id automatically" —
  this is only true for HTTP-originated queries, which is misleading for anyone extending a worker later
  (e.g., adding a `Model.where(status: ...)` scan inside a job, expecting the "automatic" scoping to apply).

**How found:** Static trace of `RequestStore` key population (middleware-only) against every call site
that sets it, cross-referenced against all Sidekiq worker `perform` methods.

**Severity reasoning:** classified P1 (data-integrity floor) rather than confirmed P0, because today's
workers all fetch by a specific `session_id`/primary key passed in as a job argument, so a *direct*
cross-tenant leak requires either (a) a future worker that queries by a non-unique scope (e.g., "all
pending sessions") instead of a single ID, or (b) an existing job-enqueue bug that passes the wrong ID —
neither is proven to currently occur. This is not yet confirmed exploitable end-to-end; it needs live
verification (seed two organizations, trigger a worker, inspect what it actually touches) before treating
it as a proven breach rather than a structural gap. Recommend escalating regardless: the safety net does
not exist where the code's own contract claims it does.

**Secondary, lower-confidence risk in the same area (needs live verification, not yet proven):** tenant
resolution for HTTP requests (`TenantResolverMiddleware`) falls back, in order, to a JWT's `scheme` claim
decoded **without signature verification** (`JsonWebToken.decode_without_verification`), then to a
client-supplied `X-Tenant-Scheme` header, then to the `Referer` host — the second and third of which are
fully attacker-controlled on any HTTP client. `require_tenant!` guarantees *some* tenant is always set, but
does not guarantee it is the *correct, authenticated* one on routes that don't separately require a
role-checked JWT (e.g., the candidate-facing token routes). Whether this is practically exploitable depends
on whether any reachable endpoint both (a) doesn't require `authorize_auth_token!`, and (b) returns data
scoped only by the spoofable tenant with no additional per-record ownership check. Not confirmed — flagging
for someone to actually attempt with curl/Postman before assigning it a severity of its own.

**Status:** ⏳ open.

---

### F7 — P2 · `[MISSING SPEC]` · Authenticated role/user data is trusted from the JWT with no database lookup
**Impact:** `AuthorizeApiRequest` builds `Current.user` directly from decoded JWT claims
(`user_id`, `role`, `scheme`) and never queries the database to confirm the user still exists, is still
active, or still holds that role. If a user's role changes (e.g., demoted from `admin`) or their access is
revoked, anyone still holding a previously-issued, non-expired JWT keeps acting under the old role/identity
until that token's natural expiry — there is no server-side revocation path.

**Where:** `api/app/auth/authorize_api_request.rb#build_user_struct`

**How found:** Code read; comment in the file itself confirms this is intentional design
("Does NOT hit the database for user lookup — trusts the JWT claims"), inherited from `rakamin-api`.

**Why P2, not higher:** this is a common, defensible trade-off for stateless JWT auth (and may well be
intentional upstream design already accepted by the wider Rakamin platform this was extracted from), and
there's no evidence in this repo of an unusually long token TTL that would make it acutely dangerous. Flagging
because there's no written spec here confirming the intended TTL or revocation story for *this* platform
specifically — worth a one-line confirmation from whoever owns the shared auth layer rather than treating
it as a defect to fix unilaterally.

**Status:** ⏳ open — recommend confirming intended token TTL, not necessarily a code fix.

---

### F9 — P1 · `[BUILT WRONG]` · NameError: uninitialized constant AudioWebsocketMiddleware on eager loading
**Impact:** Rails application boot fails under production/CI mode when `config.eager_load` is enabled. The application cannot boot because Zeitwerk expects the file name `audio_websocket_middleware.rb` to define `AudioWebsocketMiddleware` (lowercase `s`), but the file actually defines `AudioWebSocketMiddleware` (uppercase `S`).

**Where:** `api/app/channels/audio_websocket_middleware.rb`, `api/app/channels/coverage_websocket_middleware.rb`, `api/config/initializers/websocket.rb`

**Evidence:**
- Running `Rails.application.eager_load!` throws `NameError: uninitialized constant AudioWebsocketMiddleware`.
- This also applies to `CoverageWebSocketMiddleware` once the audio one is resolved.

**Fix:** Created `api/config/initializers/inflections.rb` registering `WebSocket` as an acronym:
```ruby
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym 'WebSocket'
end
```
This correctly allows the camel-cased `AudioWebSocketMiddleware` and `CoverageWebSocketMiddleware` names to match their snake-cased file names (`audio_websocket_middleware.rb`, `coverage_websocket_middleware.rb`) for Zeitwerk, and allows eager loading to complete successfully.

**Status:** ✅ Resolved — inflections added, tests run with `CI=true` (which triggers eager loading) pass successfully.

---

## Systemic pattern (what ties these findings together)

Three related root causes recur across F1–F7:

1. **Destructive or gating operations are implemented independently in multiple places with no shared
   contract and no test enforcing it.** The portfolio generator "knows" regeneration should be idempotent
   but doesn't defend the data that makes it not-actually-idempotent (F1). The coverage state engine
   "knows" a probe threshold but a different part of the prompt layer assumes a different one (F3). The
   hardware checklist treats an unrelated-to-hardware network check as a hard prerequisite for checks that
   have nothing to do with it (F5).
2. **Environment/config wiring is never verified end-to-end.** The candidate-facing invite link is built
   from the API's own base URL instead of the web app's (F4) — a config value that *looks* correct in
   isolation but is silently wrong the moment a real candidate clicks it.
3. **Safety guarantees are asserted in a comment but only actually enforced in one of several execution
   contexts.** `TenantScoped` claims automatic tenant isolation, but that guarantee is middleware-based and
   silently absent for every background worker (F6) — the same shape of gap as F1 and F3: the code *says*
   one thing is guaranteed, and only a trace of every call site reveals it isn't, everywhere, all the time.

Nothing in the codebase or CI would have caught any of these before a human found them — by reading code
line-by-line (F1, F3, F6, F7) or by actually clicking through the app as a candidate would (F4, F5). This
is exactly the ghost-spec rot the case study brief describes — the fix is not one patch, it's the
workflow gate in `02-quality-system.md`.

## Ship / do-not-ship line

**Do not ship.** F4 alone is disqualifying on its own: it breaks the single entry point candidates use to
reach an interview, full stop. F1 is a silent, unrecoverable data-loss path touching a human judgment call
a real hiring decision may depend on. F2 means there is currently no safety net for *any* future change to
this codebase. F5 will silently lose real candidates with perfectly good hardware whenever their network
is merely constrained rather than broken. F6 means the platform's multi-tenant isolation promise — likely
a hard requirement for a B2B client-delivery product — does not actually hold outside HTTP requests, and
needs live verification before anyone can honestly claim tenant data is safe. F3 and F7 should be
escalated to product/platform owners for a real answer before deciding further, not fixed by guessing.

## Findings log (fill as you go)

| ID | Severity | Type | Title | Status |
|---|---|---|---|---|
| F1 | P1 | Built wrong | Overrides destroyed on regeneration | Resolved |
| F2 | P1 | Missing spec | Zero test coverage | Open |
| F3 | P1 | Missing spec / built wrong | Coverage state threshold mismatch | Open |
| F4 | P0 | Built wrong | Invite link points at API port, not web app | Resolved |
| F5 | P1 (conditional) | Built wrong / missing spec | Hardware check: persistent slow network permanently blocks start; no timeout; third-party false negatives | Resolved |
| F6 | P1 | Built wrong | Tenant scoping unenforced inside Sidekiq workers | Open |
| F7 | P2 | Missing spec | JWT trusted without DB lookup / no revocation path | Open |
| F9 | P1 | Built wrong | NameError: uninitialized constant AudioWebsocketMiddleware | Resolved |

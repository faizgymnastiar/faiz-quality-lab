# Release Decision — v1.0.0

**Release Status:** 🛑 **BLOCKED**

This release contains critical stability, usability, and correctness improvements (resolving F1, F4, F5, and F9) that have been successfully verified. However, under the **"honesty-over-green"** principle, this release is officially marked as **BLOCKED** for production deployment due to a critical unresolved data security risk (**F6 — Tenant isolation unenforced in background workers**).

---

## 1. What the Gate Checked & Found

The Release Gate CI pipeline ran the automated test and validation suites for this release tag:

| Component / Check | What was Checked | Status | Finding |
|---|---|---|---|
| **Backend Test Suite** | RSpec unit/integration tests (`api/spec/`) | ✅ **PASSED** | Verification of model, service, and inflection behaviors. |
| **F1 Regression Net** | Override survival on regeneration | ✅ **PASSED** | Overrides are preserved via `find_or_initialize_by`. |
| **F4 Regression Net** | Invite link base URL correction | ✅ **PASSED** | Links point to frontend origin via `WEB_BASE_URL`. |
| **F9 Validation** | Rails Eager Loading (`config.eager_load`) | ✅ **PASSED** | App boots successfully in production mode; inflection registered. |
| **Frontend Test Suite** | Vitest unit tests (`web/src/**/*.test.ts`) | ✅ **PASSED** | Verification of frontend helper and hook behaviors. |
| **F5 Regression Net** | Speed check parallel execution & timeout | ✅ **PASSED** | Network hang simulated; checks complete without freezing the UI. |
| **Frontend Build** | Production bundling (`npm run build`) | ✅ **PASSED** | App compiles successfully with no TypeScript or build-time errors. |
| **Linter Check** | Code quality checks (`npm run lint`) | ✅ **PASSED** | No compiler or code formatting errors in newly authored code. |

---

## 2. Unresolved Risks & Blockers

Although the automated test suite is green, the overall codebase still carries high-severity findings that prevent a safe production launch:

### 🚨 Major Blocker: F6 — Tenant scoping unenforced in Sidekiq workers (Severity: P1)
*   **Risk:** `TenantScoped` multi-tenant boundaries are only applied via Rack/HTTP middleware in controllers. Any database queries or record updates triggered from background workers (Sidekiq) do not inherit this tenant scope and run globally against the database.
*   **Impact:** Potential cross-tenant data leak or unintended data cross-contamination during background processing.
*   **Recommendation:** Block production shipment until a tenant scoping middleware is implemented and verified for Sidekiq.

### ⚠️ Minor Risk: F3 — Coverage state threshold mismatch (Severity: P1/P2)
*   **Risk:** The coverage check state machine uses arbitrary thresholds that do not match current expectations.
*   **Impact:** Non-critical state machine path mismatch. Escalation to the Product Owner is required to define the correct specification.

---

## 3. Recommendation & Risk Acceptance

### Recommendation
*   **Deploy to Staging/UAT:** **Approved.** Safe to deploy to non-production environments to verify the hardware check UI and manual override behaviors.
*   **Deploy to Production:** **Blocked** until **F6** is resolved.

### Risk Acceptance for Exceptional Production Release
If business urgency mandates immediate production deployment of this version, the following conditions must be met:

1.  **Risk Owner:** `[Insert VP of Engineering or Platform Owner Name]`
2.  **Explicit Acknowledgment:** The owner accepts full responsibility for the risk of cross-tenant data leakage in background jobs.
3.  **Temporary Mitigation:** Ensure no asynchronous tasks (e.g. Sidekiq queues) that query tenant-sensitive records are enabled or run in production until F6 is patched.

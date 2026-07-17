# Release Notes — v1.0.0

This release stabilizes the AI Interview Platform by resolving critical architectural blockers, correcting long-standing functional regressions, and establishing a robust CI/CD quality gate to prevent future regressions.

## Key Deliverables

### 1. Assessor Override Preservation (F1)
- **Problem:** When a candidate's portfolio was regenerated, any manual skill level override entered by an assessor (`AssessorOverride`) was silently deleted due to a cascading `dependent: :destroy` configuration triggered by `destroy_all`.
- **Fix:** Refactored `Portfolios::Generator#save_skills` to use `find_or_initialize_by` instead of purging all records, preserving primary keys and keeping manual overrides intact.
- **Verification:** Unit and integration tests added in `spec/services/portfolios/generator_spec.rb`.

### 2. Validated Candidate Invite Routing (F4)
- **Problem:** Candidate invite links pointed to the Rails API port (`http://localhost:3001`) rather than the Web application frontend port (`http://localhost:5173`), rendering them broken for incoming candidates.
- **Fix:** Corrected `Session#invite_url` to respect `WEB_BASE_URL` with a sensible default of `http://localhost:5173`.
- **Verification:** Regression test suite added in `spec/models/session_spec.rb`.

### 3. Parallel & Resilient Hardware Checks (F5)
- **Problem:** The candidate hardware check was sequential. A slow internet speed test would block microphone and audio checks indefinitely, and network hangs could freeze the UI.
- **Fix:** Refactored `HardwareCheck.tsx` to run checks independently and in parallel. Implemented robust timeout boundaries and conservative fallback values to avoid blocking candidates due to transient or moderate network speeds.
- **Verification:** Added Vitest unit test coverage in `web/src/utils/internetSpeedTest.test.ts`.

### 4. Zeitwerk Eager Load Boot Stability (F9)
- **Problem:** The application crashed under Rails eager-loading with a `NameError: uninitialized constant AudioWebsocketMiddleware`.
- **Fix:** Registered `WebSocket` as an acronym inflection in `config/initializers/inflections.rb` to correctly map file paths and class names.
- **Verification:** Validated eager loading boot success in CI and RSpec.

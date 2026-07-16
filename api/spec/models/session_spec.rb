require "rails_helper"

# Regression net for audit finding F4 (P0, BUILT WRONG):
# "Candidate invite link points at the API, not the web app."
#
# Root cause (see /assessment/01-audit.md#F4):
#   - Session#invite_url builds the link from
#       ENV.fetch('APP_BASE_URL', 'http://localhost:3001')
#     where 3001 is the API's own port.
#   - The /interview/:token route only exists in the frontend router
#     (web/src/App.tsx), never in api/config/routes.rb.
#   - Every invite link generated today is a dead link for a real candidate.
#
# This is the single most severe finding in the audit (P0: breaks the only
# entry point candidates have into an interview), so it gets its own explicit
# regression test rather than relying on a generic smoke test to catch it.
#
# Fix direction (not applied by this spec): introduce a dedicated
# WEB_BASE_URL env var, distinct from APP_BASE_URL, and point invite_url at
# it. This spec is written against that intended contract and will fail
# until the fix lands.
RSpec.describe Session, type: :model do
  describe "#invite_url" do
    around do |example|
      original_web_base = ENV["WEB_BASE_URL"]
      ENV["WEB_BASE_URL"] = "https://interview.example.com"
      example.run
      ENV["WEB_BASE_URL"] = original_web_base
    end

    it "points at the web app's interview route, never at the API's own port" do
      session = create(:session, token: "abc123token")

      url = session.invite_url

      expect(url).to start_with("https://interview.example.com")
      expect(url).to include("/interview/abc123token")

      # Guard against the exact regression found in the audit: the API's
      # own default port must never leak into a candidate-facing link.
      expect(url).not_to include(":3001")
    end
  end
end

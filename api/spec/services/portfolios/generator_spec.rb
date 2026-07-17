require "rails_helper"

# Regression net for audit finding F1 (P1, BUILT WRONG):
# "Assessor overrides are silently destroyed on portfolio regeneration."
#
# This spec asserts the invariant that does NOT currently hold:
# "an assessor override survives regeneration of the portfolio it belongs to."
# It is expected to FAIL against the current implementation. It should not be
# made to pass by deleting or weakening this assertion -- only by fixing
# Portfolios::Generator to preserve overrides across regeneration.
RSpec.describe Portfolios::Generator do
  describe "#save_skills / regeneration" do
    it "preserves an assessor's manual override across portfolio regeneration" do
      portfolio = create(:portfolio, generation_status: "complete")
      portfolio_skill = create(
        :portfolio_skill,
        portfolio: portfolio,
        skill_id: "sk-ruby-001",
        skill_label: "Ruby on Rails"
      )

      override = create(
        :assessor_override,
        portfolio_skill: portfolio_skill,
        ai_level: 3,
        override_level: 4
      )

      # Simulate the regeneration path that today calls destroy_all + recreate.
      described_class.new(session: portfolio.session).send(
        :save_skills,
        portfolio,
        {
          "configured_skills" => [
            {
              "skill_id" => "sk-ruby-001",
              "skill_label" => "Ruby on Rails",
              "level" => 2,
              "confidence" => "medium",
              "evidence" => ["quote 1"],
              "competency_summary" => "summary"
            }
          ]
        }
      )

      portfolio.reload
      regenerated_skill = portfolio.portfolio_skills.find_by(skill_id: "sk-ruby-001")

      expect(regenerated_skill).not_to be_nil
      expect(AssessorOverride.exists?(override.id))
        .to eq(true), "assessor override #{override.id} was destroyed by regeneration " \
                       "(F1) -- portfolio_skill_id changed under it with no migration path"
      expect(regenerated_skill.assessor_override&.override_level).to eq(4)
    end
  end
end


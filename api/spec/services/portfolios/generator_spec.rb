require "rails_helper"

# Regression net for audit finding F1 (P1, BUILT WRONG):
# "Assessor overrides are silently destroyed on portfolio regeneration."
#
# Root cause (see /assessment/01-audit.md#F1):
#   - PortfolioSkill has_one :assessor_override, dependent: :destroy
#   - Portfolios::Generator#save_skills does
#       portfolio.portfolio_skills.destroy_all
#     then recreates every skill row with a NEW primary key.
#   - Any assessor_override FK'd to the old portfolio_skill_id cascades to
#     deletion. The regenerated skill has no override at all, and nothing
#     errors -- the fit/gap report silently reverts to the AI's original
#     (already-corrected-by-a-human) judgment.
#
# This spec asserts the invariant that does NOT currently hold:
# "an assessor override survives regeneration of the portfolio it belongs to."
# It is expected to FAIL against the current implementation. It should not be
# made to pass by deleting or weakening this assertion -- only by fixing
# Portfolios::Generator to preserve overrides across regeneration (e.g. by
# matching on skill_id instead of destroy_all + recreate, or by re-attaching
# surviving overrides after regeneration).
#
# NOTE: factory names/attributes below (portfolio, portfolio_skill,
# assessor_override, skill) are inferred from the model/association names
# quoted in the audit and the schema. Adjust field names to match the actual
# factories/schema before running -- the assertions are the part that matters.
RSpec.describe Portfolios::Generator do
  describe "#save_skills / regeneration" do
    it "preserves an assessor's manual override across portfolio regeneration" do
      portfolio = create(:portfolio, status: :complete)
      skill = create(:skill, name: "Ruby on Rails")
      portfolio_skill = create(:portfolio_skill, portfolio: portfolio, skill: skill)

      override = create(
        :assessor_override,
        portfolio_skill: portfolio_skill,
        overridden_level: "advanced",
      )

      # Simulate the regeneration path that today calls destroy_all + recreate.
      described_class.new(portfolio: portfolio).save_skills(
        [{ skill_id: skill.id, level: "intermediate", confidence: "high" }],
      )

      portfolio.reload
      regenerated_skill = portfolio.portfolio_skills.find_by(skill_id: skill.id)

      expect(regenerated_skill).not_to be_nil
      expect(AssessorOverride.exists?(override.id))
        .to eq(true), "assessor override #{override.id} was destroyed by regeneration " \
                       "(F1) -- portfolio_skill_id changed under it with no migration path"
      expect(regenerated_skill.assessor_override&.overridden_level).to eq("advanced")
    end
  end
end

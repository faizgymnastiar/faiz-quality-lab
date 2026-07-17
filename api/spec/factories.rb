# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    name { "Test Tenant Organization" }
    sequence(:scheme) { |n| "http-#{n}" }
    sequence(:identifier) { |n| "tenant-#{n}" }
    sequence(:host) { |n| "tenant-#{n}.example.com" }
  end

  factory :assessment do
    sequence(:name) { |n| "Assessment #{n}" }
    time_limit_min { 45 }
    language { "en" }
    created_by { 1 }

    before(:create) do |assessment|
      org = Organization.first || create(:organization)
      Current.tenant_id = org.id
      assessment.tenant_id = org.id
    end
  end

  factory :session do
    association :assessment
    status { "pending" }
    sequence(:invite_token) { |n| "token-#{n}-#{SecureRandom.hex(8)}" }

    before(:create) do |session|
      Current.tenant_id = session.assessment.tenant_id
      session.tenant_id = session.assessment.tenant_id
    end
  end

  factory :portfolio do
    association :session
    generation_status { "complete" }
  end

  factory :portfolio_skill do
    association :portfolio
    sequence(:skill_id) { |n| "sk-#{n}" }
    skill_label { "React / Frontend" }
    ai_level { 3 }
    ai_confidence { "medium" }
    competency_summary { "Demonstrates good understanding." }
  end

  factory :assessor_override do
    association :portfolio_skill
    ai_level { 3 }
    override_level { 4 }
    overridden_by { 1 }
  end
end

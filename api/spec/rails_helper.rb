ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../config/environment", __dir__)
require "rspec/rails"
require "spec_helper"

# Adjust this if the app uses a different migration-check pattern.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_path = Rails.root.join("spec/fixtures")
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # TenantScoped models require Current.tenant_id / RequestStore to be set
  # before queries run (see api/app/models/concerns/tenant_scoped.rb).
  # Without this, every spec touching a tenant-scoped model would silently
  # hit the model's own `else all` fallback branch -- which is exactly the
  # gap F6 in the audit flags. Specs must set tenant context explicitly so
  # a regression in tenant scoping shows up as a *failing* spec, not as a
  # spec that never noticed it was unscoped.
  config.before(:each) do
    RequestStore.store[:tenant_id] = nil
  end
end

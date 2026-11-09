ENV["RAILS_ENV"] ||= "test"
ENV["JWT_ACCESS_SECRET"] = "test-access-secret"
ENV["STORAGE_DRIVER"] = "local"
ENV["LOCAL_STORAGE_DIR"] = "tmp/test-storage"
require_relative "../config/environment"

# Before rails/test_help, which can reload the schema. A DATABASE_URL in the shell overrides
# database.yml, so this stops a test run from resetting the database shared with the Node API.
SharedDbGuard.assert_safe!(ActiveRecord::Base.connection_db_config.database)

require "rails/test_help"

module ActiveSupport
  class TestCase
    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

require "test_helper"
require "rake"

class SharedDbGuardTest < ActiveSupport::TestCase
  test "accepts a test database" do
    assert_nothing_raised { SharedDbGuard.assert_safe!("coacha_rails_test") }
  end

  test "refuses the shared database" do
    assert_raises(SharedDbGuard::Unsafe) { SharedDbGuard.assert_safe!("coacha") }
  end

  test "refuses a name that only contains _test" do
    assert_raises(SharedDbGuard::Unsafe) { SharedDbGuard.assert_safe!("coacha_test_copy") }
  end

  test "refuses a missing name" do
    assert_raises(SharedDbGuard::Unsafe) { SharedDbGuard.assert_safe!(nil) }
  end

  test "every resetting rake task runs the guard first" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:schema:load")

    %w[db:drop db:purge db:reset db:setup db:prepare db:schema:load db:migrate:reset db:truncate_all db:seed:replant].each do |name|
      assert_includes guarded_tasks(name), "shared_db_guard", "#{name} is not guarded"
    end
  end

  test "rake tasks that touch every environment's database are always refused" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:schema:load")

    %w[db:drop:all db:purge:all].each do |name|
      assert_includes guarded_tasks(name), "shared_db_guard:refuse", "#{name} is not refused"
    end
  end

  private

  # A task's prerequisites, followed through the tasks they name.
  def guarded_tasks(name, seen = [])
    return seen if seen.include?(name)
    seen << name
    Rake::Task[name].prerequisite_tasks.each { |task| guarded_tasks(task.name, seen) }
    seen
  end
end

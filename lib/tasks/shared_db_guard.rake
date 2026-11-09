# Stops Rails' database tasks from resetting the database shared with the Node API, or adding
# Rails' own tables to it: db:migrate creates them even with no migrations to run.
# See SharedDbGuard.

desc "Abort unless the current database is safe to reset"
task shared_db_guard: :environment do
  SharedDbGuard.assert_safe!(ActiveRecord::Base.connection_db_config.database)
end

namespace :shared_db_guard do
  desc "Abort: this task would reach the shared database from any environment"
  task :refuse do
    abort "Refusing to run: this task resets every environment's database, including the one shared with the Node API."
  end
end

%w[
  db:drop db:purge db:reset db:setup db:prepare db:schema:load db:migrate:reset
  db:truncate_all db:seed:replant db:test:purge db:drop:_unsafe
  db:migrate db:migrate:up db:migrate:down db:migrate:redo db:rollback db:forward db:environment:set
].each { |name| Rake::Task[name].enhance([ "shared_db_guard" ]) }

%w[db:drop:all db:purge:all].each { |name| Rake::Task[name].enhance([ "shared_db_guard:refuse" ]) }

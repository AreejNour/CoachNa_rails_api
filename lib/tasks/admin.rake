namespace :admin do
  desc "Create an admin from ADMIN_EMAIL / ADMIN_PASSWORD (ADMIN_NAME optional)"
  task create: :environment do
    admin = AdminUser.create_from_env!
    puts "Created admin #{admin.email}"
  rescue StandardError => e
    abort e.message
  end
end

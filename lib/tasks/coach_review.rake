# Approve or reject a coach in development, until the admin panel exists:
#   bin/rails coach_review:approve PHONE=+201001234567 COMMISSION=15
#   bin/rails coach_review:reject PHONE=+201001234567 REASON="Your certificate photo is too blurry."
namespace :coach_review do
  desc "Approve a coach waiting for review (development only)"
  task approve: :environment do
    run_review { DevCoachReview.approve!(phone: ENV["PHONE"], commission: ENV.fetch("COMMISSION", "15")) }
  end

  desc "Reject a coach waiting for review, with a reason they will read (development only)"
  task reject: :environment do
    run_review { DevCoachReview.reject!(phone: ENV["PHONE"], reason: ENV["REASON"]) }
  end

  def run_review
    coach = yield
    puts "#{coach.full_name} is now #{coach.status}."
  rescue DevCoachReview::Refused => error
    abort error.message
  end
end

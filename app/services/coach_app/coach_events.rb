module CoachApp
  # Queue messages (push and email) for a coach's application events. Call inside the
  # transaction that makes the change: the rows commit with it and publish after the commit.
  module CoachEvents
    PUSH = {
      approved: {
        title: { "ar" => "تمت الموافقة على حسابك", "en" => "You're approved" },
        body: { "ar" => "يمكنك الآن البدء في استقبال العملاء.", "en" => "You can now start taking clients." },
        screen: "coach_home"
      },
      needs_changes: {
        title: { "ar" => "طلبك يحتاج إلى تعديلات", "en" => "Your application needs changes" },
        body: { "ar" => "افتح التطبيق لمعرفة التعديلات المطلوبة.", "en" => "Open the app to see what to change." },
        screen: "coach_needs_changes"
      }
    }.freeze

    def self.push_coach!(coach, event)
      spec = PUSH.fetch(event)
      Outbox.enqueue_and_publish_after_commit!(
        kind: "push",
        payload: { recipient: { type: "coach", id: coach.id }, title: spec[:title], body: spec[:body],
                   data: { screen: spec[:screen] } }
      )
    end

    # Skipped, with a log line naming only the coach id, when the coach has no email.
    def self.email_coach!(coach, template, reason: nil)
      if coach.email.blank?
        Rails.logger.info("[coach_events] no email for coach #{coach.id}; skipped #{template}")
        return nil
      end

      data = { firstName: coach.full_name.to_s.split.first }
      data[:reason] = reason if reason
      Outbox.enqueue_and_publish_after_commit!(kind: "email", payload: { to: coach.email, template: template, data: data })
    end
  end
end

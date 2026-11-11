module CoachApp
  class NotificationsController < BaseController
    def unread_count
      render_success({ count: Notifications.unread_count(current_coach) })
    end
  end
end

module AdminHelper
  # Maps a domain status string to a pill colour used across the admin views.
  PILL_KINDS = {
    # coach statuses
    "pending_review" => "warn", "changes_requested" => "warn",
    "approved" => "ok", "suspended" => "danger", "deactivated" => "muted",
    # review / subscription / payment statuses
    "pending" => "warn", "pending_payment" => "warn", "trialing" => "warn",
    "awaiting_questionnaire" => "warn", "awaiting_plan" => "warn",
    "active" => "ok", "paid" => "ok",
    "rejected" => "danger", "past_due" => "danger", "failed" => "danger",
    "payment_failed" => "danger",
    "canceled" => "muted", "cancelled" => "muted", "ended" => "muted",
    "expired" => "muted", "refunded" => "muted"
  }.freeze

  # Renders a coloured status badge, e.g. <%= status_pill(coach.status) %>.
  def status_pill(status)
    return "—".html_safe if status.blank?
    kind = PILL_KINDS[status.to_s] || "muted"
    content_tag(:span, status.to_s.humanize, class: "pill #{kind}")
  end

  # Whole years from a date of birth to today; nil when no DOB is on file.
  def age_from(date_of_birth)
    return nil if date_of_birth.blank?

    today = Date.current
    age = today.year - date_of_birth.year
    age -= 1 if today < date_of_birth + age.years
    age
  end

  # Marks the sidebar link for `section` active when it matches the current controller.
  def admin_nav_active?(section)
    controller_name == section.to_s
  end
end

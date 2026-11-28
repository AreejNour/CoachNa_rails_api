module AdminHelper
  # Maps a domain status string to a pill colour used across the admin views.
  PILL_KINDS = {
    # coach statuses
    "pending_review" => "warn", "changes_requested" => "warn",
    "approved" => "ok", "suspended" => "danger", "deactivated" => "muted",
    # review / subscription / payment statuses
    "pending" => "warn", "pending_payment" => "warn", "trialing" => "warn",
    "awaiting_questionnaire" => "warn", "awaiting_plan" => "warn", "checkout_open" => "muted",
    "active" => "ok", "paid" => "ok",
    "rejected" => "danger", "past_due" => "danger", "failed" => "danger",
    "payment_failed" => "danger",
    "canceled" => "muted", "cancelled" => "muted", "ended" => "muted",
    "expired" => "muted", "refunded" => "muted"
  }.freeze

  # Statuses whose humanized name would mislead.
  STATUS_LABELS = {
    "checkout_open" => "Card form opened, not paid"
  }.freeze

  # The words shown for a status, e.g. "Pending payment".
  def status_label(status)
    STATUS_LABELS[status.to_s] || status.to_s.humanize
  end

  # Renders a coloured status badge, e.g. <%= status_pill(coach.status) %>.
  def status_pill(status)
    return "—".html_safe if status.blank?
    kind = PILL_KINDS[status.to_s] || "muted"
    content_tag(:span, status_label(status), class: "pill #{kind}")
  end

  # Piastres as "EGP 1,234.50"; negative amounts keep their sign.
  def egp(piastres)
    number_to_currency(piastres / 100.0, unit: "EGP ", precision: 2, negative_format: "-%u%n")
  end

  # A promo code's discount, e.g. "30% (max EGP 200.00)" or "EGP 100.00".
  def promo_discount_label(code)
    return egp(code.value) if code.fixed?

    label = "#{code.value}%"
    label += " (max #{egp(code.max_discount_piastres)})" if code.max_discount_piastres
    label
  end

  # "Dec 01, 2026 00:00 – Jan 01, 2027 00:00" in Cairo time, with "now" / "no end" for an open end.
  def promo_dates(code)
    fmt = ->(t) { t&.in_time_zone(PromoCode::TIME_ZONE)&.strftime("%b %d, %Y %H:%M") }
    return "Any time" if code.starts_at.nil? && code.ends_at.nil?

    "#{fmt.(code.starts_at) || 'now'} – #{fmt.(code.ends_at) || 'no end'}"
  end

  # Active / Inactive / Expired badge for a promo code.
  def promo_status_pill(code)
    if !code.active
      content_tag(:span, "Inactive", class: "pill muted")
    elsif code.expired?
      content_tag(:span, "Expired", class: "pill muted")
    else
      content_tag(:span, "Active", class: "pill ok")
    end
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

  # The admin actions available for a coach in its current status, for the shared action menu.
  # Each: { key:, label:, url:, input: nil|:reason|:commission, danger:, confirm: }.
  def coach_actions(coach)
    act = lambda do |key, label, input, danger: false|
      { key: key, label: label, url: send("admin_#{key}_coach_path", coach), input: input, danger: danger, confirm: nil }
    end
    resend = coach.email.present? ? [ act.(:send_password_email, "Send set-password email", nil) ] : []
    case coach.status
    when "pending_review"
      [ act.(:approve, "Approve", :commission), act.(:request_changes, "Request changes", :reason), act.(:reject, "Reject", :reason) ]
    when "approved"
      [ act.(:suspend, "Suspend", :reason), act.(:deactivate, "Deactivate", :reason, danger: true) ] + resend
    when "suspended"
      [ act.(:reactivate, "Reactivate", :reason), act.(:deactivate, "Deactivate", :reason, danger: true) ] + resend
    else
      []
    end
  end

  # The admin actions available for a client in its current status (none take input).
  def client_actions(client)
    act = lambda do |key, label, danger: false, confirm: nil|
      { key: key, label: label, url: send("admin_#{key}_client_path", client), input: nil, danger: danger, confirm: confirm }
    end
    deactivate = act.(:deactivate, "Deactivate", danger: true, confirm: "Deactivate this client? This cannot be undone.")
    case client.status
    when "active" then [ act.(:suspend, "Suspend"), deactivate ]
    when "suspended" then [ act.(:reactivate, "Reactivate"), deactivate ]
    else []
    end
  end
end

# A coach's set-password link is built from this origin; a localhost fallback in production would
# email dead links, so fail at boot instead.
if Rails.env.production? && ENV["COACH_PASSWORD_URL_BASE"].to_s.strip.empty?
  raise "COACH_PASSWORD_URL_BASE must be set in production (the public https origin of this app)"
end

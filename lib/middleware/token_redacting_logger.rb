# Rails' request logger prints the raw path; the set-password token lives in the path, so redact it.
class TokenRedactingLogger < Rails::Rack::Logger
  TOKEN_PATH = %r{/coach-password/[^/?]+}

  private

  def started_request_message(request)
    super.sub(TOKEN_PATH, "/coach-password/[FILTERED]")
  end
end

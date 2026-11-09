# A failure the API reports to the caller, as this HTTP status and message. `extra` adds fields
# to the response, such as what's missing.
class ApiError < StandardError
  attr_reader :status, :extra

  def initialize(status, message, **extra)
    super(message)
    @status = status
    @extra = extra
  end
end

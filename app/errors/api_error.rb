# A failure the API reports to the caller, as this HTTP status and message.
class ApiError < StandardError
  attr_reader :status

  def initialize(status, message)
    super(message)
    @status = status
  end
end

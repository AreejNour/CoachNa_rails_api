class ApplicationController < ActionController::API
  # rescue_from checks the last declared first, so the catch-all stays at the top.
  rescue_from StandardError, with: :render_internal_error
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_json
  rescue_from ApiError, with: :render_api_error

  def route_not_found
    render_failure(:not_found, "not found")
  end

  private

  def render_success(data, status: :ok)
    render json: { success: true, data: data }, status: status
  end

  def render_failure(status, message)
    render json: { success: false, error: message }, status: status
  end

  def render_api_error(error)
    render_failure(error.status, error.message)
  end

  def render_malformed_json
    render_failure(:bad_request, "validation failed")
  end

  def render_internal_error(error)
    Rails.error.report(error, handled: true)
    Rails.logger.error("#{error.class}: #{error.message}\n#{error.backtrace&.first(20)&.join("\n")}")
    render_failure(:internal_server_error, "internal error")
  end
end

# Unreadable request bodies, such as a cut-off upload, fail in the router before any controller
# runs, so its error handling never sees them. This answers in the API's usual format.
class BadRequestEnvelope
  BODY = { success: false, error: "validation failed" }.to_json.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue ActionController::BadRequest
    [ 400, { "content-type" => "application/json; charset=utf-8" }, [ BODY ] ]
  end
end

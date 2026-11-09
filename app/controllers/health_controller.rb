class HealthController < ApplicationController
  def show
    render_success({ status: "ok", service: "coach-rails-api" })
  end
end

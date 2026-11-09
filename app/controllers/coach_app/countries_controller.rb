module CoachApp
  class CountriesController < ApplicationController
    def index
      render_success(PhoneNumber.countries)
    end
  end
end

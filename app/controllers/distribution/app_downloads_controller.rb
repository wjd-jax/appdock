module Distribution
  class AppDownloadsController < ApplicationController
    include Qrcode
    layout 'distribution'
    before_action :load_app

    def show
      releases = AppDownloads.new(@app).available
      @latest = releases.uniq(&:platform)
      @history = releases.first(50)
      render 'distribution/public/app'
    end

    def qrcode
      render qrcode: AppDownloads.new(@app).url, **qrcode_options
    end

    private

    def load_app
      @app = App.find(params[:id])
      allowed = DistributionAccess.trusted_lan? || (current_user && AppPolicy.new(current_user, @app).show?)
      unless allowed && !@app.archived?
        render 'distribution/public/unavailable', status: :not_found
      end
    end
  end
end

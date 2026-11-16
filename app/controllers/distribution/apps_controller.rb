module Distribution
  class AppsController < BaseController
    before_action :verify_authenticity_token, only: :update
    before_action :load_app

    def show
      @environment_filter = history_environment_filter
      releases = Release.where(channel_id: @app.channel_ids)
      @header_releases = releases.order(id: :desc).limit(50)
      @releases = filter_history(releases).order(id: :desc).limit(50)
    end

    def package
      @package_platform = params[:platform]
      @package_bundle_id = params[:bundle_id]
      releases = Release.where(channel_id: @app.channel_ids, bundle_id: @package_bundle_id)
                        .order(id: :desc).select { |release| release.platform == @package_platform }
      raise ActiveRecord::RecordNotFound if releases.empty?

      @package_view = true
      @package_release = releases.first
      @environment_filter = history_environment_filter
      @releases = filter_history(releases).first(50)
      render :show
    end

    def update
      @app.update!(params.require(:app).permit(:name))
      redirect_to distribution_manage_app_path(@app), notice: '应用信息已保存'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to distribution_manage_app_path(@app), alert: e.message
    end

    private

    def history_environment_filter
      value = params[:business_environment]
      TeamRelease::BUSINESS_ENVIRONMENTS.key?(value) ? value : 'all'
    end

    def filter_history(releases)
      return releases if @environment_filter == 'all'

      value = @environment_filter
      releases.is_a?(Array) ? releases.select { |release| release.business_environment == value } : releases.where(business_environment: value)
    end

    def load_app
      @app = App.active.find(params[:id])
      authorize @app, :update?
    end
  end
end

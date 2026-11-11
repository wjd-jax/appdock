module Distribution
  class AppsController < BaseController
    before_action :verify_authenticity_token, only: :update
    before_action :load_app

    def show
      @releases = Release.where(channel_id: @app.channel_ids).order(id: :desc).limit(50)
    end

    def update
      @app.update!(params.require(:app).permit(:name))
      redirect_to distribution_manage_app_path(@app), notice: '应用信息已保存'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to distribution_manage_app_path(@app), alert: e.message
    end

    private

    def load_app
      @app = App.active.find(params[:id])
      authorize @app, :update?
    end
  end
end

module Distribution
  class WorkspaceController < BaseController
    layout 'distribution'
    skip_before_action :authenticate_user!, only: :landing

    def landing
      return redirect_to distribution_workspace_path if user_signed_in? || trusted_lan?
      render :landing
    end

    def index
      @apps = App.active.order(created_at: :desc).select { |app| AppPolicy.new(current_user, app).show? }
      @downloads = @apps.to_h { |app| [app.id, Distribution::AppDownloads.new(app).latest] }
    end
  end
end

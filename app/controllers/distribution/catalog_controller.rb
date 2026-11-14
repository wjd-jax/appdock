module Distribution
  class CatalogController < ApplicationController
    layout 'distribution'
    def index
      @apps = App.active.order(:name)
      @downloads = @apps.to_h { |app| [app.id, AppDownloads.new(app).latest] }
    end
    def icon
      release = Release.find(params[:id])
      return head :not_found unless release.valid_share_token?(params[:share]) && release.icon&.file&.exists?
      send_file release.icon.path, disposition: 'inline'
    end
  end
end

module Distribution
  class NetworkAccessController < BaseController
    before_action :require_lan
    def index
      response.headers['Cache-Control'] = 'no-store'
      @enabled = NetworkAccess.requested?
      @status = NetworkAccess.status
      @live = NetworkAccess.live?
      @apps = App.active.order(:name)
      @public_host = ENV.fetch('APPDOCK_PUBLIC_HOST', 'download.17love.life')
    end
    def update
      NetworkAccess.request!(params[:enabled] == '1')
      redirect_to distribution_network_access_path, notice: '访问设置已提交，实际状态将在下方更新'
    end
    private
    def require_lan
      head :forbidden unless trusted_lan? && !PublicContext.external
    end
  end
end

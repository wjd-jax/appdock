module Distribution
  class NotificationsController < BaseController
    before_action :require_manager
    before_action :private_response

    def index
      @config = LarkNotification.config
      @configured = @config['credentials'].present? && LarkNotification.credentials['url'].present?
      @signed = @configured && LarkNotification.credentials['secret'].present?
      @status = Setting.distribution_lark_status.to_h.stringify_keys
    end

    def update
      LarkNotification.save!(params.permit(:enabled, :webhook_url, :signing_secret, :clear_secret))
      redirect_to distribution_notifications_path, notice: '上传通知配置已保存'
    rescue LarkNotification::InvalidConfig => e
      redirect_to distribution_notifications_path, alert: e.message
    end

    def test
      ok = LarkNotification.deliver
      redirect_to distribution_notifications_path, (ok ? {notice: '测试消息已发送，请在 Lark 群中确认'} : {alert: '测试发送失败，请查看最近发送结果'})
    end

    private

    def require_manager
      head :forbidden unless trusted_lan? || current_user.admin?
    end

    def private_response
      response.headers['Cache-Control'] = 'no-store'
    end
  end
end

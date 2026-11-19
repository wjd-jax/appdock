module Distribution
  class VersionsController < BaseController
    before_action :verify_authenticity_token

    def update
      release = Release.find(params[:id])
      authorize release, :update?
      attrs = params.permit(:distribution_status, :test_notes, :issue_url, :changelog)
      Release.transaction do
        release.lock!
        release.update!(attrs)
        if params[:recommend] == 'true'
          raise ActiveRecord::RecordInvalid, release unless release.file? && release.distribution_status != 'retired' && !release.app.archived?
          release.update!(distribution_status: 'approved')
          release.channel.update!(recommended_release: release)
        end
      end
      destination = if params[:return_to] == 'package'
                      distribution_manage_package_path(release.app, release.platform, release.bundle_id)
                    else
                      distribution_manage_app_path(release.app)
                    end
      redirect_to destination, notice: '版本信息已更新'
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: distribution_workspace_path, alert: e.message
    end

    def destroy
      release = Release.find(params[:id])
      authorize release, :destroy?
      app = release.app
      platform, bundle_id = release.platform, release.bundle_id
      release.destroy!
      remaining = Release.where(channel_id: app.channel_ids, bundle_id: bundle_id).any? { |item| item.platform == platform }
      destination = if params[:return_to] == 'package' && remaining
                      distribution_manage_package_path(app, platform, bundle_id)
                    else
                      distribution_manage_app_path(app)
                    end
      redirect_to destination, flash: { toast: '此历史版本已删除' }, status: :see_other
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_back fallback_location: distribution_workspace_path, alert: e.message, status: :see_other
    end

    def share
      return head :not_found if trusted_lan?
      release = Release.find(params[:id])
      authorize release, :update?
      release.with_lock do
        release.update!(share_version: release.share_version + (params[:rotate] == 'true' ? 1 : 0), share_expires_at: expiry)
      end
      redirect_to distribution_workspace_path(channel: release.channel_id), notice: '分享设置已更新；轮换后的旧链接已失效'
    rescue ArgumentError
      redirect_back fallback_location: distribution_workspace_path, alert: '有效期格式不正确'
    end

    def environment_share
      return head :not_found if trusted_lan?
      scheme = Scheme.find(params[:id])
      authorize scheme, :update?
      scheme.with_lock do
        scheme.update!(share_version: scheme.share_version + (params[:rotate] == 'true' ? 1 : 0), share_expires_at: expiry)
      end
      redirect_to distribution_workspace_path, notice: '固定入口的分享设置已更新'
    rescue ArgumentError
      redirect_back fallback_location: distribution_workspace_path, alert: '有效期格式不正确'
    end

    private

    def expiry
      params[:share_expires_at].present? ? Time.zone.parse(params[:share_expires_at]) : nil
    end
  end
end

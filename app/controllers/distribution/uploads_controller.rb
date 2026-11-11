module Distribution
  class UploadsController < BaseController
    before_action :verify_authenticity_token

    def new
      authorize App.new, :create?
      redirect_to distribution_workspace_path
    end

    def inspect_package
      file = params.require(:file)
      parser = AppInfo.parse(file.path)
      channel = params[:channel_id].present? ? Channel.find(params[:channel_id]) : UploadPackage.automatic_channel(parser)
      if channel
        authorize channel, :update?
      else
        authorize App.new, :create?
      end
      sha = Digest::SHA256.file(file.path).hexdigest
      duplicates = channel ? channel.releases.where.not(distribution_status: 'retired').where(file_sha256: sha).order(id: :desc).select(&:file?) : []
      render json: {name: parser.name, bundle_id: parser.bundle_id, version: (parser.respond_to?(:release_version) ? parser.release_version : nil),
                    platform: parser.platform, size: file.size, sha256: sha,
                    duplicate: duplicates.present?, existing_url: duplicates.first&.release_url}
    rescue AppInfo::UnknownFormatError, ActionController::ParameterMissing => e
      render json: {error: '无法识别安装包，请选择有效的 IPA 或 APK'}, status: :unprocessable_entity
    ensure
      parser&.clear! if parser&.respond_to?(:clear!)
    end

    def create
      result = UploadPackage.new(params, current_user, source: 'web').call
      render json: {id: result.release.id, duplicate: result.duplicate, release_url: result.release.release_url,
                    qrcode_url: result.release.qrcode_url, version: result.release.version,
                    app_url: distribution_app_path(result.release.app), workspace_url: distribution_app_path(result.release.app)}, status: result.duplicate ? :ok : :created
    rescue UploadPackage::InvalidPackage, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      render json: {error: e.message}, status: :unprocessable_entity
    end
  end
end

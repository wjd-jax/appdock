module Distribution
  class UploadsController < BaseController
    before_action :verify_authenticity_token

    def new
      authorize App.new, :create?
      redirect_to distribution_workspace_path
    end

    def inspect_package
      file = params.require(:file)
      business_environment = params[:business_environment] || 'testing'
      unless TeamRelease::BUSINESS_ENVIRONMENTS.key?(business_environment)
        return render json: {error: '包环境只能选择测试环境或正式环境'}, status: :unprocessable_entity
      end
      parser = AppInfo.parse(file.path)
      channel = params[:channel_id].present? ? Channel.find(params[:channel_id]) : UploadPackage.automatic_channel(parser)
      if channel
        authorize channel, :update?
      else
        authorize App.new, :create?
      end
      sha = Digest::SHA256.file(file.path).hexdigest
      duplicates = channel ? channel.releases.where.not(distribution_status: 'retired')
                                    .where(file_sha256: sha, business_environment: business_environment)
                                    .order(id: :desc).select(&:file?) : []
      render json: {name: parser.name, bundle_id: parser.bundle_id, version: (parser.respond_to?(:release_version) ? parser.release_version : nil),
                    platform: parser.platform, size: file.size, sha256: sha,
                    business_environment: business_environment,
                    duplicate: duplicates.present?, existing_url: duplicates.first&.release_url}
    rescue AppInfo::UnknownFormatError, ActionController::ParameterMissing => e
      render json: {error: '无法识别安装包，请选择有效的 IPA 或 APK'}, status: :unprocessable_entity
    ensure
      parser&.clear! if parser&.respond_to?(:clear!)
    end

    def create
      result = UploadPackage.new(params, current_user, source: 'web').call
      downloads = AppDownloads.new(result.release.app)
      render json: {id: result.release.id, duplicate: result.duplicate, release_url: result.release.release_url,
                    qrcode_url: result.release.qrcode_url, version: result.release.version,
                    business_environment: result.release.business_environment,
                    app_url: downloads.path,
                    package_url: downloads.package_path(result.release),
                    package_qrcode_url: downloads.package_qrcode_path(result.release),
                    workspace_url: downloads.path}, status: result.duplicate ? :ok : :created
    rescue UploadPackage::InvalidPackage, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      render json: {error: e.message}, status: :unprocessable_entity
    end
  end
end

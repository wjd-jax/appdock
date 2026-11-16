module Distribution
  class UploadPackage
    class InvalidPackage < StandardError; end
    Result = Struct.new(:release, :duplicate, keyword_init: true)

    def initialize(params, user, source: 'api')
      @params, @user, @source = params, user, source
    end

    def self.device_for(parser)
      platform = parser.platform.to_s
      Channel.device_types.find { |key, value| value.casecmp?(platform) || key.casecmp?(platform) }&.first
    end

    def self.automatic_channel(parser)
      return unless parser.respond_to?(:bundle_id) && parser.bundle_id.present?
      Channel.joins(:releases, scheme: :app).merge(App.active)
             .where(device_type: device_for(parser), releases: {bundle_id: parser.bundle_id})
             .distinct.order(:id).first
    end

    def call
      upload = @params[:file]
      raise InvalidPackage, '请选择安装包' unless upload.respond_to?(:path) && File.file?(upload.path)
      channel = Channel.find_by!(key: @params[:channel_key]) if @params[:channel_key].present?
      Pundit.authorize(@user, channel, :update?) if channel
      raise InvalidPackage, '应用已归档' if channel&.app&.archived?
      business_environment = @params[:business_environment] || 'testing'
      unless TeamRelease::BUSINESS_ENVIRONMENTS.key?(business_environment)
        raise InvalidPackage, '包环境只能选择测试环境或正式环境'
      end
      sha = Digest::SHA256.file(upload.path).hexdigest
      parser = AppInfo.parse(upload.path)
      result = nil
      ActiveRecord::Base.transaction do
        unless channel
          # Serialize automatic target creation: concurrent first uploads must share one app.
          ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtext('team-auto-upload'))")
          channel = self.class.automatic_channel(parser) || create_channel(parser)
          Pundit.authorize(@user, channel, :update?)
        end
        channel.lock!
        existing = channel.releases.where.not(distribution_status: 'retired')
                          .where(file_sha256: sha, business_environment: business_environment)
                          .order(id: :desc).detect(&:file?)
        if existing && @params[:allow_duplicate].to_s != 'true'
          result = Result.new(release: existing, duplicate: true)
        else
          permitted = @params.permit(:file, :changelog, :release_type, :branch, :git_commit, :ci_url, :custom_fields, :release_version, :build_version)
          release = channel.releases.upload_file(permitted, parser: parser, source: @source)
          release.business_environment = business_environment
          Pundit.authorize(@user, release, :create?)
          release.file_sha256 = sha
          release.save!
          result = Result.new(release: release, duplicate: false)
        end
      end
      unless result.duplicate
        Distribution::LarkNotification.enqueue(result.release)
        result.release.channel.perform_web_hook('upload_events', @user.id)
        result.release.perform_teardown_job(@user.id)
      end
      result
    rescue AppInfo::UnknownFormatError
      raise InvalidPackage, '无法识别安装包格式，请上传有效的 IPA 或 APK'
    ensure
      parser&.clear! if result&.duplicate && parser&.respond_to?(:clear!)
    end

    private

    def create_channel(parser)
      device = self.class.device_for(parser)
      raise InvalidPackage, '请上传 iOS 或 Android 安装包' unless %w[ios android].include?(device)
      name = @params[:name].presence || parser.name.presence || parser.bundle_id
      app = App.active.find_or_initialize_by(name: name)
      if app.new_record?
        Pundit.authorize(@user, app, :create?)
        app.save!
        app.create_owner(@user)
      else
        Pundit.authorize(@user, app, :update?)
      end
      scheme = app.schemes.find_or_initialize_by(name: '内部测试')
      Pundit.authorize(@user, scheme, :create?)
      scheme.save! if scheme.new_record?
      channel = scheme.channels.find_or_initialize_by(device_type: device, bundle_id: Regexp.escape(parser.bundle_id.to_s))
      Pundit.authorize(@user, channel, :create?)
      if channel.new_record?
        channel.name = device == 'ios' ? 'iOS' : 'Android'
        channel.save!
      end
      channel
    end
  end
end

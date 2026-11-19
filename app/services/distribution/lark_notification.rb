require 'openssl'
require 'base64'

module Distribution
  class LarkNotification
    class InvalidConfig < StandardError; end

    def self.config
      Setting.distribution_lark.to_h.stringify_keys
    end

    def self.encryptor
      key = Rails.application.key_generator.generate_key('appdock-lark-notifications-v1', 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
    end

    def self.credentials
      value = config['credentials']
      value.present? ? encryptor.decrypt_and_verify(value) : {}
    end

    def self.validate_url!(url)
      uri = URI.parse(url)
      valid = uri.scheme == 'https' && %w[open.larksuite.com open.feishu.cn].include?(uri.host) &&
        uri.port == 443 && !uri.userinfo && !uri.query && !uri.fragment &&
        uri.path.match?(%r{\A/open-apis/bot/v2/hook/[a-zA-Z0-9-]+\z})
      raise InvalidConfig, '请填写 Lark 或飞书官方群机器人 HTTPS Webhook 地址' unless valid
    rescue URI::InvalidURIError
      raise InvalidConfig, 'Webhook 地址格式无效'
    end

    def self.save!(params)
      data = credentials.stringify_keys
      url = params[:webhook_url].to_s.strip
      data['url'] = url if url.present?
      data['secret'] = params[:signing_secret].to_s.strip if params[:signing_secret].present?
      data.delete('secret') if params[:clear_secret] == '1'
      validate_url!(data['url'].to_s) if data['url'].present? || params[:enabled] == '1'
      Setting.distribution_lark = {
        'enabled' => params[:enabled] == '1',
        'credentials' => encryptor.encrypt_and_sign(data)
      }
    end

    def self.enqueue(release)
      LarkUploadNotificationJob.perform_later(release.id) if config['enabled']
    rescue StandardError
      record(false, '通知任务未能入队，请检查后台服务')
    end

    def self.record(ok, message)
      Setting.distribution_lark_status = {'ok' => ok, 'message' => message, 'at' => Time.current.iso8601}
    end

    # Plain text keeps uploaded changelogs from becoming mentions or card markup.
    def self.changelog_preview(release)
      raw = release.text_changelog(default_template: false).to_s
      lines = raw.lines.map { |line| line.strip.sub(/\A(?:(?:[-*•]|\d+[.)])\s+)+/, '') }
                 .reject(&:blank?)
      visible = lines.reject do |line|
        line.match?(/\AMerge (?:branch|pull request|remote-tracking branch)\b/i) ||
          line.match?(/\Adocs(?:\([^)]*\))?!?:\s*/i) || line == '删除文档'
      end.map do |line|
        line.sub(/\A(?:feat|fix|perf|refactor|chore|build|ci|test|style)(?:\([^)]*\))?!?:\s*/i, '')
      end.uniq
      return ['未填写更新说明。', false] if lines.empty?
      return ['本次记录主要为合并或文档维护，详见完整更新记录。', true] if visible.empty?

      shortened = visible.length > 5 || visible.any? { |line| line.length > 100 } || visible.length != lines.length
      summary = visible.first(5).map { |line| "• #{line.truncate(100)}" }.join("\n")
      [summary, shortened]
    end

    def self.message_payload(release = nil)
      if release
        platform = {'ios' => 'iOS', 'android' => 'Android', 'macos' => 'macOS'}
          .fetch(release.channel.device_type.to_s.downcase, release.channel.device_type.to_s.presence || '未知平台')
        title = "#{release.app_name.to_s.truncate(60)} · #{platform} #{release.business_environment_key == 'production' ? '新正式版' : '新测试版'}"
        version = release.release_version.to_s.presence || '未填写'
        build = release.build_version.to_s.presence || '未填写'
        summary, shortened = changelog_preview(release)
        elements = [
          {tag: 'div', text: {tag: 'plain_text', content: "版本：#{version.truncate(80)} ｜ 构建号：#{build.truncate(80)}"}},
          {tag: 'div', text: {tag: 'lark_md', content: '**本次更新**'}},
          {tag: 'div', text: {tag: 'plain_text', content: summary}}
        ]
        if shortened
          elements << {tag: 'note', elements: [{tag: 'plain_text', content: '以上为更新摘要，完整记录请查看版本详情。'}]}
        end
        package_url = release.release_url
        elements << {tag: 'action', actions: [
          {tag: 'button', text: {tag: 'plain_text', content: '下载并安装'}, type: 'primary', url: package_url},
          {tag: 'button', text: {tag: 'plain_text', content: '完整更新记录'}, type: 'default', url: release.release_url},
          {tag: 'button', text: {tag: 'plain_text', content: release.business_environment_key == 'production' ? '最新正式版' : '最新测试版'}, type: 'default', url: Distribution::AppDownloads.new(release.app).package_url(release)}
        ]}
      else
        title = 'AppDock · 上传通知测试'
        elements = [
          {tag: 'div', text: {tag: 'lark_md', content: '**通知连接成功**'}},
          {tag: 'div', text: {tag: 'plain_text', content: '新测试版本上传后，将以卡片展示应用、版本、更新摘要及下载入口。'}}
        ]
      end
      elements << {tag: 'note', elements: [{tag: 'plain_text', content: 'AppDock · 下载与安装请连接公司内网。'}]}
      {msg_type: 'interactive', card: {
        config: {wide_screen_mode: true},
        header: {template: release ? 'blue' : 'green', title: {tag: 'plain_text', content: title}},
        elements: elements
      }}
    end

    def self.deliver(release = nil)
      data = credentials.stringify_keys
      validate_url!(data['url'].to_s)
      payload = message_payload(release)
      if data['secret'].present?
        timestamp = Time.now.to_i.to_s
        payload[:timestamp] = timestamp
        payload[:sign] = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', "#{timestamp}\n#{data['secret']}", ''))
      end
      response = Faraday.post(data['url']) do |request|
        request.headers['Content-Type'] = 'application/json'
        request.body = payload.to_json
        request.options.timeout = 10
        request.options.open_timeout = 5
      end
      body = JSON.parse(response.body) rescue {}
      code = body.key?('code') ? body['code'] : body['StatusCode']
      ok = response.status == 200 && code == 0
      # Never persist provider text: it can echo credentials or message content.
      message = ok ? (release ? "版本 #{release.id} 通知已发送" : '测试消息已发送') : "发送失败（HTTP #{response.status}，业务码 #{code.is_a?(Numeric) ? code : '未知'}），请检查机器人关键词、签名或 IP 限制"
      record(ok, message)
      ok
    rescue InvalidConfig => e
      record(false, e.message)
      false
    rescue StandardError
      record(false, '发送失败，请检查机器人配置及服务器网络')
      false
    end
  end
end

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

    def self.deliver(release = nil)
      data = credentials.stringify_keys
      validate_url!(data['url'].to_s)
      text = if release
        app_url = Rails.application.routes.url_helpers.distribution_app_url(release.channel.app)
        ["AppDock · 新测试版本", "应用：#{release.app_name}",
         "平台：#{release.channel.device_type.upcase}",
         "版本：#{release.release_version} (#{release.build_version})",
         "更新说明：#{release.text_changelog.to_s.first(2000).presence || '未填写'}",
         "下载：#{app_url}", '下载与安装请连接公司内网。'].join("\n")
      else
        'AppDock · 上传通知测试成功。新测试版本上传后将发送应用、版本、更新说明与下载链接。下载与安装请连接公司内网。'
      end
      payload = {msg_type: 'text', content: {text: text}}
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

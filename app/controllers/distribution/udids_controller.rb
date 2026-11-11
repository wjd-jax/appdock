module Distribution
  class UdidsController < BaseController
    include Qrcode
    # iOS Profile Service posts outside the browser session. A short-lived random
    # challenge binds this callback; all ordinary browser actions retain CSRF.
    skip_before_action :verify_authenticity_token, only: :receive
    skip_before_action :authenticate_user!, only: :receive
    before_action :private_response

    def index; end

    def qrcode
      render qrcode: distribution_udid_url, **qrcode_options
    end

    def profile
      challenge = SecureRandom.hex(32)
      Rails.cache.write("appdock:udid:challenge:#{challenge}", true, expires_in: 15.minutes)
      profile = {
        'PayloadContent' => {
          'URL' => distribution_udid_receive_url(token: challenge),
          'Challenge' => challenge, 'DeviceAttributes' => %w[UDID PRODUCT VERSION]
        },
        'PayloadOrganization' => 'AppDock',
        'PayloadDisplayName' => 'AppDock 获取设备 UDID',
        'PayloadDescription' => '仅获取本机 UDID、设备型号和系统版本，用于内部应用测试。不会安装应用或加入设备管理。',
        'PayloadIdentifier' => 'life.17love.appdock.udid',
        'PayloadType' => 'Profile Service', 'PayloadVersion' => 1,
        'PayloadUUID' => SecureRandom.uuid.upcase
      }
      send_data Plist::Emit.dump(profile), type: 'application/x-apple-aspen-config',
                disposition: 'attachment', filename: 'AppDock-UDID.mobileconfig'
    end

    def receive
      token = params[:token].to_s
      return invalid('获取请求已失效，请重新开始。') unless token.match?(/\A[0-9a-f]{64}\z/) && Rails.cache.read("appdock:udid:challenge:#{token}")
      body = request.body.read(131_073)
      return invalid('设备响应过大。') if body.bytesize > 131_072
      signed = OpenSSL::PKCS7.new(body)
      # Check the CMS signature, without treating the supplied certificate as a
      # trusted Apple identity. These attributes are displayed, never authorized.
      return invalid('设备响应无法验证。') unless signed.verify([], OpenSSL::X509::Store.new, nil, OpenSSL::PKCS7::NOVERIFY)
      xml = signed.data.to_s
      return invalid('设备响应格式不正确。') if xml.match?(/<!ENTITY/i)
      attrs = Plist.parse_xml(xml)
      return invalid('设备响应格式不正确。') unless attrs.is_a?(Hash)
      return invalid('获取请求不匹配，请重新开始。') unless ActiveSupport::SecurityUtils.secure_compare(attrs['CHALLENGE'].to_s, token)
      udid = attrs['UDID'].to_s
      return invalid('未收到有效 UDID，请在 iPhone 或 iPad 上重试。') unless udid.match?(/\A(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16})\z/)
      Rails.cache.delete("appdock:udid:challenge:#{token}")
      result = SecureRandom.hex(32)
      Rails.cache.write("appdock:udid:result:#{result}", {udid: udid, product: attrs['PRODUCT'].to_s.first(80), version: attrs['VERSION'].to_s.first(40)}, expires_in: 10.minutes)
      redirect_to distribution_udid_result_url(token: result), status: :moved_permanently
    rescue OpenSSL::OpenSSLError, ArgumentError, TypeError, REXML::ParseException
      invalid('无法读取设备响应，请重新获取。')
    end

    def result
      token = params[:token].to_s
      @device = Rails.cache.read("appdock:udid:result:#{token}") if token.match?(/\A[0-9a-f]{64}\z/)
      return invalid('结果已过期，请重新获取。', :gone) unless @device
    end

    private

    def private_response
      response.headers['Cache-Control'] = 'no-store'
      response.headers['Referrer-Policy'] = 'no-referrer'
    end

    def invalid(message, status = :unprocessable_entity)
      @udid_error = message
      render :index, status: status
    end
  end
end

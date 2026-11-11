require 'action_dispatch/testing/integration'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'zealot_verify'
def check(label)
  raise label unless yield
  puts "PASS #{label}"
end
service = Distribution::LarkNotification
Setting.distribution_lark = {}
Setting.distribution_lark_status = {}
url = 'https://open.larksuite.com/open-apis/bot/v2/hook/isolated-test'
service.save!({webhook_url: url, signing_secret: 'isolated-secret', enabled: '1'})
check('credentials encrypted'){!Setting.distribution_lark.to_json.include?(url) && !Setting.distribution_lark.to_json.include?('isolated-secret')}
check('encrypted round trip'){service.credentials['url'] == url}
service.save!({enabled: '0'})
check('blank retains credentials and disables'){!service.config['enabled'] && service.credentials['secret'] == 'isolated-secret'}
%w[http://open.larksuite.com/open-apis/bot/v2/hook/x https://localhost/open-apis/bot/v2/hook/x https://open.larksuite.com.evil.test/open-apis/bot/v2/hook/x https://open.larksuite.com/open-apis/bot/v2/hook/x?q=x].each do |bad|
  rejected = false
  begin; service.validate_url!(bad); rescue Distribution::LarkNotification::InvalidConfig; rejected = true; end
  check('reject untrusted destination'){rejected}
end
class << Faraday
  attr_accessor :lark_request, :lark_response, :lark_url
  def post(url)
    self.lark_url = url
    self.lark_request = Struct.new(:headers, :body, :options).new({}, nil, Struct.new(:timeout, :open_timeout).new)
    yield lark_request
    lark_response
  end
end
Faraday.lark_response = Struct.new(:status,:body).new(200, '{"code":0}')
check('test send succeeds even when automatic disabled'){service.deliver}
payload=JSON.parse(Faraday.lark_request.body)
expected=Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', "#{payload['timestamp']}\nisolated-secret", ''))
check('Lark signature and payload'){payload['msg_type']=='text' && payload['sign']==expected && payload.dig('content','text').include?('AppDock')}
check('timeouts bounded'){Faraday.lark_request.options.timeout==10}
Faraday.lark_response = Struct.new(:status,:body).new(200, '{"code":19024}')
check('provider rejection fails'){!service.deliver && !Setting.distribution_lark_status['ok']}
Faraday.lark_response = Struct.new(:status,:body).new(503, 'not json')
check('http failure handled'){!service.deliver}
release=Release.first
raise 'Need isolated release fixture' unless release
Faraday.lark_response = Struct.new(:status,:body).new(200, '{"code":0}')
check('actual release message'){service.deliver(release) && JSON.parse(Faraday.lark_request.body).dig('content','text').include?("版本：#{release.release_version}")}
service.save!({enabled:'1'})
LarkUploadNotificationJob.new.perform(release.id)
check('worker uses exact release ID'){Setting.distribution_lark_status['message'].include?(release.id.to_s)}
original_adapter = LarkUploadNotificationJob.queue_adapter
LarkUploadNotificationJob.queue_adapter = :test
service.enqueue(release)
check('upload enqueues release ID'){LarkUploadNotificationJob.queue_adapter.enqueued_jobs.last[:args] == [release.id]}
LarkUploadNotificationJob.queue_adapter.enqueued_jobs.clear
service.save!({enabled:'0'})
service.enqueue(release)
check('disabled does not enqueue'){LarkUploadNotificationJob.queue_adapter.enqueued_jobs.empty?}
LarkUploadNotificationJob.queue_adapter = original_adapter
service.save!({enabled:'0',clear_secret:'1'})
check('secret removal'){service.credentials['secret'].blank?}
s=ActionDispatch::Integration::Session.new(Rails.application);s.host!('apps.example.com');s.https!
s.get('/notifications')
check('configuration page rendered and private'){s.response.status==200 && s.response.headers['Cache-Control'].include?('no-store')}
check('credentials absent from html'){!s.response.body.include?(url) && !s.response.body.include?('isolated-secret')}
s.patch('/notifications',params:{enabled:'1'})
check('CSRF rejects unprotected save'){s.response.status==422}
s.get('/notifications');token=Nokogiri::HTML(s.response.body).at_css('meta[name="csrf-token"]')['content']
s.patch('/notifications',params:{enabled:'1',authenticity_token:token})
check('save via page'){s.response.status==302}
s.get('/notifications');token=Nokogiri::HTML(s.response.body).at_css('meta[name="csrf-token"]')['content']
s.post('/notifications/test',params:{authenticity_token:token})
check('test via page'){s.response.status==302}
s.get('/notifications');check('saved enabled state and test result'){s.response.body.include?('自动通知已开启') && s.response.body.include?('测试消息已发送')}
puts 'All isolated Lark checks passed (HTTP mocked; no external messages)'

require 'action_dispatch/testing/integration'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'
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
check('Lark signature and payload'){payload['msg_type']=='interactive' && payload['sign']==expected && payload.dig('card','header','title','content').include?('AppDock')}
check('timeouts bounded'){Faraday.lark_request.options.timeout==10}
Faraday.lark_response = Struct.new(:status,:body).new(200, '{"code":19024}')
check('provider rejection fails'){!service.deliver && !Setting.distribution_lark_status['ok']}
Faraday.lark_response = Struct.new(:status,:body).new(503, 'not json')
check('http failure handled'){!service.deliver}
release=Release.first
raise 'Need isolated release fixture' unless release
Faraday.lark_response = Struct.new(:status,:body).new(200, '{"code":0}')
check('actual release message'){service.deliver(release) && JSON.parse(Faraday.lark_request.body).dig('card','elements').first.dig('text','content').include?("版本：#{release.release_version}")}
card = service.message_payload(release)[:card]
buttons = card[:elements].find { |element| element[:tag] == 'action' }[:actions]
expected_package_path = "/#{release.app.distribution_slug}/#{release.platform.downcase}/p#{release.channel_id}/#{release.business_environment_key}"
check('notification downloads the exact version and exposes its environment link') do
  buttons[0][:url] == release.release_url && buttons[1][:url] == release.release_url &&
    URI(buttons.fetch(2)[:url]).path == expected_package_path
end
check('AppDock keyword and LAN requirement retained') { card.to_json.include?('AppDock') && card.to_json.include?('公司内网') }
fixture = release.dup
fixture.id = release.id
fixture.changelog = "- fix(lock): 修复冷启动白屏\n- Merge branch 'dev'\n- docs: 更新文档\n- 删除文档\n- fix(lock): 修复冷启动白屏\n- 403或1023 改成 403且1023\n- <at id=all></at> **原始内容**"
summary, shortened = service.changelog_preview(fixture)
check('summary removes noise, prefixes and duplicates') { summary.scan('修复冷启动白屏').length == 1 && !summary.include?('Merge branch') && !summary.include?('文档') && !summary.include?('fix(lock)') && shortened }
check('ambiguous entries retain original meaning') { summary.include?('403或1023 改成 403且1023') }
check('uploaded text is not interpreted as card markdown') { service.message_payload(fixture)[:card][:elements][2][:text][:tag] == 'plain_text' && summary.include?('<at id=all>') }
fixture.changelog = (1..8).map { |i| "#{i} #{'长' * 200}" }.join("\n")
summary, shortened = service.changelog_preview(fixture)
check('long changelog is bounded and marked') { summary.lines.length == 5 && summary.length < 530 && shortened }
fixture.changelog = ''
check('empty changelog has explicit fallback') { service.changelog_preview(fixture) == ['未填写更新说明。', false] }
fixture.changelog = "Merge branch 'main'"
check('maintenance only changelog has fallback') { service.changelog_preview(fixture)[0].include?('合并或文档维护') }
fixture.changelog = [{'message' => 'fix: 修复钱包'}, {'message' => 'feat: 新增兑换'}]
check('structured changelog supported') { service.changelog_preview(fixture)[0] == "• 修复钱包\n• 新增兑换" }
fixture.release_version = nil
fixture.build_version = '0'
check('missing version and zero build remain explicit') { service.message_payload(fixture)[:card][:elements][0][:text][:content] == '版本：未填写 ｜ 构建号：0' }
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
s=ActionDispatch::Integration::Session.new(Rails.application);s.host!("apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}");s.https!
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

service.save!({enabled: '0'}) # Leave the isolated fixture unable to send later.

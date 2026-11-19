require 'action_dispatch/testing/integration'
require 'nokogiri'
raise 'isolated db required' unless ActiveRecord::Base.connection_db_config.database=='appdock_verify'
Rails.application.executor.run!
class EnvLinkSession < ActionDispatch::Integration::Session
  def process(*args, **kwargs)
    super
  ensure
    Rails.application.executor.run!(reset: true)
  end
end
$count=0
def check(label)
  raise "FAILED #{label}" unless yield
  $count+=1; puts "PASS #{label}"
end
Setting.distribution_lark = {'enabled' => false}
s=EnvLinkSession.new(Rails.application);s.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}";s.https!
original_parse = AppInfo.method(:parse)
bundle = "com.verify.environments.p#{SecureRandom.hex(6)}"
build = '1'
AppInfo.define_singleton_method(:parse) do |path|
  parsed = original_parse.call(path)
  parsed.define_singleton_method(:bundle_id) { bundle }
  parsed.define_singleton_method(:build_version) { build }
  parsed
end
def upload_fixture(session, environment)
  file = Rack::Test::UploadedFile.new('/checks/sample.apk', 'application/octet-stream')
  session.post '/api/apps/upload', params: {file: file, name: 'Fixed links verification', business_environment: environment}
  raise "Fixture upload failed: #{session.response.status}" unless session.response.status == 201
  Release.find(JSON.parse(session.response.body).fetch('id'))
end
begin
  alternate = upload_fixture(s, 'testing')
  build = '2'
  a = upload_fixture(s, 'testing')
  b = upload_fixture(s, 'production')
ensure
  AppInfo.define_singleton_method(:parse, original_parse)
end
Distribution::LarkNotification.define_singleton_method(:enqueue) { |*args| raise 'unexpected notify' }
d = Distribution::AppDownloads.new(a.app)
public_host = ENV.fetch('APPDOCK_PUBLIC_HOST', 'download.example.com')
test=d.package_path(a);prod=d.package_path(b);legacy=d.package_path(a,environment:nil)
check('distinct stable paths') {test.end_with?('/testing')&&prod.end_with?('/production')&&legacy=="/#{a.app.distribution_slug}/#{a.platform.downcase}/p#{a.channel_id}"}
def doc(s);Nokogiri::HTML(s.response.body);end
[[test,a,'testing'],[prod,b,'production']].each do |path,r,env|
 s.get path
 check("#{env} install correct despite newer opposite environment") {s.response.status==200&&doc(s).at_css('.primary-install')['href']==r.install_url}
 check("#{env} history isolated") {doc(s).css('.history-row').any?&&doc(s).css('.history-row').all?{|e|e['data-environment-item']==env}}
 check("#{env} copy remains scoped") {doc(s).at_css('.utility-links button[data-copy]')['data-copy']==d.package_url(r)}
 check("#{env} QR image remains scoped") {doc(s).at_css('.download-qr img')['src']==d.package_qrcode_path(r,size:'large')}
 s.get path,params:{business_environment:env=='testing' ? 'production' : 'testing'}
 check("history filter cannot escape #{env}") {doc(s).css('.history-row').all?{|e|e['data-environment-item']==env}&&doc(s).at_css('.primary-install')['href']==r.install_url}
 payload=Distribution::LarkNotification.message_payload(r)[:card]
 actions=payload[:elements].find{|e|e[:tag]=='action'}[:actions]
 check("#{env} notification exact and fixed links") {actions[0][:url]==r.release_url&&actions.last[:url]==d.package_url(r)&&actions.last[:text][:content].include?(env=='testing' ? '测试' : '正式')}
end
s.get legacy
check('legacy still latest across environments') {s.response.status==200&&doc(s).at_css('.primary-install')['href']==b.install_url}
s.get legacy+'/qrcode'
check('legacy QR returns successfully') {s.response.status==200}
# Track actual encoded QR content without transmitting or decoding user data.
$encoded=[]
module TrackEnvQr
 def initialize(data,*args,**kwargs)
   $encoded << data
   super
 end
end
RQRCode::QRCode.prepend(TrackEnvQr)
[[test,a],[prod,b]].each do |path,r|
 s.get path+'/qrcode'
 check("QR encoded scope #{r.business_environment_key}") {s.response.status==200&&$encoded.last==d.package_url(r)}
end
s.get legacy,params:{package_environment:'invalid'}
check('invalid environment rejected') {s.response.status==404}
s.get test+'/nonsense'
check('invalid route rejected') {s.response.status==404}
# Exercise long route using its public helper without changing package identity.
h=Rails.application.routes.url_helpers
long=h.distribution_package_path(a.app,a.platform,a.bundle_id,package_environment:'testing')
s.get long
check('long package route isolated') {s.response.status==200&&doc(s).at_css('.primary-install')['href']==a.install_url}
s.get long+'/qrcode'
check('long QR keeps environment') {s.response.status==200&&$encoded.last==d.package_url(a)}
# A channel with more than one bundle uses the long-link generator.
alternate.update_columns(bundle_id: 'com.verify.other.bundle')
check('mixed bundle channel generates scoped long links') {d.package_path(a).include?('/packages/')&&d.package_path(a).end_with?('/testing')&&d.package_qrcode_path(a).end_with?('/testing/qrcode')}
# Restore identities before further requests.
alternate.update_columns(bundle_id: a.bundle_id)
s.get '/workspace'
check('workspace exposes both fixed links') {s.response.status==200&&s.response.body.include?(test)&&s.response.body.include?(prod)}
s.get h.distribution_manage_package_path(a.app,a.platform,a.bundle_id)
check('management exposes both fixed links') {s.response.status==200&&s.response.body.include?(test)&&s.response.body.include?(prod)}
# No usable testing record must fail closed, even if production is usable.
Release.where(channel_id:a.channel_id,business_environment:'testing').update_all(distribution_status:'retired')
s.get test
check('no testing release never falls back to production') {s.response.status==404}
s.get test+'/qrcode'
check('unavailable testing QR rejected') {s.response.status==404}
s.get prod
check('production unaffected by retired testing') {s.response.status==200&&doc(s).at_css('.primary-install')['href']==b.install_url}
# Exercise external host/context using the existing gate, never a live webhook.
Distribution::NetworkAccess.define_singleton_method(:live?) {true}
s.host! public_host
s.get prod
check('external fixed route permitted') {s.response.status==200&&doc(s).at_css('.primary-install')['href'].include?(public_host)}
check('external copy retains host and environment') {doc(s).at_css('.utility-links button[data-copy]')['data-copy']=="https://#{public_host}#{prod}"}
s.get prod+'/qrcode'
check('external QR retains host and environment') {s.response.status==200&&$encoded.last=="https://#{public_host}#{prod}"}
s.post '/workspace/uploads'
check('external upload still blocked') {[404,503].include?(s.response.status)}
s.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}";a.app.update!(archived:true)
s.get prod
check('archived product remains unavailable') {s.response.status==404}
puts "ENVIRONMENT LINKS VERIFIED #{$count} checks"

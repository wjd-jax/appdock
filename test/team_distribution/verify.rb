# bin/rails runner --skip-executor /checks/verify.rb
require 'action_dispatch/testing/integration'
require 'nokogiri'
require 'json'
raise 'Isolated verification database required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'
Rails.application.executor.run!
class InternalDistributionSession < ActionDispatch::Integration::Session
  def process(*args, **kwargs)
    super
  ensure
    Rails.application.executor.run!(reset: true)
  end
end

def check(label)
  raise "FAILED: #{label}" unless yield
  puts "PASS: #{label}"
end

def post_package(session, path, fields = {}, headers = {})
  boundary = 'Verification' + SecureRandom.hex(10)
  body = +''
  fields.each { |key,value| body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n" }
  body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sample.apk\"\r\nContent-Type: application/octet-stream\r\n\r\n"
  body = body.b + File.binread('/checks/sample.apk') + "\r\n--#{boundary}--\r\n".b
  session.post path, params: body, headers: headers.merge('CONTENT_TYPE'=>"multipart/form-data; boundary=#{boundary}")
end

# These are isolated fixtures only. Re-running starts with an empty visible app list.
App.update_all(archived: true)
Setting.distribution_lark = {'enabled' => false}
check('isolated upload notifications are disabled') { Distribution::LarkNotification.config['enabled'] == false }
s = InternalDistributionSession.new(Rails.application)
acceptance_port = ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')
s.host! "apps.example.com:#{acceptance_port}"
s.https!
s.get '/workspace'
check('empty workspace retains upload without target selection') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('article.fir-app').empty? && Nokogiri::HTML(s.response.body).at_css('input[type=file][name=file]') && !s.response.body.include?('目标渠道') && !s.response.body.include?('应用 / 环境') }
s.get '/upload'
check('upload entry redirects into workspace') { s.response.status==302 && URI(s.response.location).path=='/workspace' }
s.follow_redirect!
check('workspace upload defaults to testing without target or Git inputs') { s.response.status==200 && Nokogiri::HTML(s.response.body).at_css('input[name=business_environment][value=testing][checked]') && Nokogiri::HTML(s.response.body).at_css('input[name=business_environment][value=production]') && Nokogiri::HTML(s.response.body).css('input[name=branch],input[name=git_commit],select[name=channel_id]').empty? }
s.get '/developers'
check('developer setup does not depend on existing apps or channels') { s.response.status==200 && !s.response.body.include?('setup-channel') && !s.response.body.include?('channel_key') }
csrf = Nokogiri::HTML(s.response.body).at_css('meta[name="csrf-token"]')['content']
s.post '/developers/preview', params: {platform: 'android'}, headers: {'X-CSRF-Token'=>csrf, 'ACCEPT'=>'application/json'}
check('config generation works before first app upload') { s.response.status==200 && JSON.parse(JSON.parse(s.response.body)['files']['.team-distribution.json']).keys.sort==%w[artifact build endpoint] }
post_package s, '/api/apps/upload'
check('first API upload without target or token creates app') { s.response.status==201 }
first = JSON.parse(s.response.body)
r = Release.find(first['id'])
app = r.app
check('app identity and default testing environment') { r.bundle_id=='com.piko.launcher' && App.active.count==1 && URI(first['app_url']).host=='apps.example.com' && URI(first['app_url']).port==acceptance_port.to_i && URI(first['app_url']).path=="/#{app.distribution_slug}" && r.file? && r.business_environment=='testing' && first['business_environment']=='testing' }
s.get '/catalog'
check('catalog renders package links for an existing app') { s.response.status==200 && s.response.body.include?(app.name) && s.response.body.include?("/#{app.distribution_slug}/#{r.platform.downcase}/p#{r.channel_id}") }
count = Release.count
duplicate_params = {sha256: r.file_sha256, bundle_id: r.bundle_id, platform: r.platform}
s.post '/workspace/duplicate', params: duplicate_params.merge(business_environment: 'testing'), headers: {'X-CSRF-Token'=>csrf, 'ACCEPT'=>'application/json'}
check('environment switch checks duplicates without uploading again') { s.response.status==200 && JSON.parse(s.response.body)['duplicate'] && Release.count==count }
s.post '/workspace/duplicate', params: duplicate_params.merge(business_environment: 'production'), headers: {'X-CSRF-Token'=>csrf, 'ACCEPT'=>'application/json'}
check('another environment has no duplicate') { s.response.status==200 && !JSON.parse(s.response.body)['duplicate'] && Release.count==count }
s.post '/workspace/duplicate', params: duplicate_params.merge(sha256: 'invalid', business_environment: 'testing'), headers: {'X-CSRF-Token'=>csrf, 'ACCEPT'=>'application/json'}
check('invalid fingerprint rejected') { s.response.status==422 && Release.count==count }
post_package s, '/api/apps/upload', {name: 'Display name changed'}
check('same package is deduplicated into same app even if display name changes') { s.response.status==200 && JSON.parse(s.response.body)['id']==r.id && Release.count==count && App.active.count==1 }
post_package s, '/workspace/inspect', {business_environment: 'production'}, {'X-CSRF-Token'=>csrf}
check('production preview does not reuse testing file') { s.response.status==200 && !JSON.parse(s.response.body)['duplicate'] }
post_package s, '/api/apps/upload', {business_environment: 'production'}
production = Release.find(JSON.parse(s.response.body)['id'])
check('same file in production creates a separate version') { s.response.status==201 && production.id!=r.id && production.business_environment=='production' && Release.count==count+1 }
post_package s, '/api/apps/upload', {business_environment: 'production'}
check('same production file deduplicates within its environment') { s.response.status==200 && JSON.parse(s.response.body)['id']==production.id && Release.count==count+1 }
post_package s, '/api/apps/upload', {business_environment: 'invalid'}
check('invalid environment is rejected') { s.response.status==422 && Release.count==count+1 }
post_package s, '/api/apps/upload', {}, {'Origin'=>'https://untrusted.example'}
check('cross-site API upload rejected') { s.response.status==403 && Release.count==count+1 }
post_package s, '/workspace/uploads'
check('web upload keeps invisible CSRF protection') { s.response.status==422 }
post_package s, '/workspace/inspect', {}, {'X-CSRF-Token'=>csrf}
check('package preview finds duplicates automatically') { s.response.status==200 && JSON.parse(s.response.body)['duplicate'] }
post_package s, '/workspace/inspect', {business_environment: 'production'}, {'X-CSRF-Token'=>csrf}
check('production preview finds production duplicate') { s.response.status==200 && JSON.parse(s.response.body)['duplicate'] && JSON.parse(s.response.body)['business_environment']=='production' }
post_package s, '/workspace/uploads', {allow_duplicate: 'true', changelog: '<script>alert(1)</script> new version'}, {'X-CSRF-Token'=>csrf}
check('web upload without target saves an explicit testing version') { s.response.status==201 && Release.count==count+2 && JSON.parse(s.response.body)['business_environment']=='testing' }
newest = Release.find(JSON.parse(s.response.body)['id'])
check('new release starts with zero downloads') { newest.download_count == 0 }
check('all existing releases have a business environment') { Release.where(business_environment: nil).none? }
s.get first['app_url']
check('fixed app download page shows newest version and environment') { s.response.status==200 && s.response.body.include?(newest.release_url) && s.response.body.include?('测试环境') && !s.response.body.include?('推荐') }
s.get "#{first['app_url']}?business_environment=production"
check('public history filters production') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('.history-row').map { |row| row['data-environment-item'] }==['production'] && !Nokogiri::HTML(s.response.body).css('.history-row').first.text.include?(r.bundle_id) && s.response.body.include?(newest.release_url) }
s.get "#{first['app_url']}?business_environment=testing"
check('testing history includes existing packages') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('.history-row').map { |row| row['data-environment-item'] }==['testing','testing'] && !s.response.body.include?('未标记') }
s.get Rails.application.routes.url_helpers.distribution_manage_package_path(app, r.platform, r.bundle_id, business_environment: 'production')
check('package management history filters production without losing package header') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('.version-event').map { |item| item['data-environment-item'] }==['production'] && !Nokogiri::HTML(s.response.body).css('.version-event').first.text.include?(r.bundle_id) && s.response.body.include?(r.bundle_id) }
s.get "/a/#{app.id}/qrcode"
check('fixed app QR image available') { s.response.status==200 && s.response.media_type.start_with?('image/') }
s.get '/workspace'
check('one app card with environment labels, no old target controls') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('article.fir-app').size==1 && s.response.body.include?('测试环境') && !s.response.body.include?('upload-channel') && !s.response.body.include?('固定环境') }
s.get URI(newest.release_url).request_uri
check('version page contains safe notes and no channel workflow') { s.response.status==200 && s.response.body.include?('&lt;script&gt;') && !s.response.body.include?('管理此渠道') }
newest_status = newest.distribution_status
newest.update_column(:distribution_status, 'retired')
s.get URI(newest.download_url).request_uri
check('retired release cannot increment downloads') { s.response.status==404 && newest.reload.download_count==0 }
newest.update_column(:distribution_status, newest_status)
s.get URI(newest.download_url).request_uri
check('download redirect does not increment downloads') { s.response.status==302 && newest.reload.download_count==0 }
file_path = URI(s.response.location).request_uri
s.follow_redirect!
check('download hash matches original APK and count increments once') { s.response.status==200 && Digest::SHA256.hexdigest(s.response.body)==newest.file_sha256 && newest.reload.download_count==1 }
s.head file_path
check('HEAD request does not increment downloads') { s.response.status==200 && newest.reload.download_count==1 }
s.get file_path
check('repeat file request increments only its release') { s.response.status==200 && newest.reload.download_count==2 && production.reload.download_count==0 }
s.get '/workspace'
check('workspace shows app total and current release count') { s.response.status==200 && s.response.body.include?('累计下载 2 次') && s.response.body.include?('当前版本下载：') && s.response.body.include?('<strong>2</strong> 次') }
s.get Rails.application.routes.url_helpers.distribution_manage_app_path(app)
check('management shows per-release count') { s.response.status==200 && s.response.body.include?('下载 2 次') && s.response.body.include?('下载 0 次') }
newest.update!(distribution_status: 'retired')
s.get first['app_url']
check('retired version skipped by latest app view') { s.response.status==200 && s.response.body.include?(production.release_url) && !s.response.body.include?(newest.release_url) }
app.update!(archived: true)
s.get first['app_url']
check('archived app download unavailable') { s.response.status==404 }
post_package s, '/api/apps/upload'
check('reupload after archival creates a fresh visible app without restoring fixtures') { s.response.status==201 && App.active.count==1 }
active_release = Release.find(JSON.parse(s.response.body)['id'])
check('archive retained and automatic detection stable') { active_release.app.id!=app.id && app.reload.archived? && App.active.first.id==active_release.app.id }
puts({verified: true, active_app_id: active_release.app.id, release_id: active_release.id}.to_json)

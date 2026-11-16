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
s = InternalDistributionSession.new(Rails.application)
s.host! 'apps.example.com:18443'
s.https!
s.get '/workspace'
check('empty workspace retains upload without target selection') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('article.fir-app').empty? && Nokogiri::HTML(s.response.body).at_css('input[type=file][name=file]') && !s.response.body.include?('目标渠道') && !s.response.body.include?('应用 / 环境') }
s.get '/upload'
check('upload entry redirects into workspace') { s.response.status==302 && URI(s.response.location).path=='/workspace' }
s.follow_redirect!
check('workspace upload omits Git metadata and target inputs') { s.response.status==200 && s.response.body.include?('id="upload-form"') && Nokogiri::HTML(s.response.body).css('input[name=branch],input[name=git_commit],select[name=channel_id]').empty? }
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
check('app identity parsed and app link returned') { r.bundle_id=='com.piko.launcher' && App.active.count==1 && first['app_url']=="https://apps.example.com:18443/a/#{app.id}" && r.file? }
count = Release.count
post_package s, '/api/apps/upload', {name: 'Display name changed'}
check('same package is deduplicated into same app even if display name changes') { s.response.status==200 && JSON.parse(s.response.body)['id']==r.id && Release.count==count && App.active.count==1 }
post_package s, '/api/apps/upload', {}, {'Origin'=>'https://untrusted.example'}
check('cross-site API upload rejected') { s.response.status==403 && Release.count==count }
post_package s, '/workspace/uploads'
check('web upload keeps invisible CSRF protection') { s.response.status==422 }
post_package s, '/workspace/inspect', {}, {'X-CSRF-Token'=>csrf}
check('package preview finds duplicates automatically') { s.response.status==200 && JSON.parse(s.response.body)['duplicate'] }
post_package s, '/workspace/uploads', {allow_duplicate: 'true', changelog: '<script>alert(1)</script> new version'}, {'X-CSRF-Token'=>csrf}
check('web upload without target saves an explicit new version') { s.response.status==201 && Release.count==count+1 }
newest = Release.find(JSON.parse(s.response.body)['id'])
s.get first['app_url']
check('fixed app download page immediately shows newest version without recommendation') { s.response.status==200 && s.response.body.include?(newest.release_url) && !s.response.body.include?('推荐') && !s.response.body.include?('环境') }
s.get "/a/#{app.id}/qrcode"
check('fixed app QR image available') { s.response.status==200 && s.response.media_type.start_with?('image/') }
s.get '/workspace'
check('one app card, no target/environment controls') { s.response.status==200 && Nokogiri::HTML(s.response.body).css('article.fir-app').size==1 && !s.response.body.include?('upload-channel') && !s.response.body.include?('固定环境') }
s.get URI(newest.release_url).request_uri
check('version page contains safe notes and no channel workflow') { s.response.status==200 && s.response.body.include?('&lt;script&gt;') && !s.response.body.include?('管理此渠道') }
s.get URI(newest.download_url).request_uri
s.follow_redirect!
check('download hash matches original APK') { s.response.status==200 && Digest::SHA256.hexdigest(s.response.body)==newest.file_sha256 }
newest.update!(distribution_status: 'retired')
s.get first['app_url']
check('retired version skipped by latest app view') { s.response.status==200 && s.response.body.include?(r.release_url) && !s.response.body.include?(newest.release_url) }
app.update!(archived: true)
s.get first['app_url']
check('archived app download unavailable') { s.response.status==404 }
post_package s, '/api/apps/upload'
check('reupload after archival creates a fresh visible app without restoring fixtures') { s.response.status==201 && App.active.count==1 }
active_release = Release.find(JSON.parse(s.response.body)['id'])
check('archive retained and automatic detection stable') { active_release.app.id!=app.id && app.reload.archived? && App.active.first.id==active_release.app.id }
puts({verified: true, active_app_id: active_release.app.id, release_id: active_release.id}.to_json)

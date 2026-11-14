require 'action_dispatch/testing/integration'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'zealot_verify'
def check(label)
  raise label unless yield
  puts "PASS #{label}"
end
service=Distribution::NetworkAccess
service::ROOT.mkpath
service.request!(false)
File.write(service::ROOT.join('status.json'), {state:'disabled',heartbeat:Time.now.to_f}.to_json)
s=ActionDispatch::Integration::Session.new(Rails.application);s.host!('download.17love.life');s.https!
s.get('/')
check('disabled rejects public catalog'){s.response.status==503}
s.get('/distribution/app.css')
check('disabled rejects static assets too'){s.response.status==503}
service.request!(true)
File.write(service::ROOT.join('status.json'), {state:'enabled',heartbeat:Time.now.to_f}.to_json)
app=App.active.first; release=Distribution::AppDownloads.new(app).available.find(&:android?)
raise 'Android fixture required' unless release
['/',"/a/#{app.id}","/a/#{app.id}/qrcode",'/distribution/app.css'].each do |path|
  s.get(path)
  check("public read #{path}"){s.response.status==200 && s.response.headers['Cache-Control'].include?('no-store')}
end
s.get("/public/icons/#{release.id}")
check('icon endpoint validates file existence'){s.response.status == (release.icon&.file&.exists? ? 200 : 404)}
s.get("/a/#{app.id}")
check('all absolute URLs use public hostname'){!s.response.body.include?('apps.17love.life') && s.response.body.include?('https://download.17love.life')}
check('no management navigation on public pages'){!s.response.body.include?('上传通知') && !s.response.body.include?('开发接入')}
url=Distribution::PublicContext.set(external:true){release.release_url}
s.get(URI(url).request_uri)
check('version details reachable'){s.response.status==200}
s.get(URI(Distribution::PublicContext.set(external:true){release.qrcode_url}).request_uri)
check('version QR reachable'){s.response.status==200}
s.get("/channels/#{release.channel.slug}/releases/#{release.id}/install")
check('manifest uses public binary host'){s.response.status==200 && s.response.body.include?('https://download.17love.life/download/releases/') && !s.response.body.include?('apps.17love.life')}

s.get(URI(Distribution::PublicContext.set(external:true){release.download_url}).request_uri)
check('binary redirect stays public'){s.response.status==302 && s.response.location.start_with?('https://download.17love.life/')}
s.follow_redirect!
check('APK bytes downloadable'){s.response.status==200 && s.response.body.bytesize==release.file.size}
check('APK bytes match fixture'){Digest::SHA256.hexdigest(s.response.body)==Digest::SHA256.file(release.file.path).hexdigest}
channel=release.channel; previous_password=channel.password
begin
  channel.update!(password:'isolated-download-password')
  s.get(URI(Distribution::PublicContext.set(external:true){release.download_url}).request_uri)
  check('public honors existing channel password'){s.response.status==302 && s.response.location.include?('/channels/')}
  s.follow_redirect!
  check('password form rendered'){s.response.body.include?('输入下载密码')}
ensure
  channel.update!(password:previous_password)
end
%w[/access /workspace /notifications /developers /udid /users/sign_in /admin /api/apps /graphql /download/debug_files/1 /distribution/team-release.py /uploads/apps/a1/r1/binary/test.apk /backup/test].each do |path|
  s.get(path)
  check("public rejects #{path}"){s.response.status==404}
end
[['POST','/api/apps/upload'],['POST','/workspace/uploads'],['PATCH','/access'],['PATCH',"/workspace/apps/#{app.id}"],['DELETE',"/channels/#{release.channel.slug}/releases/#{release.id}"]].each do |method,path|
  s.public_send(method.downcase,path,params:{enabled:'1'})
  check("public rejects mutation #{method} #{path}"){s.response.status==404}
end
File.write(service::ROOT.join('status.json'), {state:'enabled',heartbeat:Time.now.to_f-30}.to_json)
s.get("/a/#{app.id}")
check('stale controller fails closed'){s.response.status==503}
File.write(service::ROOT.join('status.json'), {state:'enabled',heartbeat:Time.now.to_f}.to_json)
service.request!(false)
s.get("/a/#{app.id}")
check('disable denies immediately despite enabled status'){s.response.status==503}
check('public context cleared'){!Distribution::PublicContext.external}
lan=ActionDispatch::Integration::Session.new(Rails.application);lan.host!('apps.17love.life');lan.https!
lan.get('/access');check('LAN settings reachable'){lan.response.status==200}
lan.patch('/access',params:{enabled:'1'});check('CSRF enforced'){lan.response.status==422 && !service.requested?}
lan.get('/access');token=Nokogiri::HTML(lan.response.body).at_css('meta[name="csrf-token"]')['content']
lan.patch('/access',params:{enabled:'1',authenticity_token:token})
check('LAN switch saves boolean request'){lan.response.status==302 && service.requested?}
lan.get('/workspace');check('LAN upload preserved'){lan.response.status==200 && lan.response.body.include?('type="file"')}
lan.get('/notifications');check('LAN notifications preserved'){lan.response.status==200}
service.request!(false)
puts 'NETWORK ACCESS VERIFIED'

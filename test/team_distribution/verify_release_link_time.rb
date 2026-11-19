require 'action_dispatch/testing/integration'
require 'nokogiri'
raise 'Isolated database required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'
Rails.application.executor.run!
class OverwriteSession < ActionDispatch::Integration::Session
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
Setting.distribution_lark = {'enabled' => false}
Distribution::LarkNotification.define_singleton_method(:enqueue) { |*args| nil }
s = OverwriteSession.new(Rails.application); s.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}"; s.https!
s.get '/workspace'; csrf=Nokogiri::HTML(s.response.body).at_css('meta[name="csrf-token"]')['content']; headers={'X-CSRF-Token'=>csrf}
original=AppInfo.method(:parse)
$build='900'; $bundle="com.verify.overwrite.#{SecureRandom.hex(5)}"
AppInfo.define_singleton_method(:parse) do |path|
  parsed=original.call(path)
  parsed.define_singleton_method(:bundle_id) { $bundle }
  parsed.define_singleton_method(:release_version) { '8.9.0' }
  parsed.define_singleton_method(:build_version) { $build }
  parsed
end
require 'tmpdir'
fixture_directory = Dir.mktmpdir('appdock-overwrite')
at_exit { FileUtils.remove_entry(fixture_directory) }
fixture_path = File.join(fixture_directory, 'sample.apk')
FileUtils.cp('/checks/sample.apk', fixture_path)
define_method(:package_fixture) do
  Rack::Test::UploadedFile.new(fixture_path, 'application/octet-stream')
end
def body(s); JSON.parse(s.response.body); end
s.post '/workspace/uploads', params: {file: package_fixture, name:'Overwrite test', changelog:'old'}, headers:headers
raise "#{s.response.status} #{s.response.body}" unless s.response.status==201
a=Release.find(body(s)['id']); id=a.id; url=a.release_url; hash=a.file_sha256; a.update!(download_count:42)
count=Release.count
s.post '/workspace/inspect', params:{file:package_fixture,business_environment:'testing'}, headers:headers
check('inspect matches parsed version and build') { s.response.status==200 && body(s)['duplicate'] && body(s)['build']=='900' && body(s)['existing_id']==id }
s.post '/workspace/duplicate', params:{sha256:hash,bundle_id:$bundle,platform:'android',version:'8.9.0',build:'900',business_environment:'production'}, headers:headers
check('environment recheck keeps production separate') { s.response.status==200 && !body(s)['duplicate'] }
s.post '/workspace/uploads', params:{file:package_fixture,changelog:'unconfirmed',allow_duplicate:'true'}, headers:headers
check('unconfirmed duplicate and legacy flag cannot overwrite') { s.response.status==409 && body(s)['existing_id']==id && Release.count==count && a.reload.text_changelog.include?('old') }
s.post '/workspace/uploads', params:{file:package_fixture,overwrite:'true',overwrite_release_id:id+1}, headers:headers
check('incorrect confirmation target cannot overwrite') { s.response.status==409 && Release.count==count }
# Different bytes, same parsed versions and same original filename.
File.open(fixture_path,'ab'){|f|f.write("overwrite-test")}
s.post '/workspace/uploads', params:{file:package_fixture,changelog:'replaced',overwrite:'true',overwrite_release_id:id}, headers:headers
raise "#{s.response.status} #{s.response.body}" unless s.response.status==201
check('confirmed overwrite replaces same record and bytes') { body(s)['overwritten'] && body(s)['id']==id && Release.count==count && a.reload.file_sha256!=hash && Digest::SHA256.file(a.file.path).hexdigest==a.file_sha256 && a.text_changelog.include?('replaced') }
check('original link and download count retained') { a.release_url==url && a.download_count==42 && File.file?(a.file.path) }
$build='901'
s.post '/workspace/uploads', params:{file:package_fixture}, headers:headers
check('different build creates a version') { s.response.status==201 && !body(s)['overwritten'] && body(s)['id']!=id }
$build='900'
s.post '/workspace/uploads', params:{file:package_fixture,business_environment:'production'}, headers:headers
check('same version in another environment creates a version') { s.response.status==201 && !body(s)['overwritten'] && body(s)['id']!=id }
s.post '/workspace/uploads', params:{file:package_fixture,overwrite:'true',overwrite_release_id:id}
check('missing CSRF cannot overwrite') { s.response.status==422 }
s.post '/workspace/uploads', params:{file:package_fixture,overwrite:'true',overwrite_release_id:id}, headers:headers.merge('X-Appdock-Public'=>'1')
check('public ingress cannot overwrite') { [404,503].include?(s.response.status) }
puts 'OVERWRITE VERIFIED'

# The oldest record becomes newest when overwritten after a production upload.
previous_time=a.reload.uploaded_at
s.post '/workspace/uploads', params:{file:package_fixture,changelog:'latest testing',overwrite:'true',overwrite_release_id:id}, headers:headers
check('overwrite advances dedicated upload timestamp') { s.response.status==201 && a.reload.uploaded_at > previous_time }
check('latest selection honors overwrite time across environments') { Distribution::AppDownloads.new(a.app).package_releases(a.platform,a.bundle_id).first.id==id }
time=a.uploaded_at
a.update!(changelog:'edited notes',download_count:99)
check('editing notes and download count cannot change upload time') { a.reload.uploaded_at==time }
[ a, a.channel.releases.find_by!(business_environment:'production') ].each do |r|
 card = Distribution::LarkNotification.message_payload(r)[:card]
 actions = card[:elements].find { |element| element[:tag] == 'action' }.fetch(:actions)
 check("notification points to exact version #{r.id}") { actions.first[:url] == r.release_url }
 check("notification uses the matching environment") do
   card.dig(:header, :title, :content).include?(r.business_environment_key == 'production' ? '新正式版' : '新测试版') &&
     actions.last[:url] == Distribution::AppDownloads.new(r.app).package_url(r)
 end
end
s.get Distribution::AppDownloads.new(a.app).package_path(a)
check('package page shows overwritten release as latest') { s.response.status==200 && Nokogiri::HTML(s.response.body).at_css('.primary-install')['href']==a.install_url }
s.get URI(a.release_url).request_uri
check('version page uses upload time') { s.response.status==200 && s.response.body.include?(ApplicationController.helpers.distribution_time(a.uploaded_at)) }
puts 'RELEASE LINK TIME VERIFIED'

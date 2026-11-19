require 'action_dispatch/testing/integration'
require 'json'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'

def check(label)
  raise "FAILED #{label}" unless yield
  puts "PASS #{label}"
end

def upload(session, name)
  boundary = "PackageLink#{SecureRandom.hex(8)}"
  data = File.binread('/checks/sample.apk')
  body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n#{name}\r\n".b
  body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sample.apk\"\r\nContent-Type: application/octet-stream\r\n\r\n".b
  body << data << "\r\n--#{boundary}--\r\n".b
  session.post '/api/apps/upload', params: body, headers: {'CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}"}
  JSON.parse(session.response.body)
end

session = ActionDispatch::Integration::Session.new(Rails.application)
session.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}"
session.https!
name = "Package Link #{SecureRandom.hex(5)}"
real_parse = AppInfo.method(:parse)
first_bundle = "com.piko.first.#{SecureRandom.hex(4)}"
second_bundle = "com.piko.alternate.#{SecureRandom.hex(4)}"
current_bundle = first_bundle
AppInfo.define_singleton_method(:parse) do |path|
  parsed = real_parse.call(path)
  parsed.define_singleton_method(:bundle_id) { current_bundle }
  parsed
end
begin
  first = upload(session, name)
  check('first package created') { session.response.status == 201 }
  original = Release.find(first.fetch('id'))
  first_app = original.app
  check('first package and summary links differ') { first['package_url'] != first['app_url'] }
  check('summary and package links use stable readable aliases') do
    URI(first['app_url']).path == "/#{first_app.distribution_slug}" &&
      URI(first['package_url']).path == "/#{first_app.distribution_slug}/#{original.platform.downcase}/p#{original.channel_id}/testing"
  end

  current_bundle = second_bundle
  second = upload(session, name)
  check('same product name and different package creates release') { session.response.status == 201 }
  alternate = Release.find(second.fetch('id'))
  check('different package shares product summary') { alternate.app.id == first_app.id && second['app_url'] == first['app_url'] }
  check('different package has distinct channel and stable package link') do
    alternate.channel_id != original.channel_id && second['package_url'] != first['package_url']
  end
  again = upload(session, name)
  check('same package reports a conflict and keeps its link') do
    session.response.status == 409 && again['package_url'] == second['package_url'] && again['existing_id'] == second['id']
  end
ensure
  AppInfo.define_singleton_method(:parse, real_parse)
end

session.get URI(first['app_url']).request_uri
check('summary shows both packages') do
  session.response.status == 200 && session.response.body.include?(original.bundle_id) &&
  session.response.body.include?(second_bundle)
end
session.get "/a/#{first_app.id}"
check('legacy summary link remains available') { session.response.status == 200 }
session.get URI(second['package_url']).request_uri
check('package page shows only matching package') do
  session.response.status == 200 && session.response.body.include?(second_bundle) &&
    !session.response.body.include?(original.bundle_id)
end
session.get "/a/#{first_app.id}/packages/#{alternate.platform}/#{second_bundle}"
check('legacy package link remains available') { session.response.status == 200 }
session.get URI(second['package_qrcode_url']).request_uri
check('package QR is available') { session.response.status == 200 && session.response.media_type.start_with?('image/') }
alternate.update!(distribution_status: 'retired')
session.get URI(second['package_url']).request_uri
check('retired package link is unavailable') { session.response.status == 404 }
session.get URI(first['app_url']).request_uri
check('other package remains on summary') { session.response.status == 200 && session.response.body.include?(original.bundle_id) }

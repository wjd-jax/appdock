require 'action_dispatch/testing/integration'
require 'nokogiri'
raise 'Isolation required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'

def check(label)
  raise "FAILED #{label}" unless yield
  puts "PASS #{label}"
end

check('Rails application and GraphQL use AppDock') do
  Rails.application.class.name == 'AppDock::Application' && AppDockSchema < GraphQL::Schema
end
check('new session name') { Rails.application.config.session_options[:key] == '_appdock_session' }
Rails.application.executor.run!
class AppDockBrandSession < ActionDispatch::Integration::Session
  def process(*args, **kwargs)
    super
  ensure
    Rails.application.executor.run!(reset: true)
  end
end
session = AppDockBrandSession.new(Rails.application)
session.host! 'apps.example.com:18443'
session.https!
%w[/workspace /upload /developers /udid /notifications /access].each do |path|
  session.get path
  if path == '/upload' && session.response.redirect?
    check('upload entry reaches workspace') { URI(session.response.location).path == '/workspace' }
    session.follow_redirect!
  end
  check("AppDock page #{path}") do
    session.response.status == 200 && Nokogiri::HTML(session.response.body).title.include?('AppDock')
  end
end
release = Release.where(distribution_status: 'testing').first || Release.first
raise 'Need isolated APK fixture' unless release
release.update!(distribution_status: 'testing')
release.app.update!(archived: false)
session.get URI(release.download_url).request_uri
session.follow_redirect! if session.response.redirect?
check('APK download preserves SHA-256') do
  session.response.status == 200 && Digest::SHA256.hexdigest(session.response.body) == release.file_sha256
end
session.post '/workspace/uploads'
check('web upload CSRF preserved') { session.response.status == 422 }
check('old source namespace removed') { !Object.const_defined?(:Zealot) }
puts 'APPDOCK BRAND AND DOWNLOAD VERIFIED'

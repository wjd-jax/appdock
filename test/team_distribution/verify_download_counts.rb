require 'action_dispatch/testing/integration'
require 'nokogiri'

raise 'Isolated verification database required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'

class DownloadCountSession < ActionDispatch::Integration::Session
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

release = Release.order(id: :desc).detect { |item| item.file? && !item.app.archived? && item.distribution_status != 'retired' }
raise 'Active release fixture with a file required' unless release
app = release.app
release.update_column(:download_count, 0)
initial_total = Release.where(channel_id: app.channel_ids).sum(:download_count)
session = DownloadCountSession.new(Rails.application)
session.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}"
session.https!

original_status = release.distribution_status
release.update_column(:distribution_status, 'retired')
session.get URI(release.download_url).request_uri
check('retired release is denied without counting') { session.response.status == 404 && release.reload.download_count == 0 }
release.update_column(:distribution_status, original_status)

session.get URI(release.download_url).request_uri
check('redirect does not count') { session.response.status == 302 && release.reload.download_count == 0 }
file_path = URI(session.response.location).request_uri
session.follow_redirect!
check('first file GET counts once') { session.response.status == 200 && session.response.body.bytesize == release.file.size && release.reload.download_count == 1 }

session.head file_path
check('HEAD does not count') { session.response.status == 200 && release.reload.download_count == 1 }
session.get file_path
check('second file GET counts again') { session.response.status == 200 && release.reload.download_count == 2 }

session.get '/workspace'
check('workspace shows cumulative and current-version counts') do
  session.response.status == 200 &&
    session.response.body.include?("累计下载 #{initial_total + 2} 次") &&
    session.response.body.include?('当前版本下载：')
end

session.get Rails.application.routes.url_helpers.distribution_manage_app_path(app)
check('version management shows per-version count') do
  session.response.status == 200 &&
    Nokogiri::HTML(session.response.body).css('.version-event').any? { |item| item.text.include?('下载 2 次') }
end

puts 'DOWNLOAD COUNTS VERIFIED'

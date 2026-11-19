require 'action_dispatch/testing/integration'
require 'nokogiri'
raise 'Isolated verification database required' unless ActiveRecord::Base.connection_db_config.database == 'appdock_verify'
Rails.application.executor.run!
class DeletionSession < ActionDispatch::Integration::Session
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
s = DeletionSession.new(Rails.application)
s.host! "apps.example.com:#{ENV.fetch('APPDOCK_ACCEPTANCE_HTTPS_PORT', '18443')}"; s.https!
s.get '/workspace'
csrf = Nokogiri::HTML(s.response.body).at_css('meta[name="csrf-token"]')['content']
headers = {'X-CSRF-Token'=>csrf}
def upload_fixture(s, name, environment)
  original_parse = AppInfo.method(:parse)
  build = SecureRandom.random_number(1_000_000).to_s
  AppInfo.define_singleton_method(:parse) do |path|
    parsed = original_parse.call(path)
    parsed.define_singleton_method(:bundle_id) { 'com.verify.p' + Digest::SHA256.hexdigest(name)[0, 12] }
    parsed.define_singleton_method(:build_version) { build }
    parsed
  end
  file = Rack::Test::UploadedFile.new('/checks/sample.apk', 'application/octet-stream')
  s.post '/api/apps/upload', params: {name: name, file: file, business_environment: environment}
  raise "Upload failed #{s.response.status}: #{s.response.body}" unless s.response.status == 201
  Release.find(JSON.parse(s.response.body).fetch('id'))
ensure
  AppInfo.define_singleton_method(:parse, original_parse)
end
name = "Delete verification #{SecureRandom.hex(5)}"
a = upload_fixture(s, name, 'testing')
b = upload_fixture(s, name, 'production')
c = upload_fixture(s, name, 'testing')
other = upload_fixture(s, "Other #{SecureRandom.hex(4)}", 'testing')
app = a.app
# Make another package under this product while retaining a different bundle identity.
alternate = upload_fixture(s, "Alternate #{SecureRandom.hex(4)}", 'testing')
alternate.scheme.update!(app: app)
alternate.update_columns(bundle_id: 'com.verify.alternate')
helpers = Rails.application.routes.url_helpers
package_path = helpers.distribution_manage_package_path(app, a.platform, a.bundle_id)
product_path = helpers.distribution_manage_app_path(app)
s.get package_path
check('package has package and individual deletion forms') { s.response.status == 200 && Nokogiri::HTML(s.response.body).css('form[data-delete-confirm]').size == 4 }
s.get product_path
check('product confirmation states all platforms and environments') { s.response.status == 200 && s.response.body.include?('删除产品') && s.response.body.include?('所有平台、测试和正式环境') }
# Missing/invalid CSRF must leave the target intact.
s.delete helpers.distribution_version_path(c)
check('missing CSRF denied without deleting') { s.response.status == 422 && Release.exists?(c.id) }
a.channel.update!(recommended_release: c)
Rails.cache.write("app_#{app.id}_recently_release", c)
file = c.file.path
metadata_id = c.metadata&.id
s.delete helpers.distribution_version_path(c), params: {return_to: 'package'}, headers: headers
check('single deletion redirects to remaining package') { s.response.status == 303 && URI(s.response.location).path == package_path }
check('single version file and metadata removed') { !Release.exists?(c.id) && !File.exist?(file) && (!metadata_id || !Metadatum.exists?(metadata_id)) }
check('recommendation and product cache cleared') { a.channel.reload.recommended_release_id.nil? && Rails.cache.read("app_#{app.id}_recently_release").nil? }
check('other versions remain') { Release.exists?(a.id) && Release.exists?(b.id) }
# Public ingress rejects the delete route regardless of current public switch.
s.delete package_path, headers: headers.merge('X-Appdock-Public'=>'1')
check('external deletion denied') { [404,503].include?(s.response.status) && Release.exists?(a.id) }
# A reader cannot delete in authenticated mode.
original_trust = DistributionAccess.method(:trusted_lan?)
DistributionAccess.define_singleton_method(:trusted_lan?) { false }
begin
  reader = User.create!(email: "delete-reader-#{SecureRandom.hex(4)}@example.test", password: SecureRandom.hex(16), username: 'Reader', role: 'member')
  check('reader has no product or release delete permission') { !AppPolicy.new(reader, app).destroy? && !ReleasePolicy.new(reader, a).destroy? }
ensure
  DistributionAccess.define_singleton_method(:trusted_lan?, original_trust)
end
files = [a.file.path, b.file.path]
s.delete package_path, headers: headers
check('package deletion redirects to product') { s.response.status == 303 && URI(s.response.location).path == product_path }
check('package deletes testing and production files') { !Release.exists?(a.id) && !Release.exists?(b.id) && files.none? { |path| File.exist?(path) } }
check('other package and product preserved') { App.exists?(app.id) && Release.exists?(alternate.id) && Release.exists?(other.id) }
s.get package_path
check('deleted package no longer accessible') { s.response.status == 404 }
s.get URI(a.release_url).request_uri
check('deleted version link no longer accessible') { s.response.status == 404 }
# Delete the final version through its package view and return to product safely.
s.delete helpers.distribution_version_path(alternate), params: {return_to: 'package'}, headers: headers
check('last version deletion returns to product') { s.response.status == 303 && URI(s.response.location).path == product_path }
final = upload_fixture(s, name, 'testing')
channel_ids = app.channel_ids
scheme_ids = app.schemes.ids
file = final.file.path
slug = app.distribution_slug
s.delete product_path, headers: headers
check('product deletion returns to workspace') { s.response.status == 303 && URI(s.response.location).path == '/workspace' }
check('product cascade deletes channels schemes versions files and collaborators') do
  !App.exists?(app.id) && !Scheme.where(id: scheme_ids).exists? && !Channel.where(id: channel_ids).exists? &&
    !Release.where(channel_id: channel_ids).exists? && !Collaborator.where(app_id: app.id).exists? && !File.exist?(file)
end
check('unrelated product preserved') { Release.exists?(other.id) && App.exists?(other.app.id) }
s.get "/#{slug}"
check('deleted product summary unavailable') { s.response.status == 404 }
puts 'DELETION VERIFIED'

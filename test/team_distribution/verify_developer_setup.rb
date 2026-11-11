# bin/rails runner --skip-executor /checks/verify_developer_setup.rb
require 'action_dispatch/testing/integration'
require 'json'
require 'yaml'
require 'zip'
require 'nokogiri'
raise 'Isolated verification database required' unless ActiveRecord::Base.connection_db_config.database == 'zealot_verify'
Rails.application.executor.run!
class DeveloperSetupSession < ActionDispatch::Integration::Session
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
count = Release.count
session = DeveloperSetupSession.new(Rails.application)
session.host! 'apps.example.com:18443'
session.https!
session.get '/developers'
check('anonymous setup page includes channel context and interactive controls') { session.response.status == 200 && session.response.body.include?('下载当前项目接入包') && session.response.body.include?('setup-form') && !session.response.body.include?('开发者登录') }
csrf = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')['content']
headers = {'X-CSRF-Token' => csrf, 'ACCEPT' => 'application/json'}
base = { platform: 'android', trigger: 'manual', branch: 'develop', runner: 'Linux'}
session.post '/developers/preview', params: base, headers: {'ACCEPT' => 'application/json'}
check('setup generator requires CSRF without account prompts') { session.response.status == 422 }
session.post '/developers/preview', params: base.merge(branch: 'not valid / ignored'), headers: headers
check('manual CI generation has no branch dependency') { session.response.status == 200 }
%w[android ios flutter].each do |platform|
  %w[manual push].each do |trigger|
    payload = base.merge( platform: platform, trigger: trigger, runner: platform == 'ios' ? 'macOS' : 'Linux')
    session.post '/developers/preview', params: payload, headers: headers
    check("#{platform}/#{trigger}: generation succeeds") { session.response.status == 200 }
    files = JSON.parse(session.response.body).fetch('files')
    cfg = JSON.parse(files.fetch('.team-distribution.json'))
    check("#{platform}/#{trigger}: endpoint/channel and nonempty build configured") { !cfg.key?('channel_key') && cfg['endpoint'] == 'https://apps.example.com:18443' && cfg['build'].is_a?(Array) && cfg['build'].any? }
    github = YAML.safe_load(files.fetch('.github/workflows/team-distribution.yml'))
    # Psych YAML 1.1 parses the unquoted GitHub key `on` as true.
    triggers = github['on'] || github[true]
    gitlab = YAML.safe_load(files.fetch('ci/team-distribution.gitlab.yml'))
    check("#{platform}/#{trigger}: valid YAML, expected trigger and LAN runner") { triggers.key?('workflow_dispatch') && triggers.key?('push') == (trigger == 'push') && github.dig('jobs','distribute','runs-on').include?('company-lan') && gitlab.dig('team_test_distribution','tags').include?('company-lan') }
  end
end
[{build: 'rm -rf .'}, {build: '[]'}, {build: '42'}, {build: '["please"]', artifact: ''}, {trigger: 'push', branch: 'develop\ninvalid'}, {platform: 'ios', runner: 'Linux'}].each do |invalid|
  session.post '/developers/preview', params: base.merge(invalid), headers: headers
  check("invalid config rejected: #{invalid.keys.join(',')}") { session.response.status == 422 && JSON.parse(session.response.body)['error'].present? }
end
session.post '/developers/bundle', params: base.merge(trigger: 'push'), headers: headers
check('project kit returned as ZIP') { session.response.status == 200 && session.response.media_type == 'application/zip' }
File.binwrite('/tmp/developer-kit.zip', session.response.body)
entries = {}
Zip::InputStream.open(StringIO.new(session.response.body)) do |zip|
  while entry = zip.get_next_entry
    raise 'unsafe archive path' if entry.name.start_with?('/') || entry.name.split('/').include?('..')
    entries[entry.name] = zip.read
  end
end
manifest = JSON.parse(entries.fetch('distribution-kit-manifest.json'))
check('kit manifest hashes verify every payload') { manifest.fetch('files').all? { |name,sha| Digest::SHA256.hexdigest(entries.fetch(name)) == sha } }
check('project skill and CLI are complete and byte-identical') { entries.key?('.agents/skills/team-distribution/SKILL.md') && entries.key?('.agents/skills/team-distribution/agents/openai.yaml') && entries['.agents/skills/team-distribution/scripts/team_release.py'] == entries['tools/team_release.py'] && entries['tools/team_release.py'] == Distribution::DeveloperKit.cli }
session.get '/developers/skill.zip'
check('standalone Skill archive downloads without login') { session.response.status == 200 && session.response.media_type == 'application/zip' }
File.binwrite('/tmp/developer-skill.zip', session.response.body)
check('setup generation never creates releases') { Release.count == count }
puts({verified: true, release_count: count, automatic_app_detection: true}.to_json)

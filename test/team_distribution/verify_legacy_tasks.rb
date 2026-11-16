require 'minitest/autorun'
require 'rake'

class LegacyTasksTest < Minitest::Test
  include Rake::DSL

  def setup
    Rake.application = Rake::Application.new
  end

  def test_migration_version_reaches_new_task
    received = nil
    task 'appdock:db:migrate', [:version] do |_, args|
      received = args[:version]
    end
    load File.expand_path('../../lib/tasks/legacy_tasks.rake', __dir__)
    Rake::Task['zealot:db:migrate'].invoke('123')
    assert_equal '123', received
  end

  def test_upgrade_without_arguments
    called = false
    task 'appdock:upgrade' do
      called = true
    end
    load File.expand_path('../../lib/tasks/legacy_tasks.rake', __dir__)
    Rake::Task['zealot:upgrade'].invoke
    assert called
  end
end

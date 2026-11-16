# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'rbconfig'

class AppDockEnvironmentTest < Minitest::Test
  CONFIG = File.expand_path('../../config/appdock_environment.rb', __dir__)

  def value(environment)
    output, status = Open3.capture2(environment, RbConfig.ruby, '-r', CONFIG,
                                  '-e', "print ENV.fetch('APPDOCK_TEST_OPTION', 'missing')")
    assert status.success?
    output
  end

  def test_legacy_configuration
    assert_equal 'legacy', value('ZEALOT_TEST_OPTION' => 'legacy', 'APPDOCK_TEST_OPTION' => nil)
  end

  def test_new_configuration_takes_precedence
    assert_equal 'current', value('ZEALOT_TEST_OPTION' => 'legacy', 'APPDOCK_TEST_OPTION' => 'current')
  end

  def test_explicit_empty_value_is_preserved
    assert_equal '', value('ZEALOT_TEST_OPTION' => 'legacy', 'APPDOCK_TEST_OPTION' => '')
  end
end

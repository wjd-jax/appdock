# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require_relative 'appdock_environment'

# Rails 8 reads SECRET_KEY_BASE directly; retain the documented SECRET_TOKEN
# for existing installations and the legacy secrets.yml configuration.
ENV['SECRET_KEY_BASE'] ||= ENV['SECRET_TOKEN'] if ENV['SECRET_TOKEN'] && !ENV['SECRET_TOKEN'].empty?

require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'bootsnap/setup' # Speed up boot time by caching expensive operations.

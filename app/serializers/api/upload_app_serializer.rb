# frozen_string_literal: true

class Api::UploadAppSerializer < ApplicationSerializer
  # release model based
  attributes :id, :version, :app_name, :bundle_id, :release_version, :build_version,
             :source, :branch, :git_commit, :ci_url, :size, :platform, :device_type,
             :icon_url, :release_url, :install_url, :qrcode_url, :changelog, :text_changelog,
             :custom_fields, :created_at, :file_sha256, :distribution_status, :app_url, :environment_url

  belongs_to :app
  belongs_to :scheme
  belongs_to :channel

  def app_url
    Distribution::AppDownloads.new(object.app).url
  end

  def environment_url
    object.scheme.distribution_url
  end

  def changelog
    object.array_changelog(default_template: false)
  end
end

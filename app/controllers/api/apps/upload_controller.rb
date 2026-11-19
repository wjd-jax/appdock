# frozen_string_literal: true

class Api::Apps::UploadController < Api::BaseController
  include AppArchived

  before_action :validate_user_token

  # Upload an App
  #
  # POST /api/apps/upload
  #
  # @param token         [String]   optional  user token (only outside trusted LAN mode)
  # @param file          [String]   required  file of app
  # @param channel_key   [String]   optional  channel key of app
  # @param name          [String]   optional  name of app
  # @param password      [String]   optional  password to download app
  # @param release_type  [String]   optional  release type(debug, beta, adhoc, release, enterprise etc)
  # @param business_environment [String] optional testing(default) or production, selected by the uploader
  # @param source        [String]   optional  upload source(api, cli, jenkins, gitlab-ci etc)
  # @param changelog     [String]   optional  changelog
  # @param branch        [String]   optional  git branch
  # @param git_commit    [String]   optional  git commit
  # @param ci_url        [String]   optional  ci url
  # @return              [String]   json formatted app info
  def create
    result = Distribution::UploadPackage.new(params, current_user, source: params[:source].presence || 'api').call
    body = ActiveModelSerializers::SerializableResource.new(result.release, serializer: Api::UploadAppSerializer).as_json
    render json: body.merge(duplicate: result.duplicate, overwritten: result.overwritten, existing_id: result.release.id,
                            error: (result.duplicate ? '版本号和 build 号已存在；确认覆盖需传 overwrite=true 和 overwrite_release_id=existing_id' : nil)), status: result.duplicate ? :conflict : :created
  rescue Distribution::UploadPackage::InvalidPackage => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

end

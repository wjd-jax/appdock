# frozen_string_literal: true

class Download::ReleasesController < ApplicationController
  before_action :set_release

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_entity_response

  def show
    return render_not_found_entity_response unless shared_release_access?

    # password protected check
    unless helpers.logged_in_or_without_auth?(@release) 
      return redirect_to channel_release_path(@release.channel, @release, **@release.distribution_share_options)
    end

    return render_not_found_entity_response unless File.exist?(@release.file.path.to_s)

    redirect_to filename_download_release_url(@release, @release.download_filename, **@release.distribution_share_options)
  end

  def download
    return render_not_found_entity_response unless shared_release_access?

    # The filename URL is public and can be visited without passing through #show.
    unless helpers.logged_in_or_without_auth?(@release)
      return redirect_to channel_release_path(@release.channel, @release, **@release.distribution_share_options)
    end

    return render_not_found_entity_response unless @release.file? && File.file?(@release.file.path.to_s)

    # 触发 web_hook
    @release.channel.perform_web_hook('download_events', current_user&.id)

    headers['Content-Length'] = @release.file.size
    send_file @release.file.path,
              filename: @release.download_filename,
              disposition: 'attachment'
    Release.increment_counter(:download_count, @release.id) if request.get?
  end

  private

  def shared_release_access?
    (!DistributionAccess.trusted_lan? && user_signed_in?) || @release.valid_share_token?(params[:share])
  end

  def render_not_found_entity_response
    render json: {
      error: t('.not_found')
    }, status: :not_found
  end


  def set_release
    @release = Release.find(params[:id])
  end
end



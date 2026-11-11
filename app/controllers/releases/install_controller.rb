# frozen_string_literal: true

class Releases::InstallController < ApplicationController

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_entity_response

  def show
    @release = Release.version_by_channel(params[:channel_id], params[:release_id])
    return render_not_found_entity_response unless (!DistributionAccess.trusted_lan? && user_signed_in?) || @release.valid_share_token?(params[:share])

    render content_type: 'text/xml', layout: false
  end

  private

  def render_not_found_entity_response
    render xml: { error: t('.not_found') }, status: :not_found
  end
end


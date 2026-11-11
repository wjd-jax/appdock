# frozen_string_literal: true

class Releases::QrcodeController < ApplicationController
  include Qrcode

  before_action :set_release

  ##
  # 显示应用的二维码
  # GET /apps/:slug/(:version)/qrcode
  def show
    return head :not_found unless (!DistributionAccess.trusted_lan? && user_signed_in?) || @release.valid_share_token?(params[:share])

    render qrcode: @release.release_url, **qrcode_options
  end

  private

  def set_release
    @release = Release.find params[:release_id]
  end
end

module Distribution
  class PublicController < ApplicationController
    include Qrcode
    layout 'distribution'
    before_action :load_environment

    def environment
      return redirect_to distribution_app_path(@scheme.app) if DistributionAccess.trusted_lan?
      @channels = @scheme.channels.includes(:recommended_release).to_a
      @available = @channels.filter_map do |channel|
        r = channel.recommended_release
        r if r && r.valid_share_token?(r.share_token) && r.file?
      end
    end

    def qrcode
      render qrcode: @scheme.distribution_url, **qrcode_options
    end

    private

    def load_environment
      @scheme = Scheme.find(params[:id])
      permitted = !DistributionAccess.trusted_lan? && current_user && SchemePolicy.new(current_user, @scheme).index?
      unless permitted || @scheme.valid_distribution_share?(params[:share])
        render 'distribution/public/unavailable', status: :not_found
      end
    end
  end
end

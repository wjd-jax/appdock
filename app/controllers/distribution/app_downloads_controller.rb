module Distribution
  class AppDownloadsController < ApplicationController
    include Qrcode
    layout 'distribution'
    before_action :load_app, except: %i[product_alias product_alias_qrcode package_alias package_alias_qrcode]
    before_action :load_product_alias, only: %i[product_alias product_alias_qrcode package_alias package_alias_qrcode]
    before_action :load_package_alias, only: %i[package_alias package_alias_qrcode]

    before_action :load_package_environment, only: %i[package package_qrcode package_alias package_alias_qrcode]

    def show
      releases = AppDownloads.new(@app).available
      @latest = releases.uniq { |release| [release.platform, release.bundle_id] }
      @environment_filter = history_environment_filter
      @history_platform = %w[ios android].include?(params[:history_platform]) ? params[:history_platform] : 'all'
      @history = filter_history(releases).first(50)
      render 'distribution/public/app'
    end

    def qrcode
      render qrcode: AppDownloads.new(@app).url, **qrcode_options
    end

    def product_alias
      show
    end

    def product_alias_qrcode
      qrcode
    end

    def package
      releases = AppDownloads.new(@app).package_releases(params[:platform], params[:bundle_id], environment: @package_environment)
      render_package(releases)
    end

    def package_qrcode
      release = AppDownloads.new(@app).package_releases(params[:platform], params[:bundle_id], environment: @package_environment).first
      return head :not_found unless release

      render qrcode: AppDownloads.new(@app).package_url(release, environment: @package_environment), **qrcode_options
    end

    def package_alias
      release = package_alias_release
      releases = release ? AppDownloads.new(@app).package_releases(release.platform, release.bundle_id, environment: @package_environment) : []
      render_package(releases)
    end

    def package_alias_qrcode
      release = package_alias_release
      return head :not_found unless release && AppDownloads.new(@app).package_releases(release.platform, release.bundle_id, environment: @package_environment).any?

      render qrcode: AppDownloads.new(@app).package_url(release, environment: @package_environment), **qrcode_options
    end

    private

    def load_package_environment
      value = params[:package_environment]
      return if value.nil?
      unless TeamRelease::BUSINESS_ENVIRONMENTS.key?(value)
        return render 'distribution/public/unavailable', status: :not_found
      end
      @package_environment = value
    end

    def load_app
      @app = App.find(params[:id])
      check_access
    end

    def load_product_alias
      @app = App.active.find_by!(distribution_slug: params[:product_slug])
      check_access
    end

    def load_package_alias
      @channel = Channel.find(params[:package_code].delete_prefix('p').to_i)
      return render 'distribution/public/unavailable', status: :not_found unless @channel.app.id == @app.id
    end

    def check_access
      allowed = DistributionAccess.trusted_lan? || (current_user && AppPolicy.new(current_user, @app).show?)
      unless allowed && !@app.archived?
        render 'distribution/public/unavailable', status: :not_found
      end
    end

    def package_alias_release
      release = @channel.releases.order(id: :desc).first
      return unless release
      return if @channel.releases.where.not(bundle_id: release.bundle_id).exists?
      return unless release.platform.downcase == params[:platform]

      release
    end

    def render_package(releases)
      return render 'distribution/public/unavailable', status: :not_found if releases.empty?

      @latest = releases.first(1)
      @environment_filter = @package_environment || history_environment_filter
      @history_platform = %w[ios android].include?(params[:history_platform]) ? params[:history_platform] : 'all'
      @history = filter_history(releases).first(50)
      @package_view = true
      render 'distribution/public/app'
    end

    def history_environment_filter
      value = params[:business_environment]
      TeamRelease::BUSINESS_ENVIRONMENTS.key?(value) ? value : 'all'
    end

    def filter_history(releases)
      releases.select do |release|
        (@environment_filter == 'all' || release.business_environment_key == @environment_filter) &&
          (@history_platform == 'all' || release.platform.downcase == @history_platform)
      end
    end
  end
end

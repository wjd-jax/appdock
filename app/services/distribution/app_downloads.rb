module Distribution
  class AppDownloads
    def initialize(app)
      @app = app
    end

    def available
      return [] if @app.archived?
      Release.where(channel_id: @app.channel_ids).where.not(distribution_status: 'retired').recently_uploaded.includes(channel: {scheme: :app}).select(&:file?)
    end

    def latest
      available.uniq { |release| [release.platform, release.bundle_id] }
    end

    def package_releases(platform, bundle_id, environment: nil)
      available.select do |release|
        release.platform == platform && release.bundle_id == bundle_id &&
          (environment.nil? || release.business_environment_key == environment)
      end
    end

    def package_url(release, environment: release.business_environment_key)
      helpers = Rails.application.routes.url_helpers
      options = Setting.url_options.merge(PublicContext.url_options).merge(package_environment: environment)
      if short_package?(release)
        helpers.distribution_package_alias_url(@app.distribution_slug, release.platform.downcase,
                                               "p#{release.channel_id}", **options)
      else
        helpers.distribution_package_url(@app, release.platform, release.bundle_id, **options)
      end
    end

    def package_qrcode_url(release, environment: release.business_environment_key)
      helpers = Rails.application.routes.url_helpers
      options = Setting.url_options.merge(PublicContext.url_options).merge(package_environment: environment)
      if short_package?(release)
        helpers.distribution_package_alias_qrcode_url(@app.distribution_slug, release.platform.downcase,
                                                      "p#{release.channel_id}", **options)
      else
        helpers.distribution_package_qrcode_url(@app, release.platform, release.bundle_id, **options)
      end
    end

    def package_path(release, environment: release.business_environment_key)
      if short_package?(release)
        Rails.application.routes.url_helpers.distribution_package_alias_path(@app.distribution_slug,
                                                                            release.platform.downcase, "p#{release.channel_id}", package_environment: environment)
      else
        Rails.application.routes.url_helpers.distribution_package_path(@app, release.platform, release.bundle_id, package_environment: environment)
      end
    end

    def package_qrcode_path(release, environment: release.business_environment_key, **options)
      if short_package?(release)
        Rails.application.routes.url_helpers.distribution_package_alias_qrcode_path(@app.distribution_slug,
                                                                                   release.platform.downcase,
                                                                                   "p#{release.channel_id}", **options.merge(package_environment: environment))
      else
        Rails.application.routes.url_helpers.distribution_package_qrcode_path(@app, release.platform, release.bundle_id, **options.merge(package_environment: environment))
      end
    end

    def url
      Rails.application.routes.url_helpers.distribution_product_alias_url(@app.distribution_slug,
                                                                          **Setting.url_options.merge(PublicContext.url_options))
    end

    def path
      Rails.application.routes.url_helpers.distribution_product_alias_path(@app.distribution_slug)
    end

    def qrcode_path(**options)
      Rails.application.routes.url_helpers.distribution_product_alias_qrcode_path(@app.distribution_slug, **options)
    end

    private

    def short_package?(release)
      !release.channel.releases.where.not(bundle_id: release.bundle_id).exists?
    end

  end
end

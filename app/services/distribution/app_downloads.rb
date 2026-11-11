module Distribution
  class AppDownloads
    def initialize(app)
      @app = app
    end

    def available
      return [] if @app.archived?
      Release.where(channel_id: @app.channel_ids).where.not(distribution_status: 'retired').order(id: :desc).includes(channel: {scheme: :app}).select(&:file?)
    end

    def latest
      available.uniq(&:platform)
    end

    def url
      Rails.application.routes.url_helpers.distribution_app_url(@app, **Setting.url_options)
    end
  end
end

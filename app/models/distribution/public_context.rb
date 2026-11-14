module Distribution
  class PublicContext < ActiveSupport::CurrentAttributes
    attribute :external
    def self.url_options
      external ? {host: ENV.fetch('APPDOCK_PUBLIC_HOST', 'download.17love.life'), protocol: 'https', port: nil} : {}
    end
  end
end

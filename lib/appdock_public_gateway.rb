# The public listener goes directly to Rails, never the container static file server.
class AppDockPublicGateway
  ALLOWED = {
    'distribution/catalog' => %w[index icon],
    'distribution/app_downloads' => %w[show qrcode],
    'releases' => %w[index show auth],
    'releases/install' => %w[show],
    'releases/qrcode' => %w[show],
    'download/releases' => %w[show download]
  }.freeze
  STATIC = %w[/distribution/app.css /distribution/app.js /distribution/fir.css /distribution/download.css /distribution/appdock-logo.svg /distribution/ribbons-left.svg].freeze
  def initialize(app)
    @app = app
  end
  def call(env)
    external = env['HTTP_X_APPDOCK_PUBLIC'] == '1' || env['HTTP_HOST'].to_s.split(':').first == ENV.fetch('APPDOCK_PUBLIC_HOST', 'download.17love.life')
    return @app.call(env) unless external
    return denied(503) unless Distribution::NetworkAccess.live?
    path = env['PATH_INFO']
    return denied(404) if path.include?('%') || path.include?('..') || path.include?("\\")
    return denied(404) if path == '/admin' || path.start_with?('/admin/')
    method = env['REQUEST_METHOD']
    env['PATH_INFO'] = path = '/catalog' if path == '/'
    allowed = false
    if %w[GET HEAD].include?(method) && STATIC.include?(path)
      allowed = true
    else
      begin
        route = Rails.application.routes.recognize_path(path, method: method)
        allowed = ALLOWED.fetch(route[:controller], []).include?(route[:action]) &&
          (%w[GET HEAD].include?(method) || (method == 'POST' && route[:controller] == 'releases' && route[:action] == 'auth'))
      rescue ActionController::RoutingError
        allowed = false
      end
    end
    return denied(404) unless allowed
    env['appdock.public'] = true
    status, headers, body = @app.call(env)
    # Browser/CDN must revalidate even after the switch is turned off.
    headers['cache-control'] = 'private, no-store'
    headers['referrer-policy'] = 'no-referrer'
    [status, headers, body]
  end
  def denied(code)
    [code, {'content-type'=>'text/plain; charset=utf-8', 'cache-control'=>'no-store'}, [code == 503 ? '外网下载已关闭或暂不可用' : '此入口仅限内网访问']]
  end
end

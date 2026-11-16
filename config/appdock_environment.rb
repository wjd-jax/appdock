# frozen_string_literal: true

# Existing deployments can retain their configuration. Explicit APPDOCK_* wins,
# including an explicitly empty value; never log configuration values.
ENV.keys.grep(/\AZEALOT_/).each do |legacy|
  current = legacy.sub(/\AZEALOT_/, 'APPDOCK_')
  ENV[current] = ENV[legacy] unless ENV.key?(current)
end

# Keep authentication cookies readable when upgrading an existing installation.

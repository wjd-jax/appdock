module TeamScheme
  extend ActiveSupport::Concern

  def distribution_share_token
    Rails.application.message_verifier('environment_share_v1').generate({'id' => id, 'v' => share_version})
  end

  def valid_distribution_share?(token)
    return false if app.archived?
    return true if DistributionAccess.trusted_lan?
    return false if token.blank? || (share_expires_at && share_expires_at <= Time.current)
    Rails.application.message_verifier('environment_share_v1').verified(token) == {'id' => id, 'v' => share_version}
  end

  def distribution_url
    return Distribution::AppDownloads.new(app).url if DistributionAccess.trusted_lan?
    options = DistributionAccess.trusted_lan? ? {} : {share: distribution_share_token}
    Rails.application.routes.url_helpers.distribution_environment_url(id, **options, **Setting.url_options)
  end

  def rotate_distribution_share!
    with_lock { update!(share_version: share_version + 1) }
  end
end

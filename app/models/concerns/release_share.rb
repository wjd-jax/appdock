# frozen_string_literal: true

module ReleaseShare
  extend ActiveSupport::Concern

  def share_token
    Rails.application.message_verifier('release_share_v1').generate({'id' => id, 'v' => share_version})
  end

  def valid_share_token?(token)
    return false if distribution_status == 'retired' || app.archived?
    return true if DistributionAccess.trusted_lan?
    return false if token.blank?
    return false if share_expires_at && share_expires_at <= Time.current

    value = Rails.application.message_verifier('release_share_v1').verified(token)
    value == {'id' => id, 'v' => share_version} || (share_version.zero? && value == id)
  end

  def rotate_share!
    with_lock { update!(share_version: share_version + 1) }
  end
end

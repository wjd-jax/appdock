module DistributionHelper
  def distribution_time(value)
    value ? value.in_time_zone.strftime('%Y-%m-%d %H:%M') : '—'
  end

  def distribution_expiry(value)
    value&.in_time_zone&.strftime('%Y-%m-%dT%H:%M')
  end

  def distribution_platform(release)
    release.ios? ? 'iOS' : release.android? ? 'Android' : release.platform
  end

  def distribution_notes(release)
    # Changelog is untrusted build input: escape it instead of rendering arbitrary HTML.
    simple_format(h(release.text_changelog(default_template: false).presence || '开发者暂未填写更新说明。'), sanitize: false)
  end
end

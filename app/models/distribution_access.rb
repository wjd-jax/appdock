class DistributionAccess
  def self.trusted_lan?
    ENV['APPDOCK_TRUSTED_LAN'] == 'true'
  end

  # 内网共享操作者只用于持久化上传归属和后台任务，不提供前台登录凭据。
  def self.operator
    User.find_or_create_by!(email: 'team-distribution@localhost.invalid') do |user|
      user.username = '内网团队'
      user.role = :developer
      user.password = SecureRandom.hex(32)
      user.confirmed_at = Time.current
    end
  end
end

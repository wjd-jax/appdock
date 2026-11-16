module TeamRelease
  extend ActiveSupport::Concern
  STATUSES = {'testing' => '待测试', 'approved' => '测试通过', 'retired' => '已停用'}.freeze
  BUSINESS_ENVIRONMENTS = {'testing' => '测试环境', 'production' => '正式环境'}.freeze
  included do
    validates :distribution_status, inclusion: { in: STATUSES.keys }
    validates :business_environment, inclusion: { in: BUSINESS_ENVIRONMENTS.keys }
    validates :issue_url, format: { with: /\Ahttps?:\/\/[^\s]+\z/ }, allow_blank: true
    before_validation :default_business_environment, on: :create
    before_validation :compute_distribution_hash
    after_save :clear_retired_recommendation
  end

  def distribution_label
    STATUSES.fetch(distribution_status, '待测试')
  end

  def business_environment_label
    BUSINESS_ENVIRONMENTS.fetch(business_environment || 'testing')
  end

  def business_environment_key
    business_environment || 'testing'
  end

  def recommended?
    channel.recommended_release_id == id
  end

  private

  def default_business_environment
    self.business_environment = 'testing' if business_environment.nil?
  end

  def compute_distribution_hash
    if file.present? && File.file?(file.path.to_s) && (file_sha256.blank? || will_save_change_to_file?)
      self.file_sha256 = Digest::SHA256.file(file.path).hexdigest
    end
  end

  def clear_retired_recommendation
    channel.update!(recommended_release_id: nil) if distribution_status == 'retired' && recommended?
  end
end

module TeamRelease
  extend ActiveSupport::Concern
  STATUSES = {'testing' => '待测试', 'approved' => '测试通过', 'retired' => '已停用'}.freeze
  included do
    validates :distribution_status, inclusion: { in: STATUSES.keys }
    validates :issue_url, format: { with: /\Ahttps?:\/\/[^\s]+\z/ }, allow_blank: true
    before_validation :compute_distribution_hash
    after_save :clear_retired_recommendation
  end

  def distribution_label
    STATUSES.fetch(distribution_status, '待测试')
  end

  def recommended?
    channel.recommended_release_id == id
  end

  private

  def compute_distribution_hash
    if file.present? && File.file?(file.path.to_s) && (file_sha256.blank? || will_save_change_to_file?)
      self.file_sha256 = Digest::SHA256.file(file.path).hexdigest
    end
  end

  def clear_retired_recommendation
    channel.update!(recommended_release_id: nil) if distribution_status == 'retired' && recommended?
  end
end

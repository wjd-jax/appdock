module Distribution
  class OperationsController < BaseController
    layout 'distribution'

    def index
      return head :forbidden unless trusted_lan? || current_user.admin?
      path = Rails.root.join('operations/status.json')
      @health = path.file? ? JSON.parse(path.read) : {}
      @keep = params.fetch(:keep, '10').to_i.clamp(1, 100)
      @days = params.fetch(:days, '30').to_i.clamp(1, 3650)
      @candidates = []
      Channel.includes(:releases).find_each do |channel|
        ordered = channel.releases.sort_by(&:id).reverse
        ordered.drop(@keep).each do |release|
          next if release.id == channel.recommended_release_id || release.distribution_status == 'approved'
          next unless release.created_at < @days.days.ago && release.file?
          @candidates << release
        end
      end
      @candidate_bytes = @candidates.sum { |r| r.size || 0 }
      @candidates = @candidates.first(200)
    rescue JSON::ParserError
      @health = {'error' => '运维状态文件无法解析，请检查维护任务'}
      @candidates ||= []
      @candidate_bytes ||= 0
    end
  end
end

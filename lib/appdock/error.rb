# frozen_string_literal: true

class AppDock::Error < StandardError
  def initialize(data = nil)
    @data = data
    super
  end

  class RecordExisted < AppDock::Error
    def message
      I18n.t('errors.messages.record_existed', model: @data[:model].model_name.human)
    end
  end

  class RecordNotFound < AppDock::Error
    def message
      case @data[:model]
      when User.class
        I18n.t('errors.messages.user_not_found')
      else
        I18n.t('errors.messages.record_not_found')
      end
    end
  end

  class AppArchivedDeny < AppDock::Error
    def message
      I18n.t('errors.messages.app_archived', name: @data[:name])
    end
  end

  module API
    class NotFound < AppDock::Error
      def message
        I18n.t('errors.messages.api_not_found')
      end
    end
  end
end

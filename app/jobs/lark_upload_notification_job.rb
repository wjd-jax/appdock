class LarkUploadNotificationJob < ApplicationJob
  queue_as :webhook

  def perform(release_id)
    return unless Distribution::LarkNotification.config['enabled']
    release = Release.find_by(id: release_id)
    Distribution::LarkNotification.deliver(release) if release
  end
end

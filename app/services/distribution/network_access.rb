module Distribution
  class NetworkAccess
    ROOT = Rails.root.join('network-access')
    def self.read(name)
      JSON.parse(ROOT.join(name).read)
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end
    def self.requested?
      read('request.json')['enabled'] == true
    end
    def self.status
      read('status.json')
    end
    def self.live?
      value = status
      value['state'] == 'enabled' && Time.now.to_f - value.fetch('heartbeat', 0).to_f < 20 && requested?
    end
    def self.request!(enabled)
      ROOT.mkpath
      # Serialize concurrent saves and atomically replace; host only accepts a boolean.
      ROOT.join('request.lock').open('a') do |lock|
        lock.flock(File::LOCK_EX)
        temp = ROOT.join(".request-#{SecureRandom.hex(8)}")
        begin
          temp.write(JSON.generate(enabled: enabled, id: SecureRandom.uuid, at: Time.now.utc.iso8601))
          File.rename(temp, ROOT.join('request.json'))
        ensure
          temp.delete if temp.exist?
        end
      end
    end
  end
end

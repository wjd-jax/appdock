module Distribution
  class DevelopersController < BaseController
    before_action :verify_authenticity_token, only: %i[preview bundle]

    def index
    end

    def preview
      files = kit.files
      # Only human-readable setup outputs are returned in the preview.
      render json: {files: files.slice('.team-distribution.json', '.github/workflows/team-distribution.yml', 'ci/team-distribution.gitlab.yml', 'docs/team-distribution.md')}
    rescue DeveloperKit::InvalidConfig => e
      render json: {error: e.message}, status: :unprocessable_entity
    end

    def bundle
      send_zip kit.files, 'team-distribution-kit.zip'
    rescue DeveloperKit::InvalidConfig => e
      render json: {error: e.message}, status: :unprocessable_entity
    end

    def skill
      send_zip DeveloperKit.skill_files, 'team-distribution-skill.zip'
    end

    private

    def kit
      DeveloperKit.new(endpoint: request.base_url,
                      params: params.permit(:platform, :build, :artifact, :trigger, :branch, :runner))
    end

    def send_zip(files, filename)
      require 'zip'
      buffer = Zip::OutputStream.write_buffer do |zip|
        files.each do |name, content|
          zip.put_next_entry(name)
          zip.write(content)
        end
      end
      send_data buffer.string, filename: filename, type: 'application/zip', disposition: 'attachment'
    end

  end
end

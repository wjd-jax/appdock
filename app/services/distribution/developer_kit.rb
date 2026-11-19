module Distribution
  class DeveloperKit
    class InvalidConfig < StandardError; end
    CHECKOUT = '3d3c42e5aac5ba805825da76410c181273ba90b1'.freeze
    PRESETS = {
      'android' => {label: 'Android / Gradle', build: ['./gradlew', 'assembleDebug'], artifact: 'app/build/outputs/apk/debug/*.apk'},
      'ios' => {label: 'iOS / Fastlane', build: ['bundle', 'exec', 'fastlane', 'build_test'], artifact: 'build/*.ipa'},
      'flutter' => {label: 'Flutter / Android', build: ['flutter', 'build', 'apk', '--debug'], artifact: 'build/app/outputs/flutter-apk/app-debug.apk'},
      'custom' => {label: '自定义构建', build: ['请填写项目实际构建命令'], artifact: 'build/*.apk'}
    }.freeze

    def self.resource(name)
      public_path = Rails.root.join('public/distribution/examples', name)
      public_path.file? ? public_path.binread : Rails.root.join('examples/team-distribution', name).binread
    end

    def self.cli
      path = Rails.root.join('public/distribution/team-release.py')
      path.file? ? path.binread : Rails.root.join('tools/team_release.py').binread
    end

    def self.skill_files
      {
        'team-distribution/SKILL.md' => resource('skill/team-distribution/SKILL.md'),
        'team-distribution/agents/openai.yaml' => resource('skill/team-distribution/agents/openai.yaml'),
        'team-distribution/scripts/team_release.py' => cli
      }
    end

    def initialize(endpoint:, params: {})
      @endpoint, @params = endpoint, params
    end

    def files
      platform = @params.fetch(:platform, 'android').to_s
      preset = PRESETS[platform] || raise(InvalidConfig, '请选择受支持的技术栈')
      command = @params.key?(:build) ? JSON.parse(@params[:build].to_s) : preset[:build]
      unless command.is_a?(Array) && command.any? && command.all? { |v| v.is_a?(String) && !v.strip.empty? && v.bytesize <= 2048 } && command.size <= 100 && !command.first.start_with?('请')
        raise InvalidConfig, '构建命令应为非空 JSON 字符串数组，例如 ["./gradlew", "assembleDebug"]'
      end
      artifact = @params.key?(:artifact) ? @params[:artifact].to_s : preset[:artifact]
      raise InvalidConfig, '产物路径应为 1–1024 个字符，且不含换行' if artifact.blank? || artifact.size > 1024 || artifact.match?(/[\r\n\x00]/)
      @trigger = @params.fetch(:trigger, 'manual').to_s
      raise InvalidConfig, '请选择手动或推送触发' unless %w[manual push].include?(@trigger)
      @branch = @trigger == 'push' ? @params.fetch(:branch, 'develop').to_s.strip : 'develop'
      if @trigger == 'push' && !(@branch.match?(/\A[A-Za-z0-9][A-Za-z0-9._\/-]{0,119}\z/) && !@branch.include?('..') && !@branch.end_with?('/', '.'))
        raise InvalidConfig, '请填写有效的 Git 分支名'
      end
      runner = @params.fetch(:runner, platform == 'ios' ? 'macOS' : 'Linux').to_s
      raise InvalidConfig, '请选择 Linux 或 macOS 内网 Runner' unless %w[Linux macOS].include?(runner)
      raise InvalidConfig, 'iOS 构建需要 macOS Runner' if platform == 'ios' && runner != 'macOS'
      config = {endpoint: @endpoint, build: command, artifact: artifact}
      output = {
        '.team-distribution.json' => JSON.pretty_generate(config) + "\n",
        'tools/team_release.py' => self.class.cli,
        'docs/team-distribution.md' => instructions(platform),
        'AGENTS.distribution.md' => self.class.resource('AGENTS.md'),
        '.github/workflows/team-distribution.yml' => github(runner),
        'ci/team-distribution.gitlab.yml' => gitlab(runner)
      }
      output['fastlane/team-distribution.Fastfile.example'] = self.class.resource('Fastfile') if platform == 'ios'
      self.class.skill_files.each { |path, content| output[".agents/skills/#{path}"] = content }
      output['distribution-kit-manifest.json'] = JSON.pretty_generate({format: 2, files: output.transform_values { |v| Digest::SHA256.hexdigest(v) }}) + "\n"
      output
    rescue JSON::ParserError
      raise InvalidConfig, '构建命令不是有效 JSON，请使用命令数组'
    end

    private

    def github(runner)
      triggers = "  workflow_dispatch:\n"
      triggers += "  push:\n    branches: [#{@branch.to_json}]\n" if @trigger == 'push'
      <<~YAML
        name: Team test distribution
        on:
        #{triggers.chomp}
        permissions:
          contents: read
        concurrency:
          group: team-distribution-${{ github.ref }}
          cancel-in-progress: false
        jobs:
          distribute:
            runs-on: [self-hosted, #{runner}, company-lan]
            timeout-minutes: 60
            steps:
              # checkout v7 requires runner >= 2.327.1
              - uses: actions/checkout@#{CHECKOUT}
                with:
                  persist-credentials: false
              - name: Build and upload
                run: python3 tools/team_release.py release > distribution-result.json
              - name: Show distribution links
                run: |
                  python3 - <<'PY'
                  import json, os
                  result = json.load(open('distribution-result.json'))
                  with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                      summary.write('## 测试包分发\\n')
                      for key in ('release_url', 'qrcode_url', 'app_url'):
                          summary.write(f'- {key}: {result[key]}\\n')
                  PY
      YAML
    end

    def gitlab(runner)
      conditions = "    - if: '$CI_PIPELINE_SOURCE == \"web\"'\n      when: manual\n"
      if @trigger == 'push'
        expression = "$CI_PIPELINE_SOURCE == \"push\" && $CI_COMMIT_BRANCH == #{@branch.to_json}"
        conditions += "    - if: #{expression.to_json}\n      when: on_success\n"
      end
      <<~YAML
        # 将本文件通过 include:local 引入现有 .gitlab-ci.yml。
        # 内网 Runner 需添加 company-lan 与 #{runner.downcase} 标签。
        team_test_distribution:
          stage: build
          tags: [company-lan, #{runner.downcase}]
          timeout: 1h
          rules:
        #{conditions.chomp}
            - when: never
          script:
            - python3 tools/team_release.py release > distribution-result.json
            - cat distribution-result.json
          artifacts:
            paths: [distribution-result.json]
            expire_in: 7 days
      YAML
    end

    def instructions(platform)
      <<~TEXT
        # 当前项目的分发接入

        技术栈：#{PRESETS.fetch(platform)[:label]}
        站点：#{@endpoint}

        先在下载目录解压、核对内容，再将需要的文件合并到业务工程根目录；不要直接覆盖已有配置、AI 规则或 CI 工作流。
        `.team-distribution.json` 只需配置站点、构建命令和产物路径，上传后自动识别应用及平台。构建命令由开发者电脑/内网 Runner 执行，平台只生成配置，不在服务端运行命令。

        ## CLI
        Python 3.8+，在业务工程根目录执行 `python3 tools/team_release.py release`。仅上传已有包用 `python3 tools/team_release.py upload <包路径>`。stdout 是真实 JSON 结果，构建日志在 stderr；成功含 release_url、qrcode_url、package_url、package_qrcode_url、app_url、file_sha256、duplicate。同产品名汇总一个链接，各平台、包标识及测试/正式环境分别有固定链接。同一环境内的版本号和构建号同时冲突时，CLI 报告 HTTP 409，确认后可通过网页覆盖。

        ## AI Skill
        接入包已含 `.agents/skills/team-distribution/`，保留其 SKILL.md、agents/openai.yaml 和 scripts/team_release.py。在支持项目 Skill 的 Codex 中重新打开工程/新建对话，然后调用 `$team-distribution 按项目配置构建并上传测试包`。其他 AI 工具按其 Skill 目录约定安装同一文件夹；不支持 Skill 时，将 AGENTS.distribution.md 的内容合并进已有项目规则。

        ## 自动化
        GitHub：核对后合并 `.github/workflows/team-distribution.yml`；Runner 注册为 self-hosted，带 #{platform == 'ios' ? 'macOS' : '所选操作系统'} 和 company-lan 标签，安装原有构建/签名环境。workflow_dispatch 入口需要工作流存在默认分支。
        GitLab：将 `ci/team-distribution.gitlab.yml` 引入现有 `.gitlab-ci.yml`：
        ```yaml
        include:
          - local: 'ci/team-distribution.gitlab.yml'
        ```
        GitLab build 阶段应存在于工程 stages；Runner 标签需匹配。当前触发模式：#{@trigger == 'push' ? "推送 #{@branch} 自动执行，同时提供手动入口" : '仅手动触发'}。本接入包不会自动注册 Runner 或启用仓库 CI。

        CI 留存 distribution-result.json；GitHub 运行摘要展示下载链接，GitLab 通过日志及 Job artifact 查看。测试包上传不需要 Token；代码托管、签名所需凭据仍沿用工程现有管理方式，不写进本配置。
        内网外的云端 AI/公共 Runner 无法直连本站，需让实际执行发生在内网。iOS 的 workspace/scheme、Fastlane lane 与 Apple 签名由工程配置，平台 HTTPS 不能替代签名授权。
      TEXT
    end
  end
end

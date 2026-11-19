---
name: team-distribution
description: 为团队内网分发站配置业务 App 的测试包构建与上传，或上传已有 IPA/APK，交付下载页、二维码与应用下载链接。用于开发者要求接入分发、打测试包或分发已构建安装包时；不用于发布应用商店或修改分发站服务器。
---

# 团队测试包分发

在业务 App 工程根目录工作，读取 `.team-distribution.json` 和工程已有构建/签名约定。若未配置，使用站点开发接入页提供的配置，或用本技能的 `scripts/team_release.py init --platform android|ios|flutter|custom` 创建模板，再核对构建命令与唯一产物路径。上传后平台按包标识和 iOS/Android 自动归类，无需预先创建应用。

- 构建并上传：`python3 <本技能目录>/scripts/team_release.py release`。
- 仅上传用户指定的现有包：`python3 <本技能目录>/scripts/team_release.py upload <文件路径>`。
- 工程已包含相同工具时，可直接使用 `python3 tools/team_release.py ...`。

命令从工程根目录执行；配置文件默认是当前目录的 `.team-distribution.json`。多个工程配置使用 `--config <配置路径>`，放在 `release` / `upload` 子命令之前。只执行用户指定业务工程的构建命令，不修改分发站配置。

示例站点 `https://apps.example.com` 仅内网可达，无需登录或上传 Token。构建在开发者电脑或内网 CI 执行，上传安装包即可。iOS 沿用工程已有签名；不提取或传递签名凭据，不更换签名来绕过构建错误。

以工具真实退出码和 JSON 为准。成功交付 `release_url`、`qrcode_url`、`app_url`、`package_url`、`package_qrcode_url`、版本/构建号与 `duplicate`。二维码字段是图片地址；`app_url` 为产品汇总页，`package_url` 为平台、包标识和业务环境对应的固定下载页。HTTP 409 表示当前环境已存在相同版本号和构建号。

构建失败、产物缺失/不唯一/未更新时先说明实际错误，修正后再执行；不上传猜测的旧包。网络失败由 CLI 最多自动重试两次；仍失败就保留错误并停止，不无限重传。遇到版本冲突时报告错误和对应环境，覆盖前须由用户明确确认。未成功上传不得编造下载地址，也不自动发群通知。

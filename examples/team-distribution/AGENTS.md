# 测试包分发约定（复制进业务 App 的项目规则）

用户要求分发测试版本时，先查看 `.team-distribution.json` 和本项目的签名/构建约定，执行 `python3 tools/team_release.py release`。已有明确产物且只需上传时，执行 `python3 tools/team_release.py upload /绝对路径/安装包.apk`（或 .ipa）。

工具失败应报告实际原因，不伪造下载链接，不擅自更换签名、不绕过 HTTPS 校验。成功后使用 JSON 返回的 `release_url`、`qrcode_url`、`app_url` 交付；重复文件返回旧版本属正常去重。上传后按包标识和平台自动归类，应用页展示最新安装包。无需选择上传目标或预建应用。

内网模式免登录、免上传 Token。iOS 签名证书和描述文件由项目原有流程管理，不写进分发配置、不输出到聊天。构建及上传在开发者电脑或内网 CI Runner 执行，分发站不读取业务源码。

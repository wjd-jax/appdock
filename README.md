# AppDock

面向可信内网团队的自托管应用分发平台，基于 [Zealot](https://github.com/tryzealot/zealot) 6.2.2 定制。支持上传 IPA/APK、自动归类应用、固定下载页、二维码、开发者接入配置与 Lark/飞书上传通知。

## 功能

- 独立上传页：拖拽上传、解析、进度、失败重试和 SHA-256 去重。
- 按包标识与平台自动归类，首次上传自动创建应用，应用页展示最新包及历史版本。
- 移动端下载页、固定应用链接与二维码。
- 开发者配置页：生成 CLI、Fastlane、GitHub/GitLab CI 接入材料。
- iOS UDID 收集入口；不会自动完成 Apple 设备注册或签名。
- 可配置 Lark/飞书群机器人上传通知，凭据加密存储。
- 可选外网下载入口：按应用展示最新版本、二维码及更新日志；访问开关由宿主机控制器执行，公网请求仅允许下载相关路径。

## 运行边界

部署示例启用 `ZEALOT_TRUSTED_LAN=true`：团队日常上传、下载和共享管理免登录。**仅在受控内网运行，不要通过端口映射或 Tunnel 暴露到公网。** 共享管理包含通知配置等操作，网络访问资格即意味着共享操作权限。底层管理员账号保留。

源码包含可选的外网下载网关和 `/access` 开关页面，但快速部署示例没有安装宿主机状态控制器、独立公网反向代理及 Tunnel。缺少控制器心跳时公网入口默认拒绝访问；仅在另行配置并验证这些组件后才能使用外网下载。不要将示例中的内网 `web` 服务直接暴露为公网入口。

iOS OTA 需要有效的 Apple 签名、设备资格及受设备信任的 HTTPS；平台无法替代这些条件。UDID 描述文件未签名。群通知会将版本信息和内网下载链接发送至你配置的群，请自行选择接收群。

## 快速部署

需要 Docker Engine 与 Docker Compose，以及能访问容器镜像仓库的网络。

```sh
git clone https://github.com/wjd-jax/appdock.git
cd appdock/deploy
cp .env.example .env
openssl rand -hex 64
```

编辑 `.env`，将生成的随机值填入 `SECRET_TOKEN`，分别设置强随机数据库密码和管理员密码，并修改 `ZEALOT_DOMAIN` 为实际内网主机名（不带协议和路径）。然后：

```sh
chmod 600 .env
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 zealot web
```

将域名在内网 DNS 或测试设备 hosts 中解析到服务器内网地址，访问 `https://你的域名/`。示例 Caddy 使用内部 CA，需要将 `deploy/data/caddy/caddy/pki/authorities/local/root.crt` 导入各测试设备并信任；iOS 还需要在证书信任设置中开启信任。若已有受信任证书，按组织已有证书方案调整 Caddy TLS 配置。不要分发 CA 私钥。

应用镜像以固定 digest 的 Zealot 6.2.2 为基础覆盖当前定制源码。`deploy/data/` 保存数据库、上传包、日志及证书；备份时同时保存数据、`.env` 和原 `SECRET_TOKEN`，否则加密通知凭据无法恢复。升级前先备份。勿把这些文件提交到 Git。

## 开发与验证

Rails 源码在仓库根目录；通用 Dockerfile 保留上游完整构建方式，`deploy/Dockerfile` 用于本项目定制镜像。开发者 CLI 为 `tools/team_release.py`，团队接入见 [团队接入](docs/团队接入.md)。

`test/team_distribution/` 包含集成检查，需要独立测试数据库、服务和测试 APK。其中 Ruby 检查要求数据库名 `zealot_verify`，不可对正式数据执行。CLI 检查使用隔离端口 18443。本次开源整理只执行静态检查，未在全新机器完成部署、未验证真实 IPA 安装或业务 CI 签名构建。

## 来源与许可证

本仓库是当前定制工作树的源码快照，基于 Zealot 6.2.2；原项目介绍保留在 [README.upstream.md](README.upstream.md)。独立仓库不代表上游官方发行版。上游版权归 icyleaf 及原贡献者所有，沿用 [MIT License](LICENSE)，完整保留原版权与许可声明。AppDock 定制内容同样以 MIT 许可证发布。

不包含实际部署凭据、证书、安装包、数据库、机器运维记录及私有部署历史。

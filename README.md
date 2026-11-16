<div align="center">
  <img src="public/distribution/appdock-logo.svg" alt="AppDock logo" width="88" height="88">
  <h1>AppDock</h1>
  <p><strong>把构建好的应用包，交到需要测试的人手里。</strong></p>
  <p>面向可信内网团队的自托管 iOS / Android 应用分发平台。</p>
  <p>
    <a href="#快速开始">快速开始</a> ·
    <a href="#核心能力">核心能力</a> ·
    <a href="#安全与部署边界">安全与部署边界</a> ·
    <a href="docs/团队接入.md">团队接入指南</a>
  </p>
</div>

---

AppDock 基于 [Zealot 6.2.2](https://github.com/tryzealot/zealot) 定制，为团队提供安装包上传、版本管理、二维码下载和构建接入。测试人员在内网打开下载页即可获取最新可用版本；开发人员可通过网页、命令行或现有 CI 流程上传 IPA / APK。

> [!IMPORTANT]
> 默认部署为**可信内网模式**：上传、下载和共享管理操作无需登录。只应部署在受控网络内，不能把示例中的内网服务直接映射到公网。

## 核心能力

| 场景 | 能力 |
| --- | --- |
| 上传安装包 | 拖拽上传 IPA / APK，解析包信息，显示进度；按 SHA-256 识别重复文件。首次上传可自动创建应用。 |
| 分发测试版本 | 按产品汇总 iOS / Android 包，提供产品短链接、按平台与包标识的固定下载页及二维码；记录文件下载请求次数。 |
| 区分业务环境 | 上传时选择测试或正式环境，默认测试环境；既有版本归为测试环境，下载及管理页可按环境筛选历史版本。 |
| 接入开发流程 | 开发者页面提供 AI 接入指令、Python CLI，以及可选的 Fastlane 和 GitHub / GitLab CI 材料。 |
| 团队通知 | 可配置 Lark / 飞书群机器人，在成功上传新版本后发送版本信息和下载链接。 |
| iOS 设备收集 | 提供 UDID 收集入口，供签名和设备登记流程使用。 |

项目还包含**可选的外网下载网关**，但它需要单独部署宿主机访问状态控制器、独立公网反向代理和 Tunnel；下方快速开始不会启用这些组件。

## 快速开始

### 1. 准备环境

准备 Docker Engine、Docker Compose、可访问容器镜像仓库的网络，以及一个解析到服务器内网地址的域名。下载源码并创建本地配置：

```sh
git clone https://github.com/wjd-jax/appdock.git
cd appdock/deploy
cp .env.example .env
openssl rand -hex 64
```

编辑 `deploy/.env`：将最后一条命令生成的随机值填入 `SECRET_TOKEN`，为 `APPDOCK_POSTGRES_PASSWORD` 和 `APPDOCK_ADMIN_PASSWORD` 设置各自独立的强密码，并把 `APPDOCK_DOMAIN` 改为实际内网域名（不含协议或路径）。

### 2. 启动服务

```sh
chmod 600 .env
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 appdock web
```

服务启动后，在内网访问 `https://<APPDOCK_DOMAIN>/`。部署由 PostgreSQL、AppDock 和 Caddy 组成；首次构建会下载固定版本的基础镜像并编译前端资源，所需时间取决于网络与机器性能。

### 3. 信任内网 HTTPS 证书

示例 Caddy 使用内部 CA。将 `deploy/data/caddy/caddy/pki/authorities/local/root.crt` 导入测试设备并设为受信任；iOS 设备还需在证书信任设置中启用完全信任。已有组织证书时，可调整 `deploy/Caddyfile` 使用现有证书。**不要分发 CA 私钥。**

随后打开 `/upload` 上传测试包，或打开 `/developers` 查看适合业务工程的接入说明。完整使用流程见[团队接入指南](docs/团队接入.md)。

## 安全与部署边界

- `deploy/compose.yaml` 启用 `APPDOCK_TRUSTED_LAN=true`。能访问内网服务的人也能执行共享管理操作，包括修改通知配置；请通过网络准入控制访问范围。
- 快速部署只提供内网入口。源码中的 `/access` 页面和外网下载网关依赖额外的宿主机控制器；缺少控制器心跳时，公网入口默认拒绝访问。不要直接向公网开放 `web` 服务。
- iOS OTA 安装仍需有效的 Apple 签名、设备资格和设备信任的 HTTPS。UDID 收集不会自动完成 Apple 设备注册或签名，其描述文件未签名。
- 群机器人会把版本信息和内网下载链接发送到所配置的群。配置通知前，请确认该群的成员范围。
- `deploy/data/` 存放数据库、安装包、日志及证书。升级或迁移前，一并备份该目录、`deploy/.env` 和原 `SECRET_TOKEN`；缺少密钥将无法恢复已加密的通知凭据。不要将数据和凭据提交到 Git。

已有 Zealot / AppDock 部署应先阅读[命名与旧部署升级说明](docs/AppDock命名迁移.md)，核对数据库、Compose 项目名、数据目录和登录兼容配置，再执行迁移。新配置使用 `APPDOCK_*`，并兼容旧 `ZEALOT_*` 环境变量。

## 开发与验证

Rails 应用位于仓库根目录。`deploy/Dockerfile` 是快速部署所用的定制镜像构建入口；根目录 `Dockerfile` 保留上游完整构建方式。开发者 CLI 位于 [`tools/team_release.py`](tools/team_release.py)。

隔离验收入口位于 [`test/team_distribution/`](test/team_distribution/)。请使用与正式部署**不同目录的全新仓库副本**，确保 `deploy/data/` 是空目录；还需独立的 Compose 项目、回环端口及测试 APK。**不要在正式部署目录或正式数据上运行。**准备 `../checks/sample.apk` 和随机测试凭据后，在该副本的 `deploy/.env` 设置：

```dotenv
APPDOCK_DOMAIN=apps.example.com
COMPOSE_PROJECT_NAME=appdock-acceptance-example
APPDOCK_HTTP_BIND=127.0.0.1:18080
APPDOCK_HTTPS_BIND=127.0.0.1:18443
```

保留 `.env.example` 中其余必需项并填入随机值，然后从仓库根目录运行：

```sh
docker build -f deploy/Dockerfile -t appdock:acceptance-20261116 .
docker compose -f deploy/compose.yaml -f test/team_distribution/compose.acceptance.yaml up -d --no-build
bash test/team_distribution/run_acceptance.sh
docker compose -f deploy/compose.yaml -f test/team_distribution/compose.acceptance.yaml down
```

若默认验收端口被占用，可同时修改 `APPDOCK_HTTP_BIND`、`APPDOCK_HTTPS_BIND`，并设置 `APPDOCK_ACCEPTANCE_DOMAIN=apps.example.com:<HTTPS 端口>`；验收脚本会读取实际映射端口。

验收脚本检查隔离配置、Rails 功能、上传与下载、权限边界、HTTPS 入口及 CLI。公开仓库曾在隔离环境完成完整镜像构建、空库首次启动及该套验收；真实签名 IPA 的设备安装、业务工程 CI 签名构建和外网 Tunnel 联通仍需在目标环境单独验证。

## 项目来源与许可

AppDock 是基于 Zealot 6.2.2 的独立定制项目，**不是 Zealot 官方发行版**。上游项目说明保留在 [README.upstream.md](README.upstream.md)。上游版权归 icyleaf 及原贡献者所有；仓库保留原版权声明，并按 [MIT License](LICENSE) 发布定制内容。

本仓库不包含实际部署凭据、证书、安装包、数据库或私有机器的运维记录。

# AppDock 命名与旧部署升级

当前源码、页面、Rails 命名空间、任务、容器和默认数据库统一使用 AppDock / appdock。上游版权、真实依赖地址及 `README.upstream.md` 保留 Zealot 来源。

## 配置兼容

新配置使用 `APPDOCK_*`。Rails 启动时兼容对应的 `ZEALOT_*`，同时提供时以新变量为准，包括显式空值。上传 CLI 支持 `APPDOCK_TOKEN`，兼容旧 `ZEALOT_TOKEN`；调用构建命令时不向子进程传递这两个令牌变量。

任务入口使用 `bin/rails appdock:upgrade`、`appdock:precheck` 等，旧 `zealot:*` 暂保留兼容别名。旧格式备份文件仍可识别。

## 升级既有部署

新部署的数据库和 Compose 项目均为 `appdock`。旧部署不能直接套用新 Compose 启动：应先备份并验证恢复，停止旧应用、后台任务和维护任务，保留原数据目录、上传包及 Rails 密钥，再迁移数据库名和运行配置。

如果暂时沿用原数据库，请将 Compose 的 `POSTGRES_DB`、健康检查和应用的 `APPDOCK_POSTGRES_DB_NAME` 同步设为现有数据库名。PostgreSQL 对已有数据目录不会因为修改 `POSTGRES_DB` 自动改名。

为保持旧登录和渠道下载授权，可在既有部署设置：

```dotenv
APPDOCK_SESSION_KEY=_zealot_session
APPDOCK_CHANNEL_COOKIE_PREFIX=zealot_app_channel_auth_
```

新部署默认采用 AppDock Cookie 名称。切换 Cookie 名称会要求用户重新登录或重新输入渠道密码。

升级后检查上传、去重、下载、管理、备份恢复和公网访问限制。自建公网控制器还需同步运行目录、服务名称及维护任务；公开部署模板不包含机器专用控制器。

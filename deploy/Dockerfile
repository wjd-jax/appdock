FROM ghcr.io/tryzealot/zealot@sha256:72e80a1823aa09c213b9e29752042166dd8f689a511bb55bfde079a57a6764de
ARG VCS_REF=working-tree
LABEL org.opencontainers.image.revision="$VCS_REF"
# 固定基础镜像提供 Ruby 依赖及未改动的上游编译资产。
# 整体复制运行源码，新增控制器、迁移或视图不会遗漏；定制 UI 资产独立于上游打包链。
COPY app/ /app/app/
COPY config/ /app/config/
COPY lib/ /app/lib/
COPY db/migrate/ /app/db/migrate/
COPY public/distribution/ /app/public/distribution/
COPY tools/team_release.py /app/public/distribution/team-release.py
COPY examples/team-distribution/ /app/public/distribution/examples/

FROM ghcr.io/tryzealot/zealot@sha256:72e80a1823aa09c213b9e29752042166dd8f689a511bb55bfde079a57a6764de AS assets
# Same build tools and locked dependencies as the upstream full Dockerfile.
RUN apk add --no-cache nodejs npm && npm install -g pnpm@10.22.0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY app/ /app/app/
RUN pnpm run build && pnpm run build:css

FROM ghcr.io/tryzealot/zealot@sha256:72e80a1823aa09c213b9e29752042166dd8f689a511bb55bfde079a57a6764de
ARG VCS_REF=working-tree
LABEL org.opencontainers.image.revision="$VCS_REF"
LABEL org.opencontainers.image.title="AppDock" org.opencontainers.image.source="https://github.com/wjd-jax/appdock"
# Remove inherited source/entry points so renamed classes are not loaded twice.
RUN rm -rf /app/app /app/config /app/lib /app/db /app/tmp/cache /app/public/assets \
    /etc/cont-init.d/20-init-zealot /etc/cont-init.d/30-zealot-upgrade \
    /etc/cont-init.d/31-zealot-precheck /etc/services.d/zealot /etc/logrotate.d/zealot
COPY app/ /app/app/
COPY config/ /app/config/
COPY lib/ /app/lib/
COPY db/ /app/db/
COPY docker/rootfs/ /
COPY --from=assets /app/app/assets/builds/ /app/app/assets/builds/
COPY public/distribution/ /app/public/distribution/
COPY public/loading.html public/favicon.ico /app/public/
COPY swagger/ /app/swagger/
COPY tools/team_release.py /app/public/distribution/team-release.py
COPY examples/team-distribution/ /app/public/distribution/examples/
# JS/CSS were built above; only fingerprint/package assets in the Ruby stage.
RUN SECRET_KEY_BASE=precompile_placeholder APPDOCK_SENTRY_DISABLE=true bundle exec ruby -e 'require "./config/boot"; require "rake"; require "./config/application"; Rails.application.load_tasks; %w[javascript:build css:build].each { |n| Rake::Task[n].clear if Rake::Task.task_defined?(n) }; Rake::Task["assets:precompile"].invoke'

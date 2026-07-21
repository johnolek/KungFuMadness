# syntax=docker/dockerfile:1
# check=error=true;skip=SecretsUsedInArgOrEnv
# (RAILS_MASTER_KEY rides through a build ARG — the standard Rails Dockerfile
# shape, and what Coolify injects. BuildKit's SecretsUsedInArgOrEnv lint would
# fail the whole build under check=error, so that single rule is skipped.)

# Production image for Coolify (Dockerfile build). JS (esbuild + esbuild-svelte)
# and CSS (dart-sass) compile via yarn during assets:precompile in the build
# stage; the final image ships no Node and no node_modules.
#
#   docker build -t kung_fu_madness .
#   docker run -d -p 3000:3000 \
#     -e RAILS_MASTER_KEY=<config/master.key> \
#     -e DATABASE_URL=<postgres url> \
#     -e WEBAUTHN_RP_ID=... -e WEBAUTHN_ORIGIN=https://... \
#     --name kung_fu_madness kung_fu_madness
#
# No Active Storage attachments exist in this app, so there is NO persistent
# volume to mount — all state lives in Postgres.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. No libvips: this app has no image processing.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (no libvips; esbuild/sass/svelte are
# prebuilt and need no native node compilation, so no node-gyp/python either).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disables parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Install JavaScript build toolchain (build stage only; stripped from the final image).
ARG NODE_VERSION=24.5.0
ARG YARN_VERSION=1.22.22
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    npm install -g yarn@$YARN_VERSION && \
    rm -rf /tmp/node-build-master

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets (runs yarn build + yarn build:css via js/cssbundling) without
# requiring the real RAILS_MASTER_KEY, then strip Node modules from the image.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && rm -rf node_modules

# Record the deployed commit (Coolify passes SOURCE_COMMIT).
ARG SOURCE_COMMIT=unknown
RUN echo "${SOURCE_COMMIT}" > REVISION

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

# Run Solid Queue (with its recurring scheduler: the per-minute bot tick,
# daily rust/expire jobs) inside Puma, and default to two Puma workers.
# production.rb already logs to STDOUT unconditionally.
ENV SOLID_QUEUE_IN_PUMA="1" \
    WEB_CONCURRENCY="2"

EXPOSE 3000

HEALTHCHECK --interval=5s --timeout=5s --start-period=20s --retries=60 \
  CMD curl -f http://localhost:3000/up || exit 1

# Prepare the database on boot (runs migrations, incl. Solid Queue/Cable tables),
# then run Puma, which supervises Solid Queue (workers + dispatcher + recurring
# scheduler) in-process.
CMD ["bash", "-c", "rm -f tmp/pids/server.pid && bundle exec rails db:prepare && exec bundle exec puma -C config/puma.rb"]

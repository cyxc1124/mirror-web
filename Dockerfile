# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS node
FROM ruby:3.2-slim-bookworm AS dependencies
COPY --from=node /usr/local/ /usr/local/
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git libatomic1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/mirror-web
COPY Gemfile Gemfile.lock package.json package-lock.json ./
COPY _node_module_patch/ ./_node_module_patch/
RUN sed -i "s@https://mirrors.tuna.tsinghua.edu.cn/rubygems/@https://rubygems.org/@g" Gemfile Gemfile.lock \
    && bundler_version="$(sed -n '/BUNDLED WITH/{n;s/ //g;p;}' Gemfile.lock)" \
    && gem install bundler --version "$bundler_version" --no-document \
    && bundle config set --local path /usr/local/bundle \
    && bundle config set --local frozen true \
    && bundle install --jobs 4 --retry 3 \
    && npm ci --include=dev \
    && mv node_modules /node_modules

FROM dependencies AS builder
COPY . .
# Use the public RubyGems endpoint consistently with the installed lockfile.
RUN sed -i "s@https://mirrors.tuna.tsinghua.edu.cn/rubygems/@https://rubygems.org/@g" Gemfile Gemfile.lock \
    && mkdir -p /site && chown 10001:10001 /site
COPY --chmod=755 container/build-site.sh /usr/local/bin/build-site
ENV LANG=C.UTF-8 JEKYLL_ENV=production VITE_RUBY_VITE_BIN_PATH=/node_modules/.bin/vite HOME=/tmp
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/build-site"]
CMD ["/site"]

FROM builder AS site
ARG SITE_CONFIG=container/site-production.yml
RUN SITE_CONFIG="${SITE_CONFIG}" build-site /site

# Build the extra directory-index module against the exact official NGINX version.
# njs and envsubst are already supplied by the official image.
FROM nginx:1.30.5-trixie AS nginx-modules
ADD --checksum=sha256:6c20565aa2325cb82216ae804f4a4ff1875179014759a381c42ddc8e11c4906d \
    https://nginx.org/download/nginx-1.30.5.tar.gz /tmp/nginx.tar.gz
ADD --checksum=sha256:c3dd84d8ba0b8daeace3041ef5987e3fb96e9c7c17df30c9ffe2fe3aa2a0ca31 \
    https://codeload.github.com/aperezdc/ngx-fancyindex/tar.gz/refs/tags/v0.5.2 /tmp/fancyindex.tar.gz
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libpcre2-dev zlib1g-dev \
    && tar -xzf /tmp/nginx.tar.gz -C /tmp \
    && tar -xzf /tmp/fancyindex.tar.gz -C /tmp \
    && cd "/tmp/nginx-${NGINX_VERSION}" \
    && ./configure --with-compat --add-dynamic-module=/tmp/ngx-fancyindex-0.5.2 \
    && make -j"$(nproc)" modules \
    && mkdir /out \
    && strip -o /out/ngx_http_fancyindex_module.so objs/ngx_http_fancyindex_module.so

FROM nginx:1.30.5-trixie AS web
RUN mkdir -p /srv/site /data/mirrors /etc/mirror-web
COPY --from=nginx-modules /out/ngx_http_fancyindex_module.so /usr/lib/nginx/modules/
COPY --from=site /site/ /srv/site/
COPY container/nginx.conf.template /etc/mirror-web/nginx.conf.template
COPY --chmod=755 container/serve.sh /usr/local/bin/serve-mirrors
USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/local/bin/serve-mirrors"]

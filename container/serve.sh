#!/bin/sh
set -eu
TUNASYNC_MANAGER_URL=${TUNASYNC_MANAGER_URL:-http://127.0.0.1:14242}
TUNASYNC_MANAGER_URL=${TUNASYNC_MANAGER_URL%/}
if ! printf '%s' "$TUNASYNC_MANAGER_URL" | grep -Eq '^https?://([a-zA-Z0-9._-]+|\[[0-9a-fA-F:]+\])(:[0-9]+)?$'; then
    printf 'TUNASYNC_MANAGER_URL must be an HTTP(S) origin without a path.\n' >&2
    exit 1
fi
export TUNASYNC_MANAGER_URL
envsubst '${TUNASYNC_MANAGER_URL}' < /etc/mirror-web/nginx.conf.template > /tmp/nginx.conf
exec nginx -c /tmp/nginx.conf -g 'daemon off;'

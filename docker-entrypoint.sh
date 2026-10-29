#!/bin/sh
set -e

# /data is a host bind mount that existing deployments created while the app still ran
# as root — hand it to the unprivileged `node` user, then drop privileges for good.
# If the container is already started as a non-root user (`user:` in compose), skip.
if [ "$(id -u)" = "0" ]; then
  mkdir -p /data
  chown -R node:node /data
  exec setpriv --reuid=node --regid=node --init-groups "$@"
fi

exec "$@"

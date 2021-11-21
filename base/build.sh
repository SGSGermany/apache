#!/bin/bash
# Apache
# An Apache container with an improved configuration structure.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/../container.env" ] && source "$BUILD_DIR/../container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$BASE_TAGS")
DEFAULT_TAG="${DEFAULT_TAGS%% *}"

APACHE_MODULES=(
    "mpm_event"
    "authn_file"
    "authn_core"
    "authz_host"
    "authz_groupfile"
    "authz_user"
    "authz_core"
    "auth_basic"
    "reqtimeout"
    "mime"
    "log_config"
    "headers"
    "http2"
    "rewrite"
    "setenvif"
    "unixd"
    "autoindex"
    "dir"
    "alias"
)

APACHE_CONFIGS=(
    "charset"
    "connection"
    "errors"
    "htaccess"
    "lookups"
    "security"
    "ssl"
    "ssl-ocsp-stapling"
    "ssl-security"
)

echo + "CONTAINER=\"\$(buildah from $IMAGE:$DEFAULT_TAG)\""
CONTAINER="$(buildah from "$IMAGE:$DEFAULT_TAG")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rm -rf …/var/www/html"
rm -rf "$MOUNT/var/www/html"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

cmd buildah run "$CONTAINER" -- \
    adduser -u 65536 -s "/sbin/nologin" -D -h "/usr/local/apache2" -H apache2

cmd buildah run "$CONTAINER" -- \
    apk add --virtual .apache-run-deps \
        inotify-tools \
        openssl

echo + "buildah run $CONTAINER -- sh -c \"a2querymod | xargs a2dismod\""
buildah run "$CONTAINER" -- \
    sh -c "a2querymod | xargs a2dismod"

cmd buildah run "$CONTAINER" -- \
    a2enmod "${APACHE_MODULES[@]}"

echo + "buildah run $CONTAINER -- sh -c \"a2queryconf | xargs a2disconf\""
buildah run "$CONTAINER" -- \
    sh -c "a2queryconf | xargs a2disconf"

cmd buildah run "$CONTAINER" -- \
    a2enconf "${APACHE_CONFIGS[@]}"

cmd buildah config \
    --entrypoint '[ "/entrypoint.sh" ]' \
    --cmd "httpd-foreground" \
    "$CONTAINER"

cmd buildah config --volume "/var/www/html-" "$CONTAINER"

cmd buildah config \
    --volume "/etc/apache2/ssl" \
    --volume "/var/log/apache2" \
    --volume "/var/www" \
    "$CONTAINER"

cmd buildah config \
    --port "80/tcp" \
    --port "443/tcp" \
    "$CONTAINER"

echo + "APACHE_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$HTTPD_VERSION\"')\""
APACHE_VERSION="$(buildah run "$CONTAINER" -- /bin/sh -c 'echo "$HTTPD_VERSION"')"

cmd buildah config \
    --annotation org.opencontainers.image.title="Apache" \
    --annotation org.opencontainers.image.description="An Apache container with an improved configuration structure." \
    --annotation org.opencontainers.image.version="$APACHE_VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/apache" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$REGISTRY/$OWNER/$IMAGE:$DEFAULT_TAG" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$IMAGE:$DEFAULT_TAG")" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done

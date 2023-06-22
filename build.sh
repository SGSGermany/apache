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
shopt -s nullglob

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

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

echo + "CONTAINER=\"\$(buildah from $BASE_IMAGE)\""
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

cmd buildah run "$CONTAINER" -- \
    adduser -u 65536 -s "/sbin/nologin" -D -h "/usr/local/apache2" -H apache2

cmd buildah run "$CONTAINER" -- \
    apk add --virtual .apache-run-deps \
        inotify-tools \
        openssl

echo + "TEMP_DIR=\"\$(mktemp -d)\""
TEMP_DIR="$(mktemp -d)"

echo + "cp -t $TEMP_DIR/ …/usr/local/apache2/conf/{magic,mime.types}"
cp -t "$TEMP_DIR/" \
    "$MOUNT/usr/local/apache2/conf/magic" \
    "$MOUNT/usr/local/apache2/conf/mime.types"

echo + "rm -rf …/usr/local/apache2/conf"
rm -rf "$MOUNT/usr/local/apache2/conf"

echo + "rm -rf …/usr/local/apache2/htdocs"
rm -rf "$MOUNT/usr/local/apache2/htdocs"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

echo + "rsync -v -rl $TEMP_DIR/ …/etc/apache2/"
rsync -v -rl "$TEMP_DIR/" "$MOUNT/etc/apache2/"

cmd rm -rf "$TEMP_DIR"

for MODULE_PATH in "$MOUNT/usr/local/apache2/modules/mod_"*".so"; do
    MODULE="$(basename "$MODULE_PATH" ".so")"
    MODULE="${MODULE:4}"

    echo + "echo \"LoadModule ${MODULE}_module /usr/local/apache2/modules/mod_$MODULE.so\" > …/etc/apache2/mods-available/$MODULE.load"
    echo "LoadModule ${MODULE}_module /usr/local/apache2/modules/mod_$MODULE.so" \
        > "$MOUNT/etc/apache2/mods-available/$MODULE.load"
done

cmd buildah run "$CONTAINER" -- \
    a2enmod "${APACHE_MODULES[@]}"

cmd buildah run "$CONTAINER" -- \
    a2enconf "${APACHE_CONFIGS[@]}"

cmd buildah config \
    --port "80/tcp" \
    --port "443/tcp" \
    "$CONTAINER"

cmd buildah config \
    --volume "/etc/apache2/ssl" \
    --volume "/var/log/apache2" \
    --volume "/var/www" \
    "$CONTAINER"

cmd buildah config \
    --entrypoint '[ "/entrypoint.sh" ]' \
    --cmd "httpd-foreground" \
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
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done

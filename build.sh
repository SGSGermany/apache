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
export LC_ALL=C.UTF-8
shopt -s nullglob

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/common-traps.sh.inc"
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-alpine.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

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

git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

con_build --tag "$IMAGE-base" \
    --from "$BASE_IMAGE" --check-from "$MERGE_IMAGE_BASE_IMAGE_PATTERN" \
    "$BUILD_DIR/vendor/$MERGE_IMAGE_BUD_CONTEXT" "./vendor/$MERGE_IMAGE_BUD_CONTEXT"

echo + "CONTAINER=\"\$(buildah from $(quote "$IMAGE-base"))\"" >&2
CONTAINER="$(buildah from "$IMAGE-base")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

user_add "$CONTAINER" apache2 65536 "/usr/local/apache2"

pkg_install "$CONTAINER" --virtual .apache-run-deps \
    inotify-tools \
    openssl

echo + "MIME_TMP_DIR=\"\$(mktemp -d)\"" >&2
MIME_TMP_DIR="$(mktemp -d)"

trap_exit rm -rf "$MIME_TMP_DIR"

echo + "cp -t '\$MIME_TMP_DIR/' …/usr/local/apache2/conf/{magic,mime.types}" >&2
cp -t "$MIME_TMP_DIR/" \
    "$MOUNT/usr/local/apache2/conf/magic" \
    "$MOUNT/usr/local/apache2/conf/mime.types"

echo + "rm -rf …/usr/local/apache2/conf" >&2
rm -rf "$MOUNT/usr/local/apache2/conf"

echo + "rm -rf …/usr/local/apache2/htdocs" >&2
rm -rf "$MOUNT/usr/local/apache2/htdocs"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

echo + "rsync -v -rl '\$MIME_TMP_DIR/' …/etc/apache2/" >&2
rsync -v -rl "$MIME_TMP_DIR/" "$MOUNT/etc/apache2/"

for MODULE_PATH in "$MOUNT/usr/local/apache2/modules/mod_"*".so"; do
    MODULE="$(basename "$MODULE_PATH" ".so")"
    MODULE="${MODULE:4}"

    echo + "echo \"LoadModule ${MODULE}_module /usr/local/apache2/modules/mod_$MODULE.so\"" \
        "> $(quote "…/etc/apache2/mods-available/$MODULE.load")" >&2
    echo "LoadModule ${MODULE}_module /usr/local/apache2/modules/mod_$MODULE.so" \
        > "$MOUNT/etc/apache2/mods-available/$MODULE.load"
done

cmd buildah run "$CONTAINER" -- \
    a2enmod "${APACHE_MODULES[@]}"

cmd buildah run "$CONTAINER" -- \
    a2enconf "${APACHE_CONFIGS[@]}"

cleanup "$CONTAINER"

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
    --cmd '[ "httpd-foreground" ]' \
    "$CONTAINER"

echo + "APACHE_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$HTTPD_VERSION\"')\"" >&2
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

con_commit "$CONTAINER" "${TAGS[@]}"

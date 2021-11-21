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
[ -f "$BUILD_DIR/../container.env" ] && source "$BUILD_DIR/../container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$DEFAULT_TAGS")

APACHE_MODULES=(
    "mpm_event"
    "authn_file"
    "authn_core"
    "authz_host"
    "authz_groupfile"
    "authz_user"
    "authz_core"
    "access_compat"
    "auth_basic"
    "reqtimeout"
    "filter"
    "mime"
    "log_config"
    "env"
    "headers"
    "setenvif"
    "version"
    "unixd"
    "status"
    "autoindex"
    "dir"
    "alias"
)

APACHE_CONFIGS=(
    "cgi-bin"
    "errors"
    "htaccess"
    "htdocs"
)

echo + "CONTAINER=\"\$(buildah from $BASE_IMAGE)\""
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "TEMP_DIR=\"\$(mktemp -d)\""
TEMP_DIR="$(mktemp -d)"

echo + "cp -t $TEMP_DIR/ …/usr/local/apache2/conf/{magic,mime.types}"
cp -t "$TEMP_DIR/" \
    "$MOUNT/usr/local/apache2/conf/magic" \
    "$MOUNT/usr/local/apache2/conf/mime.types"

echo + "rm -rf …/usr/local/apache2/conf"
rm -rf "$MOUNT/usr/local/apache2/conf"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

echo + "rsync -v -rl $TEMP_DIR/ …/etc/apache2/"
rsync -v -rl "$TEMP_DIR/" "$MOUNT/etc/apache2/"

echo + "mv …/usr/local/apache2/htdocs …/var/www/html"
mv "$MOUNT/usr/local/apache2/htdocs" "$MOUNT/var/www/html"

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

cmd buildah config --volume "/var/www/html" "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done

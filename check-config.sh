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
    echo + "$@" >&2
    "$@"
    return $?
}

prepare_local_conf() {
    if [ ! -d "$TEMP_DIR/raw/local/$(dirname "$2")" ]; then
        echo + "mkdir \$TEMP_DIR/raw/local/$(dirname "$2")" >&2
        mkdir "$TEMP_DIR/raw/local/$(dirname "$2")"

        echo + "mkdir \$TEMP_DIR/clean/local/$(dirname "$2")" >&2
        mkdir "$TEMP_DIR/clean/local/$(dirname "$2")"
    fi

    echo + "cp ./base-conf/$1 \$TEMP_DIR/raw/local/$2" >&2
    cp "$BUILD_DIR/base-conf/$1" "$TEMP_DIR/raw/local/$2"

    echo + "clean_conf \$TEMP_DIR/raw/local/$2 \$TEMP_DIR/clean/local/$2" >&2
    clean_conf "$TEMP_DIR/raw/local/$2" "$TEMP_DIR/clean/local/$2"
}

prepare_upstream_conf() {
    if [ ! -d "$TEMP_DIR/raw/upstream/$(dirname "$2")" ]; then
        echo + "mkdir \$TEMP_DIR/raw/upstream/$(dirname "$2")" >&2
        mkdir "$TEMP_DIR/raw/upstream/$(dirname "$2")"

        echo + "mkdir \$TEMP_DIR/clean/upstream/$(dirname "$2")" >&2
        mkdir "$TEMP_DIR/clean/upstream/$(dirname "$2")"
    fi

    echo + "cp …/$1 \$TEMP_DIR/raw/upstream/$2" >&2
    cp "$MOUNT/$1" "$TEMP_DIR/raw/upstream/$2"

    echo + "clean_conf \$TEMP_DIR/raw/upstream/$2 \$TEMP_DIR/clean/upstream/$2" >&2
    clean_conf "$TEMP_DIR/raw/upstream/$2" "$TEMP_DIR/clean/upstream/$2"
}

clean_conf() {
    sed -e 's/^\([^#]*\)#.*$/\1/' -e '/^\s*$/d' "$1" > "$2"
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

if [ ! -d "$BUILD_DIR/base-conf" ]; then
    echo "Base configuration directory not found" >&2
    exit 1
fi

echo + "CONTAINER=\"\$(buildah from $BASE_IMAGE)\"" >&2
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "TEMP_DIR=\"\$(mktemp -d)\"" >&2
TEMP_DIR="$(mktemp -d)"

echo + "mkdir \$TEMP_DIR/{raw,clean}{,/{local,upstream}}" >&2
mkdir \
    "$TEMP_DIR/raw" "$TEMP_DIR/raw/local" "$TEMP_DIR/raw/upstream" \
    "$TEMP_DIR/clean" "$TEMP_DIR/clean/local" "$TEMP_DIR/clean/upstream"

# Apache config
prepare_local_conf "httpd.conf" "httpd.conf"
for FILE in "$BUILD_DIR/base-conf/extra/"*".conf"; do
    prepare_local_conf "extra/$(basename "$FILE")" "extra/$(basename "$FILE")"
done

prepare_upstream_conf "usr/local/apache2/conf/httpd.conf" "httpd.conf"
for FILE in "$MOUNT/usr/local/apache2/conf/extra/"*".conf"; do
    prepare_upstream_conf "usr/local/apache2/conf/extra/$(basename "$FILE")" "extra/$(basename "$FILE")"
done

# diff configs
echo + "diff -q -r \$TEMP_DIR/clean/local/ \$TEMP_DIR/clean/upstream/" >&2
if ! diff -q -r "$TEMP_DIR/clean/local/" "$TEMP_DIR/clean/upstream/" > /dev/null; then
    ( cd "$TEMP_DIR/raw" ; diff -u -r ./local/ ./upstream/ )
    exit 1
fi

echo + "rm -rf \$TEMP_DIR" >&2
rm -rf "$TEMP_DIR"

cmd buildah rm "$CONTAINER"

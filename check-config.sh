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
source "$CI_TOOLS_PATH/helper/chkconf.sh.inc"

chkconf_clean() {
    sed -e 's/^\([^#]*\)#.*$/\1/' -e '/^\s*$/d' "$1" > "$2"
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

TAG="${TAGS%% *}"

# check local image storage
echo + "IMAGE_ID=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE:$TAG"))\"" >&2
IMAGE_ID="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE:$TAG" 2> /dev/null || true)"

if [ -z "$IMAGE_ID" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG': No image with this tag found" >&2
    exit 1
fi

echo + "MERGE_IMAGE=\"\$(podman image inspect --format '{{.Id}}' $(quote "localhost/$IMAGE-base"))\"" >&2
MERGE_IMAGE="$(podman image inspect --format '{{.Id}}' "localhost/$IMAGE-base" 2> /dev/null || true)"

if [ -z "$MERGE_IMAGE" ]; then
    echo "Failed to check base config of image 'localhost/$IMAGE:$TAG':" \
        "Invalid intermediate image 'localhost/$IMAGE-base': No image with this tag found" >&2
    exit 1
fi

# prepare image for diffing
echo + "CONTAINER=\"\$(buildah from $(quote "$MERGE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$MERGE_IMAGE")"

trap_exit buildah rm "$CONTAINER"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "CHKCONF_DIR=\"\$(mktemp -d)\"" >&2
CHKCONF_DIR="$(mktemp -d)"

trap_exit rm -rf "$CHKCONF_DIR"

LOCAL_FILES=()
UPSTRAM_FILES=()

# Apache config
LOCAL_FILES+=( "httpd.conf" "httpd.conf" )
for FILE in "$BUILD_DIR/base-conf/extra/"*".conf"; do
    LOCAL_FILES+=( "extra/$(basename "$FILE")" "extra/$(basename "$FILE")" )
done

UPSTREAM_FILES+=( "usr/local/apache2/conf/httpd.conf" "httpd.conf" )
for FILE in "$MOUNT/usr/local/apache2/conf/extra/"*".conf"; do
    UPSTREAM_FILES+=( "usr/local/apache2/conf/extra/$(basename "$FILE")" "extra/$(basename "$FILE")" )
done

# diff configs
chkconf_prepare \
    --local "$BUILD_DIR/base-conf" "./base-conf" \
    "$CHKCONF_DIR" "/tmp/…" \
    "${LOCAL_FILES[@]}"

chkconf_prepare \
    --upstream "$MOUNT" "…" \
    "$CHKCONF_DIR" "/tmp/…" \
    "${UPSTREAM_FILES[@]}"

chkconf_diff "$CHKCONF_DIR" "/tmp/…"

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

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

IMAGE_ID="$(podman pull "$BASE_IMAGE" || true)"
if [ -z "$IMAGE_ID" ]; then
    echo "Failed to pull image '$BASE_IMAGE': No image with this tag found" >&2
    exit 1
fi

APACHE_VERSION="$(podman image inspect --format '{{range .Config.Env}}{{printf "%q\n" .}}{{end}}' "$BASE_IMAGE" \
    | sed -ne 's/^"HTTPD_VERSION=\(.*\)"$/\1/p')"
if [ -z "$APACHE_VERSION" ]; then
    echo "Unable to read image's env variable 'HTTPD_VERSION': No such variable" >&2
    exit 1
elif ! [[ "$APACHE_VERSION" =~ ^([0-9]+:)?([0-9]+)\.([0-9]+)\.([0-9]+)([+~-]|$) ]]; then
    echo "Unable to read image's env variable 'HTTPD_VERSION': '$APACHE_VERSION' is no valid version" >&2
    exit 1
fi

APACHE_VERSION="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.${BASH_REMATCH[4]}"
APACHE_VERSION_MINOR="${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
APACHE_VERSION_MAJOR="${BASH_REMATCH[2]}"

TAG_DATE="$(date -u +'%Y%m%d%H%M')"

DEFAULT_TAGS=(
    "v$APACHE_VERSION-default" "v$APACHE_VERSION-default_$TAG_DATE"
    "v$APACHE_VERSION_MINOR-default" "v$APACHE_VERSION_MINOR-default_$TAG_DATE"
    "v$APACHE_VERSION_MAJOR-default" "v$APACHE_VERSION_MAJOR-default_$TAG_DATE"
    "latest-default"
)

BASE_TAGS=(
    "v$APACHE_VERSION" "v${APACHE_VERSION}_$TAG_DATE"
    "v$APACHE_VERSION_MINOR" "v${APACHE_VERSION_MINOR}_$TAG_DATE"
    "v$APACHE_VERSION_MAJOR" "v${APACHE_VERSION_MAJOR}_$TAG_DATE"
    "latest"
)

printf 'VERSION="%s"\n' "$APACHE_VERSION"
printf 'DEFAULT_TAGS="%s"\n' "${DEFAULT_TAGS[*]}"
printf 'BASE_TAGS="%s"\n' "${BASE_TAGS[*]}"

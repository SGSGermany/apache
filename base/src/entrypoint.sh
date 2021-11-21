#!/bin/sh
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

set -e

[ $# -gt 0 ] || set -- httpd-foreground "$@"
if [ "$1" == "httpd-foreground" ]; then
    if [ ! -f "/etc/apache2/ssl/dhparams.pem" ]; then
        # generating Diffie Hellman parameters might take a few minutes...
        openssl dhparam -out "/etc/apache2/ssl/dhparams.pem" 2048
    fi

    (
        set -eu -o pipefail -- /etc/apache2/ssl/*/
        if [ $# -eq 1 ] && [ "$1" == "/etc/apache2/ssl/*/" ] || [ $# -eq 0 ]; then
            printf "[%s] [cert_watchdog:notice] Skipping cert watchdog service\n" \
                "$(LC_ALL=C date +'%a %b %d %T.000000 %Y')" >&2
            exit 0
        fi

        printf "[%s] [cert_watchdog:notice] Starting cert watchdog service...\n" \
            "$(LC_ALL=C date +'%a %b %d %T.000000 %Y')" >&2
        inotifywait -e close_write,delete,move -m "$@" \
            | while read -r DIRECTORY EVENTS FILENAME; do
                printf "[%s] [cert_watchdog:notice] Receiving inotify event '%s' for '%s%s'...\n" \
                    "$(LC_ALL=C date +'%a %b %d %T.000000 %Y')" "$EVENTS" "$DIRECTORY" "$FILENAME" >&2

                # wait till 300 sec (5 min) after the last event, new events reset the timer
                while read -t 300 -r DIRECTORY EVENTS FILENAME; do
                    printf "[%s] [cert_watchdog:notice] Receiving inotify event '%s' for '%s%s'...\n" \
                        "$(LC_ALL=C date +'%a %b %d %T.000000 %Y')" "$EVENTS" "$DIRECTORY" "$FILENAME" >&2
                done

                printf "[%s] [cert_watchdog:notice] Gracefully restarting Apache 'httpd' daemon...\n" \
                    "$(LC_ALL=C date +'%a %b %d %T.000000 %Y')" >&2
                apachectl graceful
            done
    ) &

    exec "$@"
fi

exec "$@"

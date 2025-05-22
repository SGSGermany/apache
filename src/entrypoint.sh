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

[ $# -gt 0 ] || set -- httpd-foreground
if [ "$1" == "httpd-foreground" ]; then
    # manage SSL config, if module is enabled
    if a2querymod -q "ssl"; then
        # generate Diffie Hellman parameters, if necessary
        if [ ! -f "/etc/apache2/ssl/dhparams.pem" ]; then
            # generating Diffie Hellman parameters might take a few minutes...
            printf "[%s] [entrypoint:notice] Generating Diffie Hellman parameters\n" \
                "$(LC_ALL=C.UTF-8 date +'%a %b %d %T.000000 %Y')" >&2
            openssl dhparam -out "/etc/apache2/ssl/dhparams.pem" 2048
        fi

        # start SSL certificate watchdog
        apache-cert-watchdog &
    fi

    exec "$@"
fi

exec "$@"

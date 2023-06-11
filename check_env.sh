#!/usr/bin/env bash

set -e
set -x

which cp
which cat
which echo
which [

which dd
which cut
which uname
which stat
which md5 || which sha1 || which sha512 || which sha256 || echo 'Warn: no known hasing algorithms'
which printf

stat -f '%Sm %z' -t %s "$0" || stat --format="%Y %s" "$0"
uname -a

[ -c /dev/null ]
[ -c /dev/zero ]
[ -c /dev/stdin ]

which diff || echo "Warn: tests depend on diff"
diff -u "$0" "$0" || echo "Warn: tests depend on diff -u"
which dirname || echo "Warn: tests depend on dirname"
which realpath || echo "Warn: tests depend on realpath"


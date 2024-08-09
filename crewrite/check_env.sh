#!/usr/bin/env bash

set -e
set -x

which cp
which cat
which echo
which [

which cut
which uname
which stat
which printf

[ -c /dev/null ]
[ -c /dev/zero ]
[ -c /dev/stdin ]

which diff || echo "Warn: tests depend on diff"
diff -u "$0" "$0" || echo "Warn: tests depend on diff -u"
which dirname || echo "Warn: tests depend on dirname"
which realpath || echo "Warn: tests depend on realpath"


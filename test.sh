#!/usr/bin/env bash

declare -a FAILS
NFAIL=0
TESTDIR=`mktemp -d`
WORKDIR=`mktemp -d`
rmtestdir() {
    rm -rf "$TESTDIR" "$WORKDIR"
}
trap rmtestdir EXIT

# Create a couple of test files
cat <<EOT > "$TESTDIR/a"
qwer
EOT
cat <<EOT > "$TESTDIR/b"
asdf
qwer
z
EOT
# Create some subdirs
mkdir -p "$TESTDIR/d"
mkdir -p "$TESTDIR/d/e"
cat <<EOT > "$TESTDIR/d/c"
asdf
qwer
z
EOT

for i in a b d/c d/e d ; do
    touch -m -d 2001-01-01T01:01:00Z "$TESTDIR/$i" || touch -m -d @978310860 "$TESTDIR/$i"
done

CURRENT=none
start() {
    CURRENT="$*"
    echo ''
    echo '-------------------'
    echo $CURRENT
    echo '-------------------'
}

fail() {
    if [[ ! -z "$CURRENT" ]] ; then
        echo '!!!!!!!!!!!!!!!!!!!!'
        echo $CURRENT FAILED!
        echo '!!!!!!!!!!!!!!!!!!!!'
        FAILS=("${FAILS[@]}" "$CURRENT")
        NFAIL=`expr $NFAIL + 1`
        CURRENT=''
    fi
}

bashftp="$( dirname $( realpath "$0" ) )/bashftp.sh"

pushd "$TESTDIR" > /dev/null 2>&1

# ls, no md5
start ls TESTDIR, no md5
$bashftp ls . | sort > "$WORKDIR/ls.1" || fail
cat <<EOT > "$WORKDIR/ls.1.orig"
d 978310860 ./d
f 978310860 12 0 ./b
f 978310860 5 0 ./a
EOT
diff -u "$WORKDIR/ls.1.orig" "$WORKDIR/ls.1" || fail

# ls, md5
start ls TESTDIR/d, with md5
$bashftp ls ./d md5 | sort > "$WORKDIR/ls.2" || fail
cat <<EOT > "$WORKDIR/ls.2.orig"
d 978310860 ./d/e
f 978310860 12 18e724602c9dcb3e4e936f8909a4972c ./d/c
EOT
diff -u "$WORKDIR/ls.2.orig" "$WORKDIR/ls.2" || fail

# get full file < block
start get full file, file is smaller than block
$bashftp get 0 10 ./a > "$WORKDIR/get.1" || fail
cat <<EOT > "$WORKDIR/get.1.orig"
qwer
EOT
diff -u "$WORKDIR/get.1.orig" "$WORKDIR/get.1" || fail

# get first block
start get first block, block is smaller than file
$bashftp get 0 5 ./b > "$WORKDIR/get.0" || fail
cat <<EOT > "$WORKDIR/get.0.orig"
asdf
EOT
diff -u "$WORKDIR/get.0.orig" "$WORKDIR/get.0" || fail

# get a block
start get second block, block is smaller than file
$bashftp get 5 10 ./b > "$WORKDIR/get.2" || fail
cat <<EOT > "$WORKDIR/get.2.orig"
qwer
EOT
diff -u "$WORKDIR/get.2.orig" "$WORKDIR/get.2" || fail

# get last block
start get last block, last block is smaller than block size
$bashftp get 10 15 ./b > "$WORKDIR/get.3" || fail
cat <<EOT > "$WORKDIR/get.3.orig"
z
EOT
diff -u "$WORKDIR/get.3.orig" "$WORKDIR/get.3" || fail

# get single character
start get single byte
$bashftp get 10 11 ./b > "$WORKDIR/get.4" || fail
# n.b.: need the file to end in LF for diff
echo>>"$WORKDIR/get.4"
cat <<EOT > "$WORKDIR/get.4.orig"
z
EOT
diff -u "$WORKDIR/get.4.orig" "$WORKDIR/get.4" || fail

# put first block
start put first block
cat <<EOT | $bashftp put 0 5 ./new || fail
asdf
EOT
cat <<EOT > "$WORKDIR/put.0.orig"
asdf
EOT
diff -u "$WORKDIR/put.0.orig" new || fail

# put second block
start put second block
cp "$WORKDIR/put.0.orig" new
cat <<EOT | $bashftp put 5 10 ./new || fail
qwer
EOT
cat <<EOT > "$WORKDIR/put.1.orig"
asdf
qwer
EOT
diff -u "$WORKDIR/put.1.orig" new || fail

# put last block
start put last block
cp "$WORKDIR/put.1.orig" new
cat <<EOT | $bashftp put 10 13 ./new || fail
zx
EOT
cat <<EOT > "$WORKDIR/put.2.orig"
asdf
qwer
zx
EOT
diff -u "$WORKDIR/put.2.orig" new || fail

# backfill second block, discarding 3rd
cp "$WORKDIR/put.2.orig" new
cat <<EOT | $bashftp put 5 10 ./new || fail
qwer
EOT
cat <<EOT > "$WORKDIR/put.3.orig"
asdf
qwer
EOT
diff -u "$WORKDIR/put.3.orig" new || fail put3 second block discarding 3rd failed

# put last block, but stdin ends early
start put last block, but stdin ends early
cp "$WORKDIR/put.1.orig" new
cat <<EOT | $bashftp put 10 15 ./new || fail
zx
EOT
cat <<EOT > "$WORKDIR/put.4.orig"
asdf
qwer
zx
EOT
diff -u "$WORKDIR/put.4.orig" new || fail

# put empty file
start upload empty file
cat /dev/null | $bashftp put 0 0 zero || fail
printf "" > "$WORKDIR/empty"
diff -u "$WORKDIR/empty" zero || fail

# error cases
#

start ls nonexistant path
$bashftp ls nonexistant && fail

start get nonexistant path
$bashftp get 0 5 nonexistant && fail

start put into nonexistant dir
cat <<EOT | $bashftp put 0 5 nonexistant/file && fail
EOT

start get with bad range
cat /dev/zero | $bashftp put 5 0 no && fail
[ -f no ] && fail

if [[ $NFAIL -gt 0 ]] ; then
    echo ''
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo $NFAIL 'test(s)' failed:
    for i in "${FAILS[@]}" ; do
    echo '    '$i
    done
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
else
    echo ''
    echo OK
    exit 0
fi

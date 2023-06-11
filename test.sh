#!/usr/bin/env bash

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
    touch -m -t 200101010101.00 "$TESTDIR/$i"
done

fail() {
    echo '!!!!!!!!!!!!!!!!!!!!'
    echo $*
    echo '!!!!!!!!!!!!!!!!!!!!'
    NFAIL=`expr $NFAIL + 1`
}

bashftp="$( dirname $( readlink -f "$0" ) )/bashftp.sh"

pushd "$TESTDIR" > /dev/null 2>&1

# ls, no md5
$bashftp ls . | sort > "$WORKDIR/ls.1"
cat <<EOT > "$WORKDIR/ls.1.orig"
d 978303660 ./d
f 978303660 12 0 ./b
f 978303660 5 0 ./a
EOT
diff -u "$WORKDIR/ls.1.orig" "$WORKDIR/ls.1" || fail ls1 failed

# ls, md5
$bashftp ls ./d md5 | sort > "$WORKDIR/ls.2"
cat <<EOT > "$WORKDIR/ls.2.orig"
d 978303660 ./d/e
f 978303660 12 18e724602c9dcb3e4e936f8909a4972c ./d/c
EOT
diff -u "$WORKDIR/ls.2.orig" "$WORKDIR/ls.2" || fail ls2 md5 failed

# get full file < block
$bashftp get 0 10 ./a > "$WORKDIR/get.1"
cat <<EOT > "$WORKDIR/get.1.orig"
qwer
EOT
diff -u "$WORKDIR/get.1.orig" "$WORKDIR/get.1" || fail get1 more than file

# get first block
$bashftp get 0 5 ./b > "$WORKDIR/get.0"
cat <<EOT > "$WORKDIR/get.0.orig"
asdf
EOT
diff -u "$WORKDIR/get.0.orig" "$WORKDIR/get.0" || fail get0 first block failed

# get a block
$bashftp get 5 10 ./b > "$WORKDIR/get.2"
cat <<EOT > "$WORKDIR/get.2.orig"
qwer
EOT
diff -u "$WORKDIR/get.2.orig" "$WORKDIR/get.2" || fail get2 block failed

# get last block
$bashftp get 10 15 ./b > "$WORKDIR/get.3"
cat <<EOT > "$WORKDIR/get.3.orig"
z
EOT
diff -u "$WORKDIR/get.3.orig" "$WORKDIR/get.3" || fail get3 last block failed

# get single character
$bashftp get 10 11 ./b > "$WORKDIR/get.4"
echo>>"$WORKDIR/get.4"
cat <<EOT > "$WORKDIR/get.4.orig"
z
EOT
diff -u "$WORKDIR/get.4.orig" "$WORKDIR/get.4" || fail get4 single character failed

# put first block
cat <<EOT | $bashftp put 0 5 ./new
asdf
EOT
cat <<EOT > "$WORKDIR/put.0.orig"
asdf
EOT
diff -u "$WORKDIR/put.0.orig" new || fail put0 first block

# put second block
cp "$WORKDIR/put.0.orig" new
cat <<EOT | $bashftp put 5 10 ./new
qwer
EOT
cat <<EOT > "$WORKDIR/put.1.orig"
asdf
qwer
EOT
diff -u "$WORKDIR/put.1.orig" new || fail put1 second block

# put last block
cp "$WORKDIR/put.1.orig" new
cat <<EOT | $bashftp put 10 13 ./new
zx
EOT
cat <<EOT > "$WORKDIR/put.2.orig"
asdf
qwer
zx
EOT
diff -u "$WORKDIR/put.2.orig" new || fail put2 last block failed

# backfill second block, discarding 3rd
cp "$WORKDIR/put.2.orig" new
cat <<EOT | $bashftp put 5 10 ./new
qwer
EOT
cat <<EOT > "$WORKDIR/put.3.orig"
asdf
qwer
EOT
diff -u "$WORKDIR/put.3.orig" new || fail put3 second block discarding 3rd failed

if [[ $NFAIL -gt 0 ]] ; then
    echo ''
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo $NFAIL tests failed
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
else
    exit 0
fi

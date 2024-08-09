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
mkdir -p "$TESTDIR/d d"
mkdir -p "$TESTDIR/d d/e"
cat <<EOT > "$TESTDIR/d d/c"
asdf
qwer
z
EOT

for i in a b "d d/c" "d d/e" "d d" ; do
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

bashftp="$( dirname $( realpath "$0" ) )/bascftp"

pushd "$TESTDIR" > /dev/null 2>&1

# ls, no crc32
start ls TESTDIR, no crc32
$bashftp ls . | sort > "$WORKDIR/ls.1" || fail
cat <<EOT > "$WORKDIR/ls.1.orig"
d 978310860 ./d d
f 978310860 12 0 ./b
f 978310860 5 0 ./a
EOT
diff -u "$WORKDIR/ls.1.orig" "$WORKDIR/ls.1" || fail

# ls, crc32
start ls TESTDIR/d d, with crc32
$bashftp ls "./d d" crc32 | sort > "$WORKDIR/ls.2" || fail
cat <<EOT > "$WORKDIR/ls.2.orig"
d 978310860 ./d d/e
f 978310860 12 4001513809 ./d d/c
EOT
diff -u "$WORKDIR/ls.2.orig" "$WORKDIR/ls.2" || fail

# ls, crc32
start crc32 hash
$bashftp ls "./d d" crc32 | sort > "$WORKDIR/ls.3" || fail
cat <<EOT > "$WORKDIR/ls.3.orig"
d 978310860 ./d d/e
f 978310860 12 4001513809 ./d d/c
EOT
diff -u "$WORKDIR/ls.3.orig" "$WORKDIR/ls.3" || fail

start tree crc32
$bashftp tree . crc32 | sort > "$WORKDIR/tree.1" || fail
cat <<EOT > "$WORKDIR/tree.1.orig"
d 978310860 ./d d
d 978310860 ./d d/e
f 978310860 12 4001513809 ./b
f 978310860 12 4001513809 ./d d/c
f 978310860 5 1658262348 ./a
EOT
diff -u "$WORKDIR/tree.1.orig" "$WORKDIR/tree.1" || fail

start tree without hash
$bashftp tree . | sort > "$WORKDIR/tree.1" || fail
cat <<EOT > "$WORKDIR/tree.1.orig"
d 978310860 ./d d
d 978310860 ./d d/e
f 978310860 12 0 ./b
f 978310860 12 0 ./d d/c
f 978310860 5 0 ./a
EOT
diff -u "$WORKDIR/tree.1.orig" "$WORKDIR/tree.1" || fail

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
start backfill second block, discarding 3rd
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

# put empty file in nonexistant directory
start put file in nonexistant1 directory
cat /dev/null | $bashftp put 0 0 nonexistant1/emptyfile || fail
printf "" > "$WORKDIR/empty"
diff -u "$WORKDIR/empty" nonexistant1/emptyfile || fail

# error cases
#

start ls nonexistant path
$bashftp ls nonexistant && fail

start get nonexistant path
$bashftp get 0 5 nonexistant && fail

# superseeded by put empty file in nonexistant directory
#start put into nonexistant dir
#cat <<EOT | $bashftp put 0 5 nonexistant/file && fail
#EOT

start get with bad range
cat /dev/zero | $bashftp put 5 0 no && fail
[ -f no ] && fail

start hash on file with EACCESS
if [[ "$(id -u)" -eq 0 ]] ; then
    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    echo  skipping start hash on file with EACCESS as this cannot run as root
    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
else

mkdir -p "$WORKDIR/EACCESS/"
echo 'secret' > "$WORKDIR/EACCESS/denied"
echo 'not a secret' > "$WORKDIR/EACCESS/public"
touch -m -d 2001-01-01T01:01:00Z "$WORKDIR/EACCESS/public" || touch -m -d @978310860 "$WORKDIR/EACCESS/public"
touch -m -d 2001-01-01T01:01:00Z "$WORKDIR/EACCESS/denied" || touch -m -d @978310860 "$WORKDIR/EACCESS/denied"
chmod 0000 "$WORKDIR/EACCESS/denied"
$bashftp ls "$WORKDIR/EACCESS/" crc32 > "$WORKDIR/eaccess.1"
cat <<EOT > "$WORKDIR/eaccess.1.orig"
f 978310860 13 3936211975 $WORKDIR/EACCESS/public
f 978310860 7 0 $WORKDIR/EACCESS/denied
EOT
diff -u "$WORKDIR/eaccess.1.orig" "$WORKDIR/eaccess.1" || fail

fi

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

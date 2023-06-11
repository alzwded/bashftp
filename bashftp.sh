#!/usr/bin/env bash

bashftp_hash() {
    md5 -q "${1?missing path}"
}

bashftp_time() {
    uname -a | grep ^OpenBSD > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        stat -f %Sm -t %s "${1?missing path}"
    else
        echo FIXME I forget
        exit 4
    fi
}

bashftp_time_size() {
    uname -a | grep ^OpenBSD > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        stat -f "%Sm %z" -t %s "${1?missing path}"
    else
        echo FIXME I forget
        exit 4
    fi
}

bashftp_ls() {
    local IN_path="${1?missing path}"
    local OLD_IFS
    local f
    local full_path
    local l_is_dir
    local l_hash
    local l_size
    local l_timestamp
    local l_with_md5=0

    if [[ ${2+x} == x && "$2" == md5 ]] ; then
        l_with_md5=1
    fi
    #if [[ ${IN_path:0:1} != '/' ]] ; then
    #    echo "Path is not absolute: $IN_path" 1>&2
    #    exit 1
    #fi
    #IN_path=/"${IN_path#/}"
    IN_path="${IN_path%/}"

    if [[ ! -d "${IN_path}" ]] ; then
        echo "Not a directory: $IN_path" 1>&2
        exit 1
    fi

    OLD_IFS=$IFS
    IFS='
'

    FILES=($( ls -1 "$IN_path" ))

    IFS=$OLD_IFS

    for f in "${FILES[@]}" ; do
        full_path="$IN_path/$f"
        if [[ -d "$full_path" ]] ; then
            printf "d %d %s\n" \
                $( bashftp_time "$full_path" ) \
                "$full_path"
        else
            printf "f %d %d %s %s\n" \
                $( bashftp_time_size "$full_path" ) \
                \
                "$( ( [ $l_with_md5 -eq 1 ] ) && ( bashftp_hash "$full_path" ) || echo 0 )" \
                "$full_path"
        fi
    done
}

bashftp_put() {
    local START=${1?missing start offset}
    local END=${2?missing end offset}
    local IN_path="${3?missing path}"

    # crazy computations
    local l_count=$( expr $END - $START )
    if [[ $l_count -le 0 ]] ; then
        echo "$END <= $START" 1>&2
        exit 1
    fi

    local l_div=$( expr $START '/' $l_count )
    local l_remul=$( expr $l_div '*' $l_count )

    # truncate file
    truncate -s $END "$IN_path"

    if [[ $l_remul -eq $START ]] ; then
        # we can use blocks
        dd if=/dev/stdin "of=$IN_path" bs=$l_count count=1 seek=$l_div
    else
        # we cannot use blocks
        dd if=/dev/stdin "of=$IN_path" bs=1 count=$l_count seek=$START
    fi

    # drain stdin
    cat > /dev/null
}

bashftp_get() {
    local START=${1?missing start offset}
    local END=${2?missing end offset}
    local IN_path="${3?missing path}"

    if [[ ! -f "$IN_path" ]] ; then
        echo "Not a file: $IN_path" 1>&2
        exit 1
    fi

    # crazy computations
    local l_count=$( expr $END - $START )
    if [[ $l_count -le 0 ]] ; then
        echo "$END <= $START" 1>&2
        exit 1
    fi

    local l_div=$( expr $START '/' $l_count )
    local l_remul=$( expr $l_div '*' $l_count )

    if [[ $l_remul -eq $START ]] ; then
        # we can use blocks
        dd "if=$IN_path" bs=$l_count count=1 seek=$l_div
    else
        # we cannot use blocks
        dd "if=$IN_path" bs=1 count=$l_count seek=$START
    fi
}

bashftp_help() {
    echo "Usage: $1 [help|ls|put|get]"
    echo "    help                  prints this message"
    echo "    ls path               list directory"
    echo "    ls path md5           list directory and calculate md5 for files"
    echo "                          prints:"
    echo "                              d 1666266539 subdir"
    echo "                              f 1666266539 2279 2164e12fc5f03902b61d977fc2f29d00 file"
    echo "                          hash is 0 if not requested"
    echo "    put start end path    receives a chunk of a file on stdin"
    echo "    get start end path    returns a chunk of a file on stdout"
}

case ${1?missing argument -- try $0 help} in
    ls)
        bashftp_ls "${2?missing path}" $3
        ;;
    put)
        bashftp_put ${2?missing start offset} ${3?missing end offset} "${4?missing destination}"
        ;;
    get)
        bashftp_get ${2?missing start offset} ${3?missing end offset} "${4?missing path}"
        ;;
    *)
        bashftp_help "$0"
        ;;
esac

exit $?

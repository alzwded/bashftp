#!/usr/bin/env bash
# Copyright (c) 2023, Vlad Meșco
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

VERSION=2.0

error_out() {
    echo "$@" 1>&2
    exit 1
}

if uname -a | grep ^OpenBSD > /dev/null 2>&1 ; then
    bashftp_hash() {
        printf "%s\n" $( ${1?missing hash command} -q "${2?missing path}" | cut -d= -f2 ) || error_out "Failed to md5 $1"
    }
elif md5sum -b "$0" > /dev/null 2>&1 ; then
    bashftp_hash() {
        printf "%s\n" $( ${1?missing hash command} -b "${2?missing path}" | cut -d' ' -f1 ) || error_out "Failed to md5 $1"
    }
else
    bashftp_hash() {
        printf "%s\n" $( ${1?missing hash command} -b "${2?missing path}" | cut -d' ' -f1 ) || error_out "Failed to md5 $1"
    }
fi

if uname -a | grep ^OpenBSD > /dev/null 2>&1 ; then
    bashftp_time() {
        stat -f %Sm -t %s "${1?missing path}" || error_out "Failed to stat $1"
    }
    
    bashftp_time_size() {
        stat -f "%Sm %z" -t %s "${1?missing path}" || error_out "Failed to stat $1"
    }
elif stat --format=%Y "$0" > /dev/null 2>&1 ; then
    bashftp_time() {
        stat --format="%Y" "${1?missing path}" || error_out "Failed to stat $1"
    }
    
    bashftp_time_size() {
        stat --format="%Y %s" "${1?missing path}" || error_out "Failed to stat $1"
    }
else
    bashftp_time() {
        stat -c "%Y" "${1?missing path}" || error_out "Failed to stat $1"
    }
    
    bashftp_time_size() {
        stat -c "%Y %s" "${1?missing path}" || error_out "Failed to stat $1"
    }
fi


bashftp_ls() {
    local IN_path="${1?missing path}"
    local OLD_IFS
    local f
    local full_path
    local l_is_dir
    local l_hash
    local l_size
    local l_timestamp
    local l_with_hash=0
    local l_hash

    if [[ ${2+x} == x  ]] ; then
        case "$2" in
            md5|sha1|sha256|sha512)
                l_with_hash=1
                if which $2 > /dev/null 2>&1 ; then
                    l_hash=( $2 )
                elif which $2sum > /dev/null 2>&1 ; then
                    l_hash=( $2sum )
                fi
                ;;
            *)
                error_out "Unsupported hash $2"
                ;;
        esac
    fi
    IN_path="${IN_path%/}"

    if [[ ! -d "${IN_path}" ]] ; then
        echo "Not a directory: $IN_path" 1>&2
        exit 1
    fi

    OLD_IFS=$IFS
    IFS='
'

    FILES=($( ls -1 "$IN_path" ))
    if [[ $? -ne 0 ]] ; then
        error_out "Failed to ls $IN_path"
    fi

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
                "$( ( [ $l_with_hash -eq 1 ] ) && ( bashftp_hash "${l_hash[*]}" "$full_path" ) || echo 0 )" \
                "$full_path"
        fi
    done

    exit 0
}

bashftp_put() {
    local START=${1?missing start offset}
    local END=${2?missing end offset}
    local IN_path="${3?missing path}"

    # ensure all directory paths exist
    mkdir -p "$( dirname "$IN_path" )"

    # check for empty file uploads
    if [[ $START -eq 0 && $START -eq $END ]] ; then
        #truncate -s 0 "$IN_path" || error_out "Faield to truncate $IN_path to 0"
        cat /dev/null > "$IN_path"
        exit 0
    fi

    # crazy computations
    local l_count=$( expr $END - $START )
    if [[ $l_count -le 0 ]] ; then
        echo "Incorrect range: $END <= $START" 1>&2
        exit 1
    fi

    # truncate file
    #truncate -s $START "$IN_path" || error_out "Failed to truncate $IN_path to $START"

    dd if=/dev/stdin "of=$IN_path" bs=1 count=$l_count seek=$START || error_out "Failed to dd stdin to $IN_path bs=1"

    # drain stdin
    cat > /dev/null

    exit 0
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

    dd "if=$IN_path" bs=1 count=$l_count skip=$START || error_out "Failed to dd $IN_path to stdout bs=1"

    exit 0
}

bashftp_version() {
    echo $VERSION
}

bashftp_help() {
    echo "Usage: $1 [help|ls|put|get|version]"
    echo "    help                  prints this message"
    echo "    version               prints version"
    echo "    ls path               list directory"
    echo "    ls path md5           list directory and calculate md5 for files"
    echo "    put start end path    receives a chunk of a file on stdin"
    echo "    get start end path    returns a chunk of a file on stdout"
    echo ""
    echo "ls format:"
    echo "- directories:"
    echo "      d unixtime path"
    echo "- files:"
    echo "      f unixtime sizeinbytes hash path"
    echo "hash is 0 if not requested"
    echo "Example:"
    echo "      d 1666266539 subdir"
    echo "      f 1666266539 2279 2164e12fc5f03902b61d977fc2f29d00 file"
    exit 1
}

if [[ -z ${1+x} ]] ; then
    bashftp_help "$0"
fi

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
    version|-V|--version)
        bashftp_version
        ;;
    help|-h|--help)
        bashftp_help "$0"
        ;;
    *)
        echo "$1 is not an option"
        bashftp_help "$0"
        ;;
esac

exit $?

bashftp
=======

I got bored and wrote something _kinda_ like a single-command sftp thing in bash (BSD licensed).

It allows putting files via stdin, block by block; as well as fetching files
via stdout, block by block.

The directory listing reports a readable records indicating if something is
a directory or not, mtime, size, and it optionally computes md5 using the
system's `md5` executable.

Block transfers are handled with `dd`.

It is intentional to create separate connections for each transfer block, since
you can retry the call a couple of times if the network is sad. It is also
a spectacularily bad idea if someone's using the same files on the other end,
since it will result in 100% file corruption.

You're meant to install it and use it something like:

    scp bashftp.sf victim:/usr/local/bin/bashftp
    ssh victim bashftp ls ~ md5
    ssh victim bashftp get 0 4096 ~/thing > ~/thing
    ssh victim bashftp get 4096 8192 ~/thing > ~/thing
    ...

There's a [Makefile](./Makefile) in there allowing you to run tests and to
install it to a `PREFIX` (but only if you're brave).

Help output:

```
Usage: ./bashftp.sh [help|ls|put|get|version]
    help                  prints this message
    version               prints version
    ls path               list directory
    ls path md5           list directory and calculate md5 for files
    put start end path    receives a chunk of a file on stdin
    get start end path    returns a chunk of a file on stdout

ls format:
- directories:
      d unixtime path
- files:
      f unixtime sizeinbytes hash path
hash is 0 if not requested
Example ls output:
      d 1666266539 subdir
      f 1666266539 2279 2164e12fc5f03902b61d977fc2f29d00 file
```

Changelog
=========

3.2 -> 3.3
----------

- add `tree` subcommand

3.1 -> 3.2
----------

- add crc32 hash type

3.0 -> 3.1
----------

- return hash 0 for files for which we get EACCESS or some other error

2.0 -> 3.0
----------

- Speed up `dd` by using bigger block sizes
- First put block overwrites the file, but subsequent puts don't.
  I need to rewrite this in C and get rid of `dd`'s 40 (or 50?) years of astonishing behaviour.

1.0 -> 2.0
----------

`put` -ing files into nonexistant paths will create all intermediate paths (`mkdir -p`).

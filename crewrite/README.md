bascftp
=======

A rewrite of [`bashftp`](../README.md) in C, for maybe better performance.

Be warned, it installs itself as `bashftp` to be a drop-in replacement for `bashftp.sh`.

This project uses the `crc32` implementation from OpenBSD, see [crc.c](./crc.c) for terms.

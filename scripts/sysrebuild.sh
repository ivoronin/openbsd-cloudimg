#!/bin/sh

set -e

CONFIG="GENERIC.MP"
NCPU=`sysctl -n hw.ncpu`

cd /usr/src 
ftp https://ftp.openbsd.org/pub/OpenBSD/`uname -r`/sys.tar.gz
tar xzf sys.tar.gz

cd /usr/src/sys
for p in /usr/src/patches/*.sys.patch; do
    patch -s < $p
done

cd /usr/src/sys/arch/`arch -s`/conf
config ${CONFIG}

cd /usr/src/sys/arch/`arch -s`/compile/${CONFIG}
make -s -j $NCPU
make install

rm -rf /usr/src/sys /usr/src/sys.tar.gz /usr/src/patches

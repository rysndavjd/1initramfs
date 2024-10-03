#!/bin/bash

# Copyright 2024 rysndavjd
# Distributed under the terms of the GNU General Public License v2

if [[ $EUID -ne 0 ]]
then 
    echo "Run as root."
    exit 1
fi

tmp=$(mktemp -d)
echo $tmp
shversion="git"

help () {
    echo "1initramfs, version $shversion"
    echo "Usage: 1initramfs [option] ..."
    echo "Options:"
    echo "      -h  (calls help menu)"
    exit 0
}

while getopts hc: flag ; do
    case "${flag}" in
        ?) help;;
        h) help;;
        c) config="${OPTARG}";;
    esac
done

if ! [ -e $config ] ; then
    echo "Specified config does not exist at $config."
    exit 1
fi

if zcat /proc/config.gz | grep -q CONFIG_DEVTMPFS || cat /boot/config* | grep -q CONFIG_DEVTMPFS || cat /proc/mounts | grep -q devtmpfs ; then
    dev="devtmpfs"
else
    dev="manual"
fi

rootmnt=$(findmnt -n -o SOURCE /)
rootuuid=$(blkid -s UUID -o value $mnt)
rootisluks=$(cryptsetup isLuks $rootmnt)

# $1 = absolute path of binary
copybinsfn() 
{
    for num in $1 ; do
        dir=$(dirname "$num")
        mkdir -p $tmp/$dir
        cp $num $tmp/$dir
    done

    libs=$(ldd $1 | awk '/ => / { print $3 }' | paste -sd ' ' -)
    if ldd $1 | grep -q /lib64/ld-linux-x86-64.so ; then 
        libs="$libs /lib64/ld-linux-x86-64.so.2"
    fi
    if ldd $1 | grep -q /lib/ld-linux.so.2 ; then 
        libs="$libs /lib/ld-linux.so.2"
    fi

    for num in $libs ; do
        dir=$(dirname "$num")
        mkdir -p $tmp/$dir
        cp $num $tmp/$dir
    done
}

. /etc/default/1initramfs

echo -n "$"


mkdir -p "$tmp"/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}



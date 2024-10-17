#!/bin/bash

# Copyright (c) 2024 rysndavjd
# Distributed under the terms of the GNU General Public License v2
# 1initramfs

if [[ $EUID -ne 0 ]] ; then 
    echo "Run as root."
    exit 1
fi

pwd=$(pwd)
tmp=$(mktemp -d)
shversion="git"
. /etc/default/1initramfs 2>/dev/null

helpfn () {
    echo "1initramfs, version $shversion"
    echo "Usage: 1initramfs [option] ..."
    echo "Options:"
    echo "      -h  (calls help menu)"
    echo "      -c  (Override using default config at /etc/default/1initramfs)"
    echo "      -o  (Override default output directory at /boot)"
    exit 0
}

while getopts hc:o: flag ; do
    case "${flag}" in
        ?) helpfn;;
        h) helpfn;;
        c) config="${OPTARG}";;
        o) output="${OPTARG}";;
    esac
done

if findmnt -n -o SOURCE / | grep -q /dev/mapper/ ; then 
    mapper=$(basename "$(findmnt -n -o SOURCE /)")
    rootmnt=$(cryptsetup status "$mapper" | grep device: | sed 's/device: //') 
else
    rootmnt=$(findmnt -n -o SOURCE /)
fi
rootuuid=$(blkid -s UUID -o value $rootmnt)
rootluksuuid=$(cryptsetup luksUUID $rootmnt)
rootisluks=$(cryptsetup isLuks $rootmnt ; echo -En $?)

if [ -z "${output+x}" ] ; then
    output="$pwd"
    echo "Output not set, outputing to $pwd"
fi

if [ -z "${RECOVERYSH+x}" ] ; then
    RECOVERYSH="n"
fi

if [ -z "${COMPRESSION+x}" ] ; then
    COMPRESSION=none
    echo "Compression not set, defaulting to none."
else
    echo "Compression set to $COMPRESSION."
fi

if [ -z "${YUBIOVERIDE+x}" ] ; then
    YUBIOVERIDE=n
    echo "Yubikey Challenge not set."
elif [ "$YUBIOVERIDE" = "y" ] ; then
    if [ "$rootisluks" = "1" ] ; then
        echo "Root is not LUKS, yubikey overide is useless."
        exit 1
    elif [ -z "${YUBICHAL+x}" ] ; then
        echo "Yubikey challenge not set."
        exit 1
    elif [ "$YUBICHAL" = "manual" ] ; then
        echo "Yubikey Challenge set to manual, challenge will be entered on boot."
    else
        echo "Yubikey Challenge set to $YUBICHAL."
    fi
fi

if ! [ -e $config ] ; then
    echo "Specified config does not exist at $config."
    exit 1
fi

if cat /proc/mounts | grep -q devtmpfs || zcat /proc/config.gz | grep -q CONFIG_DEVTMPFS || cat /boot/config* | grep -q CONFIG_DEVTMPFS ; then
    dev="devtmpfs"
else
    dev="mdev"
fi

# $1 = absolute path of binary
copybinsfn() {
    for num in $1 ; do
        dir=$(dirname "$num")
        mkdir -p $tmp/build/$dir
        cp $num $tmp/build/$dir
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
        mkdir -p $tmp/build/$dir
        cp $num $tmp/build/$dir
    done
}

compressionfn () {
cd "$tmp/build"
if [ $COMPRESSION = "none" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$output"/initramfs.img 2>/dev/null
elif [ $COMPRESSION = "gzip" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null
    gzip "$tmp"/initramfs.img 
    mv "$tmp"/initramfs.img.gz "$output"/initramfs.img
elif [ $COMPRESSION = "bzip2" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

elif [ $COMPRESSION = "lzma" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

elif [ $COMPRESSION = "xz" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

elif [ $COMPRESSION = "lzo" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

elif [ $COMPRESSION = "lz4" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

elif [ $COMPRESSION = "zstd" ] ; then 
    find . -print0 | cpio --null --create --verbose --format=newc > "$tmp"/initramfs.img 2>/dev/null

fi
}

buildbasefn() {
mkdir -p "$tmp"/build/{usr/bin,dev,etc,usr/lib,usr/lib64,mnt/root,proc,root,sys,run}
cd $tmp/build/
ln -sr ./usr/bin/ ./sbin
ln -sr ./usr/bin/ ./bin
ln -sr ./usr/bin/ ./usr/sbin
ln -sr ./usr/lib/ ./lib
ln -sr ./usr/lib64/ ./lib64

mknod ./dev/kmsg c 1 11
mknod ./dev/console c 5 1
mknod ./dev/null c 1 3
mknod ./dev/zero c 1 5
mknod ./dev/random c 1 8
chmod 600 ./dev/*

copybinsfn $(which busybox) 2>/dev/null

if [ $rootisluks = 0 ] ; then
    copybinsfn $(which cryptsetup) 2>/dev/null
fi

if [ $YUBIOVERIDE = "y" ] ; then
    copybinsfn $(which ykchalresp) 2>/dev/null
    copybinsfn $(which lsusb) 2>/dev/null
fi
}

buildinitfn() {
touch $tmp/build/init
chmod +x $tmp/build/init

#Header
echo "#!/bin/busybox sh" >> $tmp/build/init

#Kernel FS
echo "mount -n -t proc proc /proc
mount -n -t sysfs sys /sys" >> $tmp/build/init

#Devfs
if [ $dev = "devtmpfs" ] ; then
    echo "mount -n -t devtmpfs dev /dev" >> $tmp/build/init
elif [ $dev = "mdev" ] ; then
    echo "mount -t tmpfs dev /dev
echo /sbin/mdev > /proc/sys/kernel/hotplug" >> $tmp/build/init
fi

#Rescue shell function
if [ $RECOVERYSH = "y" ] ; then
    echo "rescue_shell() {
    echo 0 > /proc/sys/kernel/printk
    busybox --install -s
    clear
    echo \"Dropping to a shell: \$1\"
    setsid cttyhack sh
}" >> $tmp/build/init

    echo "for item in \$(cat /proc/cmdline) ; do
    case "\$item" in
        rd.break|rdbreak)   rescue_shell \"Rescue rdbreak\" ;;
        init=/bin/sh|init=/bin/bb|init=/bin/bash|init=/bin/dash)    rescue_shell \"Rescue init=/bin/sh\" ;;
    esac
done" >> $tmp/build/init
fi

#Mounting real root
if [ $rootisluks = "0" ] && [ $YUBIOVERIDE = "y" ] && [ $YUBICHAL = "manual" ] ; then
#    echo "echo 0 > /proc/sys/kernel/printk
#echo \"Overide, tap Yubikey to start decryption.\"
#echo -n \"\$(ykchalresp -2H )\"" >> $tmp/build/init
    echo "YUBICHAL=manual, still needs implementation"
    exit 1
elif [ $rootisluks = "0" ] && [ $YUBIOVERIDE = "y" ] ; then
    echo "echo 0 > /proc/sys/kernel/printk
lsusb | grep -q \"$YUBIUSB\"
if [ \$? = 0 ] ; then
    echo \"Overide, tap Yubikey to start decryption.\"
    echo -n \"\$(ykchalresp -2H $YUBICHAL)\" | cryptsetup luksOpen \$(findfs UUID=$rootluksuuid) root
else
    cryptsetup luksOpen --tries 3 \$(findfs UUID=$rootluksuuid) root
fi
mount -o ro /dev/mapper/root /mnt/root" >> $tmp/build/init
elif [ $rootisluks = "0" ] ; then
    echo "echo 0 > /proc/sys/kernel/printk
cryptsetup luksOpen --tries 3 \$(findfs UUID=$rootluksuuid) root
mount -o ro /dev/mapper/root /mnt/root" >> $tmp/build/init
else
    echo "mount -o ro \$(findfs UUID=$rootuuid) /mnt/root" >> $tmp/build/init
fi


#Cleanup
echo "umount /proc
umount /sys
umount /dev" >> $tmp/build/init

#Switch to real root
echo "exec switch_root /mnt/root /sbin/init" >> $tmp/build/init

#Rescue shell
if [ $RECOVERYSH = "y" ] ; then
    echo "rescue_shell \"Switch_Root_Failed\"" >> $tmp/build/init
fi
}

echo "$tmp"
buildbasefn
buildinitfn
compressionfn

#echo -n "$YUBICHAL" | xxd -p -c 1 | awk '{$1=$1; gsub(/ /, ""); printf "%s", $0}' | ykman otp calculate 2



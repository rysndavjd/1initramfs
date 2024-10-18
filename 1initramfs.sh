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
    echo "      -d  (Output debug info)"
    echo "      -c  (Override using default config at /etc/default/1initramfs)"
    echo "      -o  (Override default output directory at /boot)"
    echo "      -e  (Will output initramfs at /usr/src/initramfs.cpio, to be embedded into a kernel)"    
    exit 0
}

#$1 = output some text
debugfn() {
    echo ""
    echo "$1"
    echo "PWD: $pwd"
    echo "TMP: $tmp"
    echo "VERSION: $shversion"
    echo "CONFIG: $config"
    echo "OUTPUT: $output"
    echo "EMBEDDED: $embedded"
    echo "RECOVERYSH: $RECOVERYSH"
    echo "COMPRESSION: $COMPRESSION"
    echo "YUBIOVERIDE: $YUBIOVERIDE"
    echo "YUBICHAL: $YUBICHAL"
    echo "YUBIUSB: $YUBIUSB"
    echo ""
}

while getopts d:o:eh flag ; do
    case "${flag}" in
        d) debug="0";;
        o) output="${OPTARG}";;
        e) embedded="0";;
        ?) helpfn;;
        h) helpfn;;
    esac
done

if [ "$debug" = "0" ] ; then
    debugfn "Starting values"
fi

if [ -z "${output+x}" ] ; then
    output="$pwd"
    echo "Output not set, outputing to $pwd"
fi

if [ "$embedded" = "0" ] ; then
    COMPRESSION="embedded"
elif [ -z "${COMPRESSION+x}" ] ; then
    COMPRESSION="none"
    echo "Compression not set, defaulting to none."
else
    echo "Compression set to $COMPRESSION."
fi

if [ "$YUBIOVERIDE" = "y" ] ; then
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

if cat /proc/mounts | grep -q devtmpfs || zcat /proc/config.gz | grep -q CONFIG_DEVTMPFS ; then
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

case $COMPRESSION in
    none)
        find . -print0 | cpio --quiet --null --create --format=newc > "$output"/initramfs.img ;;
    gzip)
        find . -print0 | cpio --quiet --null --create --format=newc | gzip --quiet --stdout > "$output"/initramfs.img ;;
    bzip2)
        find . -print0 | cpio --quiet --null --create --format=newc | bzip2 --quiet --compress --stdout > "$output"/initramfs.img ;;
    lzma)
        find . -print0 | cpio --quiet --null --create --format=newc | xz --quiet --compress --format=lzma --stdout > "$output"/initramfs.img ;;
    lz4)
        find . -print0 | cpio --quiet --null --create --format=newc | lz4 -z -q -l -c > "$output"/initramfs.img ;;
    zstd)
        find . -print0 | cpio --quiet --null --create --format=newc | zstd --quiet --format=zstd --stdout > "$output"/initramfs.img ;;
    embedded)
        find . -print0 | cpio --quiet --null --create --format=newc > "/usr/src/initramfs.cpio" ;;
    *)
        echo "Unknown: $COMPRESSION"
        exit 1 
    ;;
esac
}

if findmnt -n -o SOURCE / | grep -q /dev/mapper/ ; then 
    mapper=$(basename "$(findmnt -n -o SOURCE /)")
    rootmnt=$(cryptsetup status "$mapper" | grep device: | sed 's/device: //') 
else
    rootmnt=$(findmnt -n -o SOURCE /)
fi
rootuuid=$(blkid -s UUID -o value $rootmnt)
rootluksuuid=$(cryptsetup luksUUID $rootmnt)
rootisluks=$(cryptsetup isLuks $rootmnt ; echo -En $?)

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

if [ "$debug" = "0" ] ; then
    debugfn "Ending values"
fi


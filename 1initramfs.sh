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
    echo "      -k  (Specify kernel to include essential kernel modules for)"    
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
    echo "KMODULES: $KMODULES"
    echo "YUBIOVERIDE: $YUBIOVERIDE"
    echo "YUBICHAL: $YUBICHAL"
    echo "YUBIUSB: $YUBIUSB"
    echo ""
}

while getopts do:ek:h flag ; do
    case "${flag}" in
        d) debug="0";;
        o) output="${OPTARG}";;
        e) embedded="0";;
        k) kernelver="${OPTARG}";;
        ?) helpfn;;
        h) helpfn;;
    esac
done

#flag options
if [ $debug ] ; then
    debugfn "Starting values"
fi

if [ -z "${output+x}" ] ; then
    output="$pwd"
    echo "Output not set, outputing to $pwd"
fi

if [ $embedded ] ; then
    COMPRESSION="embedded"
fi

if ! [ -d /lib/modules/$kernelver ] ; then
    echo "Unable to find kernel directory at /lib/modules/$kernelver"
fi

if [ $KMODULES = "y" ] ; then
    echo "Kernel modules will be included into initramfs"
fi

#1initramfs.conf checks
if [ -z "${COMPRESSION+x}" ] ; then
    COMPRESSION="none"
    echo "Compression not set, defaulting to none."
else
    echo "Compression set to $COMPRESSION."
fi

if [ -z "${kernelver+x}" ] && [ "$KMODULES" = "y" ] ; then
    echo "Copying currently running kernels modules: $(uname -r)"
    kernelver="$(uname -r)"
    #if [ -f /proc/config.gz ] ; then
    #    kernelconf=$(zcat /proc/config.gz)
    #elif [ -f "/lib/modules/$kernelver/build/.config" ] ; then
    #    kernelconf=$(cat "/lib/modules/$kernelver/build/.config")
    #elif [ -f "/boot/config-$kernelver" ] ; then
    #    kernelconf=$(cat "/boot/config-$kernelver")
    #fi
elif [ "$KMODULES" = "y" ] ; then 
    echo "Copying specified kernel version modules: $kernelver"
    #if [ -f "/lib/modules/$kernelver/build/.config" ] ; then
    #    kernelconf=$(cat "/lib/modules/$kernelver/build/.config")
    #elif [ -f "/boot/config-$kernelver" ] ; then
    #    kernelconf=$(cat "/boot/config-$kernelver")
    #fi
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

#Functions

if findmnt -n -o SOURCE / | grep -q /dev/mapper/ ; then 
    mapper=$(basename "$(findmnt -n -o SOURCE /)")
    rootmnt=$(cryptsetup status "$mapper" | grep device: | sed 's/\tdevice: //') 
else
    rootmnt=$(findmnt -n -o SOURCE /)
fi
rootuuid=$(blkid -s UUID -o value $rootmnt)
rootfs=$(blkid -s TYPE -o value $(findmnt -n -o SOURCE /))
rootluksuuid=$(cryptsetup luksUUID $rootmnt)
rootisluks=$(cryptsetup isLuks $rootmnt ; echo -En $?)
rootluksalgo=$(cryptsetup luksDump $rootmnt | grep "cipher:" | sed 's/\tcipher: //')
rootlukshash=$(cryptsetup luksDump $rootmnt | grep "AF hash:" | sed 's/\tAF hash://')

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

#Copy optimisation modules for crypto modules for specific x86 extensions (AVX2, AVX512, etc)
copyaccelkmodfn() {

}

#Copy hash algoriums modules needed to decrypt rootfs
copyhashkmodfn() {
for item in $rootlukshash ; do 
    case $item in 

    esac
done
}

#Copy crypto algoriums needed to decrypt rootfs
copyalgokmodfn() {
for item in $rootluksalgo ; do
    case $item in 

    esac
done
}

#copy fs module to read root fs
copyfskmodfn() {
case $rootfs in
    ext4) 
        if modinfo -k $kernelver ext4 | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n ext4)) 
            cp "$(modinfo -k $kernelver -n ext4)" "$tmp/build/$(modinfo -k $kernelver -n ext4)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n jbd2)) 
            cp "$(modinfo -k $kernelver -n jbd2)" "$tmp/build/$(modinfo -k $kernelver -n jbd2)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n mbcache)) 
            cp "$(modinfo -k $kernelver -n mbcache)" "$tmp/build/$(modinfo -k $kernelver -n mbcache)"
        fi
    ;;
    jfs) 
        if modinfo -k $kernelver jfs | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n jfs)) 
            cp "$(modinfo -k $kernelver -n jfs)" "$tmp/build/$(modinfo -k $kernelver -n jfs)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n nls_ucs2_utils)) 
            cp "$(modinfo -k $kernelver -n nls_ucs2_utils)" "$tmp/build/$(modinfo -k $kernelver -n nls_ucs2_utils)"
        fi
    ;;
    xfs) 
        if modinfo -k $kernelver xfs | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n xfs)) 
            cp "$(modinfo -k $kernelver -n xfs)" "$tmp/build/$(modinfo -k $kernelver -n xfs)"
        fi
    ;;
    gfs2) 
        if modinfo -k $kernelver gfs2 | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n gfs2)) 
            cp "$(modinfo -k $kernelver -n gfs2)" "$tmp/build/$(modinfo -k $kernelver -n gfs2)"
        fi
    ;;
    ocfs2) 
        if modinfo -k $kernelver ocfs2 | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n ocfs2)) 
            cp "$(modinfo -k $kernelver -n ocfs2)" "$tmp/build/$(modinfo -k $kernelver -n ocfs2)"
        fi
    ;;
    btrfs) 
        if modinfo -k $kernelver btrfs | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n btrfs)) 
            cp "$(modinfo -k $kernelver -n btrfs)" "$tmp/build/$(modinfo -k $kernelver -n btrfs)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n raid6_pq)) 
            cp "$(modinfo -k $kernelver -n raid6_pq)" "$tmp/build/$(modinfo -k $kernelver -n raid6_pq)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n zstd_compress)) 
            cp "$(modinfo -k $kernelver -n zstd_compress)" "$tmp/build/$(modinfo -k $kernelver -n zstd_compress)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n lzo_compress)) 
            cp "$(modinfo -k $kernelver -n lzo_compress)" "$tmp/build/$(modinfo -k $kernelver -n lzo_compress)"
        fi
    ;;
    nilfs2) 
        if modinfo -k $kernelver nilfs2 | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n nilfs2)) 
            cp "$(modinfo -k $kernelver -n nilfs2)" "$tmp/build/$(modinfo -k $kernelver -n nilfs2)"
        fi
    ;;
    f2fs) 
        if modinfo -k $kernelver f2fs | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n f2fs)) 
            cp "$(modinfo -k $kernelver -n f2fs)" "$tmp/build/$(modinfo -k $kernelver -n f2fs)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n zstd_compress)) 
            cp "$(modinfo -k $kernelver -n zstd_compress)" "$tmp/build/$(modinfo -k $kernelver -n zstd_compress)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n lz4hc_compress)) 
            cp "$(modinfo -k $kernelver -n lz4hc_compress)" "$tmp/build/$(modinfo -k $kernelver -n lz4hc_compress)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n lzo_compress)) 
            cp "$(modinfo -k $kernelver -n lzo_compress)" "$tmp/build/$(modinfo -k $kernelver -n lzo_compress)"
        fi
    ;;
    bcachefs) 
        if modinfo -k $kernelver bcachefs | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n bcachefs)) 
            cp "$(modinfo -k $kernelver -n bcachefs)" "$tmp/build/$(modinfo -k $kernelver -n bcachefs)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n raid6_pq)) 
            cp "$(modinfo -k $kernelver -n raid6_pq)" "$tmp/build/$(modinfo -k $kernelver -n raid6_pq)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n zstd_compress)) 
            cp "$(modinfo -k $kernelver -n zstd_compress)" "$tmp/build/$(modinfo -k $kernelver -n zstd_compress)"
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n lz4hc_compress)) 
            cp "$(modinfo -k $kernelver -n lz4hc_compress)" "$tmp/build/$(modinfo -k $kernelver -n lz4hc_compress)"
        fi
    ;;
    ntfs) 
        if modinfo -k $kernelver ntfs3 | grep -q "(builtin)" ; then
            echo "$rootfs builtin."
        else
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n ntfs3)) 
            cp "$(modinfo -k $kernelver -n ntfs3)" "$tmp/build/$(modinfo -k $kernelver -n ntfs3)"
        fi
    ;;
    *) echo "Unknown fs: $rootfs" 
    exit 1 
    ;;
esac

mkdir -p "$tmp/build/lib/modules/$kernelver/kernel"
cp /lib/modules/$kernelver/modules.* "$tmp/build/lib/modules/$kernelver/"

}

#Function that runs all other copy functions for kernel modules and performs checks
copykmodfn() {

}

compressionfn () {
if [ $KMODULES = "y" ] ; then
    filename="initramfs-$kernelver.img"
else 
    filename="initramfs.img"
fi

cd "$tmp/build"
case $COMPRESSION in
    none)
        find . -print0 | cpio --quiet --null --create --format=newc > "$output/$filename" ;;
    gzip)
        find . -print0 | cpio --quiet --null --create --format=newc | gzip --quiet --stdout > "$output/$filename" ;;
    bzip2)
        find . -print0 | cpio --quiet --null --create --format=newc | bzip2 --quiet --compress --stdout > "$output/$filename" ;;
    lzma)
        find . -print0 | cpio --quiet --null --create --format=newc | xz --quiet --compress --format=lzma --stdout > "$output/$filename" ;;
    lz4)
        find . -print0 | cpio --quiet --null --create --format=newc | lz4 -z -q -l -c > "$output/$filename" ;;
    zstd)
        find . -print0 | cpio --quiet --null --create --format=newc | zstd --quiet --format=zstd --stdout > "$output/$filename" ;;
    embedded)
        find . -print0 | cpio --quiet --null --create --format=newc > "/usr/src/initramfs.cpio" ;;
    *)
        echo "Unknown: $COMPRESSION"
        exit 1 
    ;;
esac
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

if [ "$KMODULES" = "y" ] ; then
    copykmodfn
fi

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

availfsmod="ext4 jfs xfs gfs2 ocfs2 btrfs nilfs2 f2fs bcachefs ntfs"
# Inserting kernel modules
if [ "$KMODULES" = "y" ] ; then
    for item in $availfsmod ; do 
        if echo "$item" | grep -q "$rootfs" ; then
            echo "modprobe $item" >> $tmp/build/init
        fi
    done
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

buildbasefn
buildinitfn
compressionfn

if [ "$debug" ] ; then
    debugfn "Ending values"
fi


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
    echo "RECOVERYSH: $RECOVERYSH"
    echo "COMPRESSION: $COMPRESSION"
    echo "KMODULES: $KMODULES"
    echo "YUBIOVERIDE: $YUBIOVERIDE"
    echo "YUBICHAL: $YUBICHAL"
    echo "YUBIUSB: $YUBIUSB"
    echo "rootmnt: $rootmnt"
    echo "rootuuid: $rootuuid"
    echo "rootinterface: $rootinterface"
    echo "rootfs: $rootfs"
    echo "rootluksuuid: $rootluksuuid"
    echo "rootluksversion: $rootluksversion"
    echo "rootisluks: $rootisluks"
    echo "rootluksalgo: $rootluksalgo"
    echo "rootlukshash: $rootlukshash"
    echo ""
}

while getopts do:ek:h flag ; do
    case "${flag}" in
        d) debug="0";;
        o) output="${OPTARG}";;
        e) COMPRESSION="embedded";;
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
elif [ "$KMODULES" = "y" ] ; then 
    echo "Copying specified kernel version modules: $kernelver"
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
    rootmnt=$(cryptsetup status "$mapper" | grep device: | sed 's/device://' | tr -d '\t ') 
else
    rootmnt=$(findmnt -n -o SOURCE / | tr -d '\t ')
fi
rootuuid=$(blkid -s UUID -o value $rootmnt)
rootfs=$(blkid -s TYPE -o value $(findmnt -n -o SOURCE /))
rootinterface=$(lsblk -o TRAN -n $rootmnt | tr -d '\n')
rootisluks=$(cryptsetup isLuks $rootmnt ; echo -En $?)
if [ $rootisluks = 0 ] ; then
    rootluksuuid=$(cryptsetup luksUUID $rootmnt)
    rootluksversion=$(cryptsetup luksDump $rootmnt | grep Version: | sed 's/Version://' | tr -d '\t ')
    if echo $rootluksversion | grep -q 1 ; then
        ciphername=$(cryptsetup luksDump $rootmnt | grep "Cipher name:" | sed 's/Cipher name://' | tr -d '\t ')
        ciphermode=$(cryptsetup luksDump $rootmnt | grep "Cipher mode:" | sed 's/Cipher mode://' | tr -d '\t ')
        rootluksalgo="$ciphername-$ciphermode"
        rootlukshash=$(cryptsetup luksDump $rootmnt | grep "Hash spec:" | sed 's/Hash spec:[[:space:]]//')
    elif [ "$rootluksversion" = "2" ] ; then
        rootluksalgo=$(cryptsetup luksDump $rootmnt | grep "cipher:" | sed 's/\tcipher://' | tr -d '\t ')
        rootlukshash=$(cryptsetup luksDump $rootmnt | grep "AF hash:" | sed 's/\tAF hash://' | tr -d '\n')
    fi
fi

# $1 = absolute path of userspace binaries
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

#function to minimise repeation of code for copying kernel modules
kmodfn() {
    touch "$tmp/modprobe"
    if modinfo -k $kernelver "$1" | grep -q "ERROR" ; then
        echo "Module not found: $1"
    elif modinfo -k $kernelver "$1" | grep -q "(builtin)" ; then
        echo "$1 builtin."
    else
        echo "$1 copied."
        mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n "$1")) 
        cp "$(modinfo -k $kernelver -n "$1")" "$tmp/build/$(modinfo -k $kernelver -n "$1")"
        #Dependies of modules ($1) being checked
        deps=$(modinfo -k $kernelver "$1" | grep "depends:" | sed 's/,/ /g' | sed 's/depends://')
        for item in $deps ; do
            mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n $item)) 
            cp "$(modinfo -k $kernelver -n $item)" "$tmp/build/$(modinfo -k $kernelver -n $item)"
        done
        #Dependies of dependies modules being checked
        for item in $deps ; do
            subdeps=$(modinfo -k $kernelver "$item" | grep "depends:" | sed 's/,/ /g' | sed 's/depends://')
            for item in $subdeps ; do
                mkdir -p $tmp/build/$(dirname $(modinfo -k $kernelver -n $item)) 
                cp "$(modinfo -k $kernelver -n $item)" "$tmp/build/$(modinfo -k $kernelver -n $item)"
            done
        done
        echo "modprobe $1" >> "$tmp/modprobe"
    fi
}

#Resolves kernel modules for block devices
blockkmodfn() {
    case $rootinterface in
        sata)
            kmodfn libata
            kmodfn sd_mod
            kmodfn scsi_mod
        ;;
        nvme)
            kmodfn nvme
        ;;
        *)
            echo "Unknown block interface: $rootinterface"
            exit 1
        ;;
    esac
}

#resolves optimisation modules for crypto modules for specific x86 extensions (AVX2, AVX512, ssse3, etc)
#copycrytoaccelkmodfn() {
#
#}

#resolves hash algoriums modules needed to decrypt rootfs
copyhashkmodfn() {
    for item in $rootlukshash ; do 
        case $item in 
            sha1)
                kmodfn sha1_generic
            ;;
            sha3)
                kmodfn sha3_generic
            ;;
            sha224)
                kmodfn sha256_generic
            ;;
            sha256)
                kmodfn sha256_generic
            ;;
            sha384)
                kmodfn sha512_generic
            ;;
            sha512)
                kmodfn sha512_generic
            ;;
            ripemd160)
                kmodfn rmd160
            ;;
            whirlpool) 
                kmodfn wp512
            ;;
            *)
                echo "Unknown hash algorium: $item"
            ;;
        esac
    done
}

#resolves needed crypto algoriums to decrypt rootfs
copyalgokmodfn() {
    for item in $rootluksalgo ; do
            kmodfn dm-mod
            kmodfn dm-crypt
        if echo "$item" | grep -q "xts" ; then
            kmodfn xts
        elif echo "$item" | grep -q "cbc" ; then
            kmodfn cbc
        fi
        case $item in
            aes*)
                kmodfn aes_generic
            ;;
            aria*)
                kmodfn aria_generic
            ;;
            blowfish*)
                kmodfn blowfish_generic
            ;;
            camellia*)
                kmodfn camellia_generic
            ;;
            serpent*)
                kmodfn serpent_generic
            ;;
            twofish*)
                kmodfn twofish_generic
            ;;
            *)
                echo "Unknown Algorium used in xts mode of operation: $item" 
            ;;
        esac
    done
}

#resolves fs module to read root fs
copyfskmodfn() {
    case $rootfs in
        ext4) 
            kmodfn ext4
        ;;
        jfs) 
            kmodfn jfs
        ;;
        xfs) 
            kmodfn xfs
        ;;
        gfs2) 
            kmodfn gfs2    
        ;;
        ocfs2) 
            kmodfn ocfs2
        ;;
        btrfs) 
            kmodfn btrfs
        ;;
        nilfs2) 
            kmodfn nilfs2
        ;;
        f2fs) 
            kmodfn f2fs
        ;;
        bcachefs) 
            kmodfn bcachefs
        ;;
        ntfs) 
            kmodfn ntfs3 
        ;;
        *) echo "Unknown fs: $rootfs" 
        exit 1 
        ;;
    esac
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
    
    copybinsfn $(which busybox) 2>/dev/null

    if [ $rootisluks = 0 ] && [ $KMODULES = "y" ] ; then
        ldconfig -C "$tmp/build/etc/ld.so.cache"
        libgcc=$(ldconfig -p | grep libgcc_s.so.1 | awk '/ => / { print $4 }')
        for item in $libgcc ; do
            dir=$(dirname "$item")
            mkdir -p $tmp/build/$dir
            cp $item $tmp/build/$dir    
        done
        copybinsfn $(which cryptsetup) 2>/dev/null
    elif [ $rootisluks = 0 ] ; then
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

    # Inserting kernel modules
    if [ "$KMODULES" = "y" ] ; then
        cat "$tmp/modprobe" >> $tmp/build/init
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
if [ $KMODULES = "y" ] ; then
    mkdir -p "$tmp/build/lib/modules/$kernelver/kernel"
    cp /lib/modules/$kernelver/modules.* "$tmp/build/lib/modules/$kernelver/"
    blockkmodfn
    copyfskmodfn
    if [ $rootisluks = "0" ] ; then
        copyalgokmodfn
        copyhashkmodfn
    fi
fi
buildinitfn
compressionfn

if [ "$debug" ] ; then
    debugfn "Ending values"
fi


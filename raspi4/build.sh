#!/usr/bin/env bash

set -e
set -x

UBUNTU_DEFAULT_PORTS_URL="http://ports.ubuntu.com"
UBUNTU_PORTS_URL="$UBUNTU_DEFAULT_PORTS_URL"

TARGET_RELEASE=eoan
TARGET_ARCH=arm64

TARGET_BUILD_DIR="$(pwd)"/build
TARGET_EXPORT_DIR="$(pwd)"/export
TARGET_PKG_DIR="$(pwd)"/pkg
TARGET_ROOTFS_DIR="$TARGET_BUILD_DIR"/rootfs

export TZ=UTC

function usage {
    printf "Usage: $0 -a ARCH [-c] -r RELEASE\n"
    printf "\t-a\tAssign the target paltform arch\n"
    printf "\t-c\t[Optional] Enable cross build\n"
    printf "\t-h\t[Optional] Get usage info\n"
    printf "\t-m\t[Optional] Set use a mirror repo.\n"
    printf "\t-r\tAssign the Ubuntu release version\n"
    printf "\t-p\t[Optional] Set HTTP_PROXY and make apt use proxy, only support http. DONT end with a slash.\n"
    exit 1
}

function write_repo {  
cat <<EOM > $TARGET_ROOTFS_DIR/etc/apt/sources.list
deb ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE} main restricted universe multiverse
# deb-src ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE} main restricted universe multiverse
deb ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-updates main restricted universe multiverse
# deb-src ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-updates main restricted universe multiverse
deb ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-security main restricted universe multiverse
# deb-src ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-security main restricted universe multiverse
deb ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-backports main restricted universe multiverse
# deb-src ${UBUNTU_PORTS_URL}/ubuntu-ports/ ${TARGET_RELEASE}-backports main restricted universe multiverse
EOM
}

function write_apt_proxy {
    cat <<EOM > $TARGET_ROOTFS_DIR/etc/apt/apt.conf.d/20proxy
Acquire::Http::Proxy "$APT_PROXY";
Acquire::Https::Proxy "$APT_PROXY";
EOM
}

function add_ppas {
    if [ -f ${TARGET_PKG_DIR}/${TARGET_RELEASE}-ppas ]; then
        while IFS= read -r line
        do
            chroot $TARGET_ROOTFS_DIR add-apt-repository -y $line
        done < ${TARGET_PKG_DIR}/${TARGET_RELEASE}-ppas
    fi
}

function install_common_packages {
    if [ -f ${TARGET_PKG_DIR}/${TARGET_RELEASE}-packages ]; then
        PACKAGE_LIST=""
        while IFS= read -r line
        do
            PACKAGE_LIST="${PACKAGE_LIST} ${line}"
        done < ${TARGET_PKG_DIR}/common-packages
        chroot $TARGET_ROOTFS_DIR apt install -y $PACKAGE_LIST
    fi
}

function install_ukui_packages {
    if [ -f ${TARGET_PKG_DIR}/${TARGET_RELEASE}-packages ]; then
        PACKAGE_LIST=""
        while IFS= read -r line
        do
            PACKAGE_LIST="${PACKAGE_LIST} ${line}"
        done < ${TARGET_PKG_DIR}/ukui-packages
        chroot $TARGET_ROOTFS_DIR apt install -y $PACKAGE_LIST
    fi
}

function install_packages {
    if [ -f ${TARGET_PKG_DIR}/${TARGET_RELEASE}-packages ]; then
        PACKAGE_LIST=""
        while IFS= read -r line
        do
            PACKAGE_LIST="${PACKAGE_LIST} ${line}"
        done < ${TARGET_PKG_DIR}/${TARGET_RELEASE}-packages
        chroot $TARGET_ROOTFS_DIR apt install -y $PACKAGE_LIST
    fi
}

function build {
    if [ ! -z $REPO_MIRROR ]; then
        UBUNTU_PORTS_URL=$REPO_MIRROR
    else        
        UBUNTU_PORTS_URL="$UBUNTU_DEFAULT_PORTS_URL"
    fi
    echo "That will checkout packages from $UBUNTU_PORTS_URL"
    if [ ! -d $TARGET_ROOTFS_DIR ]; then
        mkdir -p $TARGET_ROOTFS_DIR
        if [ ! -z "$CROSS_ARCH" ]; then
            qemu-debootstrap --arch $TARGET_ARCH $TARGET_RELEASE $TARGET_ROOTFS_DIR $UBUNTU_PORTS_URL 
        else
            debootstrap $TARGET_RELEASE $TARGET_ROOTFS_DIR $UBUNTU_PORTS_URL
        fi
    fi
}

function mount_config {
    mount -t proc none $TARGET_ROOTFS_DIR/proc
    mount -t sysfs none $TARGET_ROOTFS_DIR/sys
}

function umount_config {
    umount $TARGET_ROOTFS_DIR/proc
    umount $TARGET_ROOTFS_DIR/sys
}

function hostname_config {
    echo ubuntukylin >$TARGET_ROOTFS_DIR/etc/hostname
}

function fstab_config {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
EOM
}

function hosts_config {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOM
}

function user_group_config {
    chroot $TARGET_ROOTFS_DIR adduser --gecos "UbuntuKylin user" --add_extra_groups --disabled-password ubuntukylin
    chroot $TARGET_ROOTFS_DIR usermod -a -G sudo,adm -p '$1$.NBXnqSb$e11MEXIT/6SCDt.fTKa2X/' ubuntukylin
}

function network_config {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d
# The loopback network interface
auto lo
iface lo inet loopback
# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp
EOM
}

function img_clean {
    chroot $TARGET_ROOTFS_DIR apt clean
    rm -f $TARGET_ROOTFS_DIR/etc/apt/sources.list.save
    rm -f $TARGET_ROOTFS_DIR/etc/apt/apt.conf.d/20proxy
    rm -f $TARGET_ROOTFS_DIR/etc/resolvconf/resolv.conf.d/original
    rm -rf $TARGET_ROOTFS_DIR/run
    mkdir -p $TARGET_ROOTFS_DIR/run
    rm -f $TARGET_ROOTFS_DIR/etc/*-
    rm -f $TARGET_ROOTFS_DIR/root/.bash_history
    rm -rf $TARGET_ROOTFS_DIR/tmp/*
    rm -f $TARGET_ROOTFS_DIR/var/lib/urandom/random-seed
    [ -L $TARGET_ROOTFS_DIR/var/lib/dbus/machine-id ] || rm -f $TARGET_ROOTFS_DIR/var/lib/dbus/machine-id
    rm -f $TARGET_ROOTFS_DIR/etc/machine-id
}

function genimage_name {
    EXPORT_IMAGE_NAME="ubuntukylin-${TARGET_RELEASE}-${TARGET_ARCH}-$(date +%Y-%m-%d).img"
}

function write_image_zero {
    dd if=/dev/zero of="${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME}" bs=1M count=1
    dd if=/dev/zero of="${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME}" bs=1M count=0 seek=4096
}

function genimage {
    genimage_name
    umount_config
    img_clean
    write_image_zero
    sfdisk -f "${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME}" <<EOM
unit: sectors

1 : start=     2048, size=   526336, Id= c, bootable
2 : start=   528384, size=  7862272, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM
    VFAT_LOOP="$(losetup -o 1M --sizelimit 256M -f --show ${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME})"
    EXT4_LOOP="$(losetup -o 257M --sizelimit 3840M -f --show ${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME})"
    mkfs.vfat "$VFAT_LOOP"
    mkfs.ext4 "$EXT4_LOOP"
    TARGET_MOUNT_DIR="$(pwd)/mount"
    mkdir -p "$TARGET_MOUNT_DIR"
    mount "$EXT4_LOOP" "$TARGET_MOUNT_DIR"
    mkdir -p "$TARGET_MOUNT_DIR/boot/firmware"
    mount "$VFAT_LOOP" "$TARGET_MOUNT_DIR/boot/firmware"
    echo "Sync rootfs to image..."
    rsync -a "$TARGET_ROOTFS_DIR/" "$TARGET_MOUNT_DIR/"
    umount "$TARGET_MOUNT_DIR"/boot/firmware
    umount "$TARGET_MOUNT_DIR"
    losetup -d "$EXT4_LOOP"
    losetup -d "$VFAT_LOOP"
    echo "Export target image to ${TARGET_EXPORT_DIR}/${EXPORT_IMAGE_NAME} ."
    exit 1
}

function rootfs_config {
    fix_rapsi2_firmware
    umount_config
    mount_config
    
    if [ ! -z $REPO_MIRROR ]; then
        UBUNTU_PORTS_URL=$REPO_MIRROR
        echo "Target rootfs will checkout packages from $UBUNTU_PORTS_URL"
    else
        UBUNTU_PORTS_URL=$UBUNTU_DEFAULT_PORTS_URL
    fi
    
    write_repo

    if [ ! -z $APT_PROXY ]; then
        write_apt_proxy
    fi

    chroot $TARGET_ROOTFS_DIR apt update

    install_common_packages
    add_ppas
    install_ukui_packages
    install_packages
    chroot $TARGET_ROOTFS_DIR apt upgrade
    UBUNTU_PORTS_URL=$UBUNTU_DEFAULT_PORTS_URL
    wirte_repo
    hostname_config
    fstab_config
    hosts_config
    user_group_config
    network_config
}

function fix_rapsi2_firmware {
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/firmware
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/firmware/overlays
}


function checkenv {
    echo "Build on: $(uname -m)"
    echo "Target release: $TARGET_RELEASE"
    echo "Target arch: $TARGET_ARCH"
    echo "Target rootfs path: $TARGET_ROOTFS_DIR"

    mkdir -p $TARGET_EXPORT_DIR

    if [ ! -z $proxy ]; then
        export http_proxy=$proxy
        export https_proxy=$proxy
    fi

    if [ -d $TARGET_BUILD_DIR ]; then
        echo "Detected last build cache."
        
        read -p "Do you wish to Remove cache/reBuild/Cancel(R/B/C)? " RBC 
        case $RBC in
            [Rr]* ) sudo rm -rf $TARGET_BUILD_DIR
                    build
                    ;;
            [Bb]* ) ;;   
            [Cc]* ) exit 1
                    ;;
            * ) echo "Please answer R/B/C."
                ;;
        esac
    else
        mkdir -p $TARGET_BUILD_DIR
        build
    fi
}

while getopts ":a:c:h:m:p:r:" o; do
    case "${o}" in
        a) TARGET_ARCH=${OPTARG}
           ;;
        c) CROSS_ARCH=1
           ;;
        h) usage
           ;;
        m) REPO_MIRROR=${OPTARG}
           ;;
        p) proxy=${OPTARG}
           APT_PROXY=$proxy
           ;;
        r) TARGET_RELEASE=${OPTARG}
           ;;
        *) usage
           ;;
    esac
done
shift $((OPTIND-1))

checkenv

rootfs_config
genimage

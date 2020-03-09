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

function rootfs_config {
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
}


function checkenv {
    echo "Build on: $(uname -m)"
    echo "Target release: $TARGET_RELEASE"
    echo "Target arch: $TARGET_ARCH"
    echo "Target rootfs path: $TARGET_ROOTFS_DIR"

    mkdir -p $TARGET_EXPORT_DIR

    if [ -z $proxy ]; then
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

while getopts ":a:c:h:p:r:" o; do
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

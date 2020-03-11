#!/usr/bin/env bash

function align_usage_args() {
    printf "\t$1\t$2\n"
}

function usage() {
    printf "ukarmimg --- UubuntuKylin ARM Image generate helper\n\n"
    printf "Usage:\n\t$0 -a ARCH -p PLATFORM -r RELEASE\n"
    printf "\t$0 --arch ARCH --platform --release RELEASE\n\n"
    echo "Required arguments:"
    align_usage_args "-a, --arch" "Set the target platform architectrue"
    align_usage_args "-p, --platform" "Select the platform which you want to generate"
    align_usage_args "-r, --release" "Choose a valid Ubuntu release version\n"
    echo "Optional arguments:"
    align_usage_args "-c, --cross" "Enable cross platform build"
    align_usage_args "-h, --help" "Show usage infomation"
    align_usage_args "-m, --mirror" "Set a repository mirror"
    align_usage_args "-o, --out" "Place the image will export"
    align_usage_args "-P, --proxy" "Set HTTP_RPOXY and make apt use proxy, Only support http. DONT end with a slash"
    align_usage_args "-s, --suffix" "Set exported image name suffix"
    exit 1

}

UKARMIMG_HOME="$(pwd)"
COMMON_DIR=${UKARMIMG_HOME}/common
BUILD_DIR=${UKARMIMG_HOME}/build
EXPORT_DIR=${UKARMIMG_HOME}/export
PACKAGES_LIST_DIR=${UKARMIMG_HOME}/packages
REPOS_LIST_DIR=${UKARMIMG_HOME}/repos

UBUNTU_DEFAULT_REPO_URL="http://ports.ubuntu.com"
UBUNTU_REPO_URL="$UBUNTU_DEFAULT_REPO_URL"

SUFFIX=""

export TZ=UTC

declare -A ARCH_LIST
for constant in armhf arm64
do
    ARCH_LIST[$constant]=1
done

declare -A RELEASE_LIST
for constant in eoan focal
do
    RELEASE_LIST[$constant]=1
done

declare -A PLATFORM_LIST
for constant in raspi4 kunpeng feiteng
do
    PLATFORM_LIST[$constant]=1
done

ARGPOS=()
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -a|--arch)
            TARGET_ARCH="$2"
            shift
            shift
            ;;
        -c|--cross)
            CROSS_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            shift
            ;;
        -m|--mirror)
            REPO_MIRROR="$2"
            shift
            shift
            ;;
        -o|--out)
            TARGET_EXPORT_NAME="$2"
            shift
            shift
            ;;
        -P|--proxy)
            NET_PROXY="$2"
            APT_PROXY="$NET_PROXY"
            shift
            shift
            ;;
        -p|--platform)
            TARGET_PLATFORM="$2"
            shift
            shift
            ;;
        -r|--release)
            TARGET_RELEASE="$2"
            shift
            shift
            ;;
        -s|--suffix)
            TARGET_EXPORT_NAME_SUFFIX="$2"
            shift
            shift
            ;;
        *)
            ARGPOS+=("$1")
            usage
            shift
            ;;
    esac
done
set -- "${ARGPOS[@]}"

GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[0;37m'
YELLOW='\033[0;33m'
RESET='\033[0m'

function error() {
    echo -e "${RED}Error: $1${RESET}"
    exit 0
}

function success() {
    echo -e "${GREEN}Success: $1${RESET}"
    return
}

function warning() {
    echo -e "${YELLOW}Warning: $1${RESET}"
    return
}

function wecho() {
    echo -e "${WHITE}$1${RESET}"
    return
}

function set_proxy() {
    if [ ! -z ${NET_PROXY} ]; then
        export http_proxy=$NET_PROXY
        export https_proxy=$NET_PROXY
    fi
    return
}

function check_package() {
    dpkg -s $1 &> /dev/null
    if [ $? -eq 1 ]; then
        error "Dependence $1 is not installed"
    fi
    return
}

function check_target() {
    [[ -z ${TARGET_ARCH} ]] && error "-a or --arch argument unspecified"
    [[ -z ${TARGET_PLATFORM} ]] && error "-p or --platform argument unspecified"
    [[ -z ${TARGET_RELEASE} ]] && error "-r or --release argument unspecified"
    [[ ! ${PLATFORM_LIST[$TARGET_PLATFORM]} ]] && error "Unsupported platform    $TARGET_PLATFORM"
    [[ ! ${ARCH_LIST[$TARGET_ARCH]} ]] && error "Unsupported arch    $TARGET_ARCH"
    [[ ! ${RELEASE_LIST[$TARGET_RELEASE]} ]] && error "Unsupported release    $TARGET_RELEASE"
    check_package "debootstrap"
    check_package "qemu-user-static"
    check_package "squashfs-tools"
    check_package "genisoimage"
    wecho "Target Platform: $TARGET_PLATFORM"
    wecho "Target Architectrue: $TARGET_ARCH"
    wecho "Target Release: $TARGET_RELEASE"
    return
}

function check_target_directory() {
    [ ! -d ${BUILD_DIR} ] && wecho "$BUILD_DIR is not exist, create it."
    mkdir -p "$BUILD_DIR"
    [ ! -d ${EXPORT_DIR} ] && wecho "$BUILD_DIR is not exist, create it."
    mkdir -p "$EXPORT_DIR"
    TARGET_BUILD_DIR="$BUILD_DIR/$TARGET_PLATFORM/$TARGET_RELEASE"
    [ ! -d ${TARGET_BUILD_DIR} ] && wecho "$TARGET_BUILD_DIR is not exist, create it."
    mkdir -p $TARGET_BUILD_DIR
    TARGET_ROOTFS_DIR="$TARGET_BUILD_DIR/rootfs"
    [ ! -d ${TARGET_ROOTFS_DIR} ] && wecho "$TARGET_ROOTFS_DIR is not exist, create it."
    mkdir -p $TARGET_ROOTFS_DIR
    TARGET_MOUNT_DIR="$TARGET_BUILD_DIR/mount"
    [ ! -d ${TARGET_MOUNT_DIR} ] && wecho "$TARGET_MOUNT_DIR is not exist, create it."
    mkdir -p $TARGET_MOUNT_DIR
    TARGET_EXPORT_DIR="$EXPORT_DIR/$TARGET_PLATFORM"
    [ ! -d ${TARGET_EXPORT_DIR} ] && wecho "$TARGET_EXPORT_DIR is not exist, create it."
    mkdir -p $TARGET_EXPORT_DIR
    [ ! -d ${PACKAGES_LIST_DIR} ] && warning "Can not found packages list file"
    [ ! -d ${REPOS_LIST_DIR} ] && warning "Can not found repos list file"
    success "All check pass"
}

function build_base_rootfs(){
    wecho "Install base rootfs..."
    [[ ! -z ${REPO_MIRROR} ]] && UBUNTU_REPO_URL=$REPO_MIRROR
    if [ -z ${CROSS_BUILD} ]; then
        debootstrap $TARGET_RELEASE $TARGET_ROOTFS_DIR $UBUNTU_REPO_URL 1> /dev/null
    else
        qemu-debootstrap --arch $TARGET_ARCH $TARGET_RELEASE $TARGET_ROOTFS_DIR $UBUNTU_REPO_URL 1> /dev/null
    fi
    success "base rootfs install success"
}

function build_rootfs() {
    if [ -z  "$(ls -A $TARGET_ROOTFS_DIR)" ]; then
        build_base_rootfs
    else
        warning "Detected last build cache."
        read -p "Do you wish to Remove cache/Ignore/Cancel(R/I/C)? " RIC 
        case $RIC in
            [Rr]* )
                sudo rm -rf $TARGET_ROOTFS_DIR
                mkdir -p $TARGET_ROOTFS_DIR
                build_base_rootfs
                ;;
            [Ii]* )
                warning "Use rootfs cache"
                ;;   
            [Cc]* )
                success "Cancel generate "
                exit 1
                ;;
            * ) echo "Please answer R/B/C."
                ;;
        esac
    fi
    return
}

function install_packages_list_from_file() {
    PACKAGE_LIST=""
    while IFS= read -r line
    do
        PACKAGE_LIST="${PACKAGE_LIST} ${line}"
    done < ${1}
    chroot $TARGET_ROOTFS_DIR apt install -q -y $PACKAGE_LIST > /dev/null 2>&1
    chroot $TARGET_ROOTFS_DIR apt -f install -q -y > /dev/null 2>&1
    return
}

function check_packages_list_from_file() {
    PACKAGE_LIST=""
    while IFS= read -r line
    do
        PACKAGE_LIST="${PACKAGE_LIST} ${line}"
    done < ${1}
    chroot $TARGET_ROOTFS_DIR dpkg -s $PACKAGE_LIST &> /dev/null
    if [ $? -eq 1 ]; then
        error "Check failed. Some packages in ${1} is not installed"
    fi
    return
}

function check_rootfs_package() {
    chroot $TARGET_ROOTFS_DIR dpkg -s $1 &> /dev/null
    if [ $? -eq 1 ]; then
        error "Check failed. ${1} is not installed"
    fi
    return
}

function install_package() {
    chroot $TARGET_ROOTFS_DIR apt install -q -y $1 > /dev/null 2>&1
    chroot $TARGET_ROOTFS_DIR apt -f install -q -y > /dev/null 2>&1
    return
}

function add_ppas_list_from_file() {
    while IFS= read -r line
    do
        chroot $TARGET_ROOTFS_DIR add-apt-repository -y $line > /dev/null 2>&1
    done < ${1}
    return
}

function fix_linux_firmware_raspi2_dir() {
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/firmware
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/firmware/overlays
    return
}

function umount_after_check() {
    if mount | grep $1 > /dev/null; then
        umount $1
    fi
    return
}

function mount_sys_proc {
    mount -t proc none $TARGET_ROOTFS_DIR/proc
    mount -t sysfs none $TARGET_ROOTFS_DIR/sys
    return
}

function umount_sys_proc {
    umount_after_check "$TARGET_ROOTFS_DIR/proc"
    umount_after_check "$TARGET_ROOTFS_DIR/sys"
    return
}

function set_repo() {
    cat <<EOM > $TARGET_ROOTFS_DIR/etc/apt/sources.list
deb ${1}/ubuntu-ports/ ${2} main restricted universe multiverse
# deb-src ${1}/ubuntu-ports/ ${2} main restricted universe multiverse
deb ${1}/ubuntu-ports/ ${2}-updates main restricted universe multiverse
# deb-src ${1}/ubuntu-ports/ ${2}-updates main restricted universe multiverse
deb ${1}/ubuntu-ports/ ${2}-security main restricted universe multiverse
# deb-src ${1}/ubuntu-ports/ ${2}-security main restricted universe multiverse
deb ${1}/ubuntu-ports/ ${2}-backports main restricted universe multiverse
# deb-src ${1}/ubuntu-ports/ ${2}-backports main restricted universe multiverse
EOM
}

function set_apt_proxy() {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/apt/apt.conf.d/20proxy
Accquire::Http::Proxy "${APT_PROXY}";
Accquire::Https::Proxy "${APT_PROXY}";
EOM
}

function set_hostname {
    echo kylin >$TARGET_ROOTFS_DIR/etc/hostname
}

function set_fstab {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
EOM
}

function set_hosts {
    cat <<EOM >$TARGET_ROOTFS_DIR/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOM
}

function set_user {
    if chroot $TARGET_ROOTFS_DIR id -u kylin > /dev/null 2>&1; then
        warning "User `kylin` existed, skip create it."
	    return
    fi
    chroot $TARGET_ROOTFS_DIR useradd kylin --create-home --password "$(openssl passwd -1 "123123")" --shell /bin/bash --user-group
    chroot $TARGET_ROOTFS_DIR usermod -a -G sudo,adm kylin
}

function set_net_interface {
    mkdir -p $TARGET_ROOTFS_DIR/etc/network
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

function rpi_boot_config() {
    cp $COMMON_DIR/* $TARGET_ROOTFS_DIR/boot/firmware
    VMLINUZ="$(ls -1 $TARGET_ROOTFS_DIR/boot/vmlinuz-* | sort | tail -n 1)"
    [ -z "$VMLINUZ" ] && error "vmlinuz is not existed."
    cp $VMLINUZ $TARGET_ROOTFS_DIR/boot/firmware/kernel8.img
    INITRD="$(ls -1 $TARGET_ROOTFS_DIR/boot/initrd.img-* | sort | tail -n 1)"
    [ -z "$INITRD" ] && error "initrd is not existed."
    cp $INITRD $TARGET_ROOTFS_DIR/boot/firmware/initrd.img
}

function rootfs_configure_raspi4() {
    wecho "Now will do target rootfs configuratoin"
    fix_linux_firmware_raspi2_dir
    umount_sys_proc
    mount_sys_proc
    if [ ! -z ${REPO_MIRROR} ]; then
        set_repo "$REPO_MIRROR" $TARGET_RELEASE
    else
        set_repo "$UBUNTU_DEFAULT_REPO_URL" $TARGET_RELEASE
    fi
    [ ! -z ${APT_PROXY} && set_apt_proxy
    wecho "Install necessary package."
    chroot $TARGET_ROOTFS_DIR apt update -q > /dev/null 2>&1
    install_package software-properties-common
    install_package ubuntu-keyring
    add_ppas_list_from_file "${REPOS_LIST_DIR}/${TARGET_PLATFORM}/${TARGET_RELEASE}-ppas"
    install_packages_list_from_file "${PACKAGES_LIST_DIR}/${TARGET_PLATFORM}/${TARGET_RELEASE}-packages"
    check_packages_list_from_file "${PACKAGES_LIST_DIR}/${TARGET_PLATFORM}/${TARGET_RELEASE}-packages"
    success "packages install finished"
    set_repo "$UBUNTU_DEFAULT_REPO_URL" $TARGET_RELEASE
    set_hostname
    set_fstab
    set_hosts
    set_user
    set_net_interface
    rpi_boot_config
}

function rootfs_configure_feiteng() {
    wecho "Do nothing"
    return
}

function rootfs_configure_kunpeng() {
    wecho "Do nothing"
    return
}

function rootfs_configure() {
    case $TARGET_PLATFORM in
        "feiteng")
            rootfs_configure_fetiteng
            ;;
        "kunpeng")
            rootfs_configure_kunpeng
            ;;
        "raspi4")
            rootfs_configure_raspi4
            ;;
    esac
}

function gen_image_name() {
    EXPORT_IMAGE_NAME="ubuntukylin-${TARGET_PLATFORM}-${TARGET_RELEASE}-${TARGET_ARCH}-$(date +%Y-%m-%d).img"
}

function gen_raspi4_img() {
    gen_image_name
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
    umount_sys_proc
    mkdir -p ${EXPORT_DIR}/${TARGET_PLATFORM}
    dd if=/dev/zero of="${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME}" bs=1M count=1
    dd if=/dev/zero of="${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME}" bs=1M count=0 seek=4096
    sfdisk -f "${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME}" <<EOM
unit: sectors

1 : start=     2048, size=   526336, Id= c, bootable
2 : start=   528384, size=  7862272, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM
    VFAT_LOOP="$(losetup -o 1M --sizelimit 256M -f --show ${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME})"
    EXT4_LOOP="$(losetup -o 257M --sizelimit 3840M -f --show ${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME})"
    mkfs.vfat "$VFAT_LOOP"
    mkfs.ext4 "$EXT4_LOOP"
    mount "$EXT4_LOOP" "$TARGET_MOUNT_DIR"
    mkdir -p "$TARGET_MOUNT_DIR/boot/firmware"
    mount "$VFAT_LOOP" "$TARGET_MOUNT_DIR/boot/firmware"
    wecho "Sync rootfs to image..."
    rsync -a "$TARGET_ROOTFS_DIR/" "$TARGET_MOUNT_DIR/"
    umount "$TARGET_MOUNT_DIR"/boot/firmware
    umount "$TARGET_MOUNT_DIR"
    losetup -d "$EXT4_LOOP"
    losetup -d "$VFAT_LOOP"
    success "Export target image to ${EXPORT_DIR}/${TARGET_PLATFORM}/${EXPORT_IMAGE_NAME}."
    exit 1
}

function export_file() {
    case $TARGET_PLATFORM in
        "feiteng")
            
            ;;
        "kunpeng")
            
            ;;
        "raspi4")
            gen_raspi4_img
            ;;
    esac
    return
}

check_target
check_target_directory
set_proxy
build_rootfs
rootfs_configure
export_file

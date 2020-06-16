#!/usr/bin/env bash

UKARMIMG_HOME="$(dirname $(cd `dirname $0`; pwd))"
#BIN_DIR=${UKARMIMG_HOME}/bin
BUILD_DIR=${UKARMIMG_HOME}/build
CONFIG_DIR=${UKARMIMG_HOME}/config
EXPORT_DIR=${UKARMIMG_HOME}/export
LIB_DIR=${UKARMIMG_HOME}/lib
PACKAGES_DIR=${UKARMIMG_HOME}/packages
REPOS_DIR=${UKARMIMG_HOME}/repos
UBOOT_DIR=${UKARMIMG_HOME}/uboot

UBUNTU_DEFAULT_REPO="http://ports.ubuntu.com"
REPO_URL="$UBUNTU_DEFAULT_REPO"

if [ -f "$LIB_DIR/functions" ]; then
    . "${LIB_DIR}/functions"
fi

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
for constant in raspi4 kunpeng feiteng general
do
    PLATFORM_LIST[$constant]=1
done

function check_arch_valid() {
    if [ ! ${ARCH_LIST[$TARGET_ARCH]} ]; then
        error "Unsupported archtecture: $TARGET_ARCH"
    fi
}

function check_platform_valid() {
    if [ ! ${PLATFORM_LIST[$TARGET_PLATFORM]} ]; then
        error "Unsupported platform: $TARGET_PLATFORM"
    fi
}

function check_release_valid() {
    if [ ! ${RELEASE_LIST[$TARGET_PLATFORM]} ]; then
        error "Unsupported release: $TARGET_RELEASE"
    fi
}

function usage() {
    echo -e "ukarmimg --- UubuntuKylin ARM Image generate helper\n"
    echo -e "Usage:\n\t$0 -a ARCH -p PLATFORM -r RELEASE"
    echo -e "\t$0 --arch ARCH --platform --release RELEASE\n"
    echo "Required arguments:"
    align_usage_args "-a, --arch" "Set the target platform architectrue"
    align_usage_args "-d, --rootfs-dir" "Use a local rootfs"
    align_usage_args "-p, --platform" "Select the platform which you want to generate"
    align_usage_args "-r, --target-release" "Choose a valid Ubuntu release version"
    echo "Optional arguments:"
    align_usage_args "-c, --cross-arch" "Enable cross platform build"
    align_usage_args "-h, --help" "Show usage infomation"
    align_usage_args "-m, --mirror" "Set a repository mirror"
    align_usage_args "-o, --out" "Place the image will export"
    align_usage_args "-P, --proxy" "Set HTTP_RPOXY and make apt use proxy, Only support http. DONT end with a slash"
    align_usage_args "-s, --export-suffix" "Set exported image name suffix"
    exit 1
}

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
        -c|--cross-arch)
            CROSS_BUILD=1
            shift
            ;;
        -d|--rootfs-dir)
            LOCAL_ROOTFS_DIR="$2"
            shift
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
            EXPORT_FILE_NAME="$2"
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
        -r|--target-release)
            TARGET_RELEASE="$2"
            shift
            shift
            ;;
        -s|--export-suffix)
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

function check_environment(){ 
    wecho "check environment"
    check_var_will_error "$TARGET_ARCH" "-a or --arch argument unspecified"
    check_var_will_error "$TARGET_PLATFORM" "-p or --platform argument unspecified"
    check_var_will_error "$TARGET_RELEASE" "-r or --release argument unspecified"
    if ! check_var_will_bool "$LOCAL_ROOTFS_DIR"  ; then
        check_arch_valid
        check_platform_valid
        host_check_package "debootstrap"
        if ! check_var_will_bool $CROSS_BUILD ; then
            host_check_package "qemu-user-static"
        fi
    fi
    if [ "$TARGET_PLATFORM" != "raspi4" ]; then
        host_check_package "squashfs-tools"
        host_check_package "genisoimage"
    fi
    host_check_directory_will_warning "$BUILD_DIR"
    host_check_directory_will_warning "$EXPORT_DIR"
    TARGET_BUILD_DIR="$BUILD_DIR/$TARGET_PLATFORM/$TARGET_RELEASE"
    host_check_directory_will_warning "$TARGET_BUILD_DIR" 
    TARGET_EXPORT_DIR="$EXPORT_DIR/$TARGET_PLATFORM/$TARGET_RELEASE"
    host_check_directory_will_warning "$TARGET_EXPORT_DIR"
    if check_var_will_bool "$LOCAL_ROOTFS_DIR" ; then
        TARGET_ROOTFS_DIR="$LOCAL_ROOTFS_DIR"
    else
        TARGET_ROOTFS_DIR="$TARGET_BUILD_DIR/rootfs"
        host_check_directory_will_warning "$TARGET_ROOTFS_DIR"
    fi
    TARGET_MOUNT_DIR="$TARGET_BUILD_DIR/mount"
    host_check_directory_will_warning "$TARGET_MOUNT_DIR"
    host_check_directory_will_error "$REPOS_DIR"
    host_check_directory_will_error "$PACKAGES_DIR"
    success "environment check passed"
}

function build_base_rootfs(){
    wecho "Install base rootfs..."
    if check_var_will_bool "$REPO_MIRROR"; then
        REPO_URL=$REPO_MIRROR
    fi
    if check_var_will_bool "$NET_PROXY"; then
        export http_proxy="$NET_PROXY"
        export https_proxy="$NET_PROXY"
    fi
    if check_var_will_bool $CROSS_BUILD ; then
        sudo qemu-debootstrap --arch "$TARGET_ARCH" "$TARGET_RELEASE" "$TARGET_ROOTFS_DIR" "$REPO_URL" 1> /dev/null
    else
        sudo debootstrap "$TARGET_RELEASE" "$TARGET_ROOTFS_DIR" "$REPO_URL" 1> /dev/null
    fi
    success "base rootfs install success"
}

function build_rootfs() {
    if [ -z  "$(ls -A "$TARGET_ROOTFS_DIR")" ]; then
        build_base_rootfs
    else
        if check_var_will_bool "$LOCAL_ROOTFS_DIR" ; then
            warning "It seems that will use local rootfs."
            read -rp "Do you wish to Rebuild/Ignore/Cancel(R/I/C)? "
        else
            warning "Detected last build cache."
            read -rp "Do you wish to Remove cache/Ignore/Cancel(R/I/C)? " RIC
        fi
        case $RIC in
            [Rr]* )
                sudo rm -rf "$TARGET_ROOTFS_DIR"
                host_check_directory_will_warning "$TARGET_ROOTFS_DIR"
                build_base_rootfs
                ;;
            [Ii]* )
                if check_var_will_bool "$LOCAL_ROOTFS_DIR" ; then
                    warning "Use existed rootfs, skip build rootfs"
                else
                    warning "Use rootfs cache, skip build rootfs"
                fi
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

function configure_rootfs() {
    if check_var_will_bool "$TARGET_ARCH"; then
        case $TARGET_ARCH in
            "arm64"|"armhf")
                if check_var_will_bool "$TARGET_PLATFORM"; then
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
                else
                    error "Unspecificed platform" 
                fi
                ;;
            "x86"|"amd64")
                wecho "do nothing"
                ;;
        esac
    fi
}

function rootfs_configure_feiteng() {
    wecho "Do nothing"
    return
}

function rootfs_configure_kunpeng() {
    wecho "Do nothing"
    return
}

function rootfs_configure_raspi4() {
    wecho "Start rootfs configure"
    auto_umount "$TARGET_ROOTFS_DIR/proc"
    auto_umount "$TARGET_ROOTFS_DIR/sys"
    sudo mount -t proc none "$TARGET_ROOTFS_DIR/proc"
    sudo mount -t sysfs none "$TARGET_ROOTFS_DIR/sys"
    chroot_check_directory_will_warning "$TARGET_ROOTFS_DIR" "${TARGET_ROOTFS_DIR}/boot/firmware"
    chroot_copy_file_to_directory "${UBOOT_DIR}/${TARGET_PLATFORM}/*" "${TARGET_ROOTFS_DIR}/boot/firmware"
    if check_var_will_bool "$REPO_MIRROR"; then
        REPO_URL="$REPO_MIRROR"
    fi
    wecho "use $REPO_URL repo site" 
    if check_var_will_bool "$APT_PROXY"; then
        wecho "apt will use proxy: $APT_PROXY"
        chroot_check_file_will_warning "$TARGET_ROOTFS_DIR" "/etc/apt/apt.conf.d/20proxy"
        chroot_echo_to_file "$TARGET_ROOTFS_DIR"     "/etc/apt/apt.conf.d/20proxy" "Acquire::Http::Proxy \"${APT_PROXY}\";"
        chroot_echo_append_file "$TARGET_ROOTFS_DIR" "/etc/apt/apt.conf.d/20proxy" "Acquire::Https::Proxy \"${APT_PROXY}\";"
    fi
    wecho "Install necessary packages"
    chroot_apt_update "$TARGET_ROOTFS_DIR"
    chroot_install_package "$TARGET_ROOTFS_DIR" "software-properties-common"
    chroot_install_package "$TARGET_ROOTFS_DIR" "ubuntu-keyring"
    chroot_add_ppa_from_file "$TARGET_ROOTFS_DIR" "${REPOS_DIR}/{$TARGET_PLATFORM}/${TARGET_RELEASE}-ppas"
    chroot_install_packages_from_file "$TARGET_ROOTFS_DIR" "${PACKAGES_DIR}/{$TARGET_PLATFORM}/${TARGET_RELEASE}-packages.install"
    chroot_remove_packages_from_file "$TARGET_ROOTFS_DIR" "${PACKAGES_DIR}/{$TARGET_PLATFORM}/${TARGET_RELEASE}-packages.remove"
    success "install packages finished"
    chroot_set_apt_sources "$TARGET_ROOTFS_DIR" "$REPO_URL" "$TARGET_RELEASE"
    chroot_echo_to_file "$TARGET_ROOTFS_DIR" "/etc/hostname" "kylin"
    chroot_copy_config_to_file "$TARGET_ROOTFS_DIR" "${CONFIG_DIR}/${TARGET_PLATFORM}/fstab" "/etc/fstab"
    chroot_copy_config_to_file "$TARGET_ROOTFS_DIR" "${CONFIG_DIR}/${TARGET_PLATFORM}/hosts" "/etc/hosts"
    chroot_check_directory_will_warning "$TARGET_ROOTFS_DIR" "/etc/network"
    chroot_copy_config_to_file "$TARGET_ROOTFS_DIR" "${CONFIG_DIR}/${TARGET_PLATFORM}/interfaces" "/etc/network/interfaces"
    chroot_create_user "$TARGET_ROOTFS_DIR" "kylin" "123123"
    success "rootfs configure finished"
}

function clean_rootfs_raspi4() {
    chroot_apt_clean "$TARGET_ROOTFS_DIR"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/apt/sources.list.save"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/apt/apt.conf.d/20proxy"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/resolvconf/resolv.conf.d/original"
    chroot_remove_directory "$TARGET_ROOTFS_DIR" "/run"
    chroot_check_directory_will_warning "$TARGET_ROOTFS_DIR" "/run"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/*-"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/root/.bash_history"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/tmp/*"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/var/lib/urandom/random-seed"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/var/lib/dbus/machine-id"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/machine-id"
    chroot_remove_package "$TARGET_ROOTFS_DIR" "tsocks"
    chroot_remove_file "$TARGET_ROOTFS_DIR" "/etc/tsocks.conf"
}

function clean_rootfs() {
    case $TARGET_ARCH in
        "arm64" | "armhf" )
            case $TARGET_PLATFORM in
                "feiting" )
                    wecho "TODO"
                    ;;
                "kunpeng" )
                    wecho "TODO"
                    ;;
                "raspi4" )
                    clean_rootfs_raspi4
                    ;;
            esac
            ;;
        "x86" | "amd64" )
            wecho "do nothing"
            ;;
        * )
            error "can not clean rootfs for unsupported architectrue: $TARGET_ARCH"
            ;;
    esac
}

function generate_export_file_name() {
    if check_var_will_bool "$EXPORT_FILE_NAME"; then
        wecho "export image name: $EXPORT_FILE_NAME"
    else
        if check_var_will_bool "$TARGET_EXPORT_NAME_SUFFIX"; then
            EXPORT_FILE_NAME="ubuntukylin-${TARGET_RELEASE}-${TARGET_ARCH}+${TARGET_RELEASE}-${TARGET_EXPORT_NAME_SUFFIX}-$(date +%Y-%m-%d).img"
        else
            EXPORT_FILE_NAME="ubuntukylin-${TARGET_RELEASE}-${TARGET_ARCH}+${TARGET_RELEASE}-$(date +%Y-%m-%d).img"
        fi
    fi
    TARGET_EXPORT_NAME="$EXPORT_FILE_NAME"
}

function export_image_raspi4() {
    auto_umount "${TARGET_ROOTFS_DIR}/proc"
    auto_umount "${TARGET_ROOTFS_DIR}/sys"
    chroot_check_directory_will_warning "${EXPORT_DIR}/${TARGET_PLATFORM}"
    dd if=/dev/zero of="${EXPORT_DIR}/${TARGET_PLATFORM}/${TARGET_EXPORT_NAME}" bs=1M count=0 seek=5120 > /dev/null 2>&1
    fdisk "${EXPORT_DIR}/${TARGET_PLATFORM}/${TARGET_EXPORT_NAME}" > /dev/null 2>&1 <<EOF
n
p
1

+256M
a
t
c
n
p
2


w
EOF
    EXPORT_DEVICE="$(sudo kpartx -av "${EXPORT_DIR}/${TARGET_PLATFORM}/${TARGET_EXPORT_NAME}" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)"
    EXPORT_DEVICE_BOOT="/dev/mapper/${EXPORT_DEVICE}p1"
    EXPORT_DEVICE_ROOT="/dev/mapper/${EXPORT_DEVICE}p2"
    sudo mkfs.vfat -n "system-boot" "$EXPORT_DEVICE_BOOT"
    sudo mkfs.ext4 -F -b 4096 -i 8192 -m 0 -E resize=536870912 -L "writable" "$EXPORT_DEVICE_ROOT"
    mount "$EXPORT_DEVICE_ROOT" "$TARGET_MOUNT_DIR"
    host_check_directory_will_warning "${TARGET_MOUNT_DIR}/boot/firmware"
    mount "$EXPORT_DEVICE_BOOT" "${TARGET_MOUNT_DIR}/boot/firmware"
    wecho "sync rootfs to image..."
    rsync -a "$TARGET_ROOTFS_DIR" "$TARGET_MOUNT_DIR"
    auto_umount "${TARGET_MOUNT_DIR}/boot/firmware"
    auto_umount "${TARGET_MOUNT_DIR}"
    sudo kpartx -dv "${EXPORT_DIR}/${TARGET_PLATFORM}/${TARGET_EXPORT_NAME}"
    success "export image to ${EXPORT_DIR}/${TARGET_PLATFORM}/${TARGET_EXPORT_NAME}"
}

function export_image() {
    case $TARGET_ARCH in
        "arm64" | "armhf" )
            case $TARGET_PLATFORM in
                "feiting" )
                    wecho "TODO"
                    ;;
                "kunpeng" )
                    wecho "TODO"
                    ;;
                "raspi4" )
                    export_image_raspi4
                    ;;
            esac
            ;;
        "x86" | "amd64" )
            wecho "do nothing"
            ;;
        * )
            error "can not export image for unsupported architectrue: $TARGET_ARCH"
            ;;
    esac
}

check_environment
build_rootfs
configure_rootfs
clean_rootfs
export_image

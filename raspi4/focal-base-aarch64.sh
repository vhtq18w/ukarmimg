#!/usr/bin/env bash
#
# Author: Burgess Chang <brs@sdf.org>
#

set -u
set -e
set -x

PORTS_REPO="http://ports.ubuntu.com/"

TARGET_ARCH=aarch64
TARGET_ARCH_DEBIAN_ALIAS=arm64

TARGET_RELEASE=focal

TARGET_DIR=$(pwd)/$TARGET_RELEASE
TARGET_BUILD_DIR=$TARGET_DIR/build
TARGET_ROOTFS_DIR=$TARGET_BUILD_DIR/rootfs

mkdir -p $TARGET_DIR
mkdir -p $TARGET_BUILD_DIR
mkdir -p $TARGET_ROOTFS_DIR

export TZ=UTC

apt install -y ubuntu-keyring debootstrap

debootstrap $TARGET_RELEASE $TARGET_ROOTFS_DIR $PORTS_REPO

mount --types proc /proc $TARGET_ROOTFS_DIR/proc
mount --rbind /sys $TARGET_ROOTFS_DIR/sys
mount --make-rslave $TARGET_ROOTFS_DIR/sys
mount --rbind /dev $TARGET_ROOTFS_DIR/dev
mount --make-rslave $TARGET_ROOTFS_DIR/dev

cat <<EOM > $TARGET_ROOTFS_DIR/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE} main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE} main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-updates main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-updates main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-security main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-security main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-backports main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ ${RELEASE}-backports main restricted universe multiverse
EOM

chroot $TARGET_ROOTFS_DIR apt update

chroot $TARGET_ROOTFS_DIR apt -y install software-properties-common ubuntu-keyring

# Add PPA
# TODO


chroot $TARGET_ROOTFS_DIR apt update

# Install necessary packages

chroot $TARGET_ROOTFS_DIR apt -y install ubuntu-standard language-pack-en

chroot $TARGET_ROOTFS_DIR apt -y install linux-raspi2 linux-firmware-raspi2

# Boot configuration
# TODO

echo ubuntukylin >$TARGET_ROOTFS_DIR/etc/hostname

cat <<EOM >$TARGET_ROOTFS_DIR/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
EOM

echo ubuntukylin >$TARGET_ROOTFS_DIR/etc/hostname
cat <<EOM >$TARGET_ROOTFS_DIR/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOM

chroot $TARGET_ROOTFS_DIR adduser --gecos "UbuntuKylin user" --add_extra_groups --disabled-password ubuntukylin
chroot $TARGET_ROOTFS_DIR usermod -a -G sudo,adm -p '$1$.NBXnqSb$e11MEXIT/6SCDt.fTKa2X/' ubuntukylin

chroot $TARGET_ROOTFS_DIR apt clean

chroot $TARGET_ROOTFS_DIR mkdir -p /etc/network

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

# umount
umount $TARGET_ROOTFS_DIR/proc
umount $TARGET_ROOTFS_DIR/sys
umount $TARGET_ROOTFS_DIR/dev
umount $TARGET_ROOTFS_DIR/proc

# Clean up files
rm -f $TARGET_ROOTFS_DIR/etc/apt/sources.list.save
rm -f $TARGET_ROOTFS_DIR/etc/resolvconf/resolv.conf.d/original
rm -rf $TARGET_ROOTFS_DIR/run
mkdir -p $TARGET_ROOTFS_DIR/run
rm -f $TARGET_ROOTFS_DIR/etc/*-
rm -f $TARGET_ROOTFS_DIR/root/.bash_history
rm -rf $TARGET_ROOTFS_DIR/tmp/*
rm -f $TARGET_ROOTFS_DIR/var/lib/urandom/random-seed
[ -L $TARGET_ROOTFS_DIR/var/lib/dbus/machine-id ] || rm -f $TARGET_ROOTFS_DIR/var/lib/dbus/machine-id
rm -f $TARGET_ROOTFS_DIR/etc/machine-id

# Build the image file
# Currently hardcoded to a 1.75GiB image
DATE="$(date +%Y-%m-%d)"
dd if=/dev/zero of="$TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img" bs=1M count=1
dd if=/dev/zero of="$TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img" bs=1M count=0 seek=1792
sfdisk -f "$TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img" <<EOM
unit: sectors

1 : start=     2048, size=   131072, Id= c, bootable
2 : start=   133120, size=  3536896, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM
VFAT_LOOP="$(losetup -o 1M --sizelimit 64M -f --show $TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img)"
EXT4_LOOP="$(losetup -o 65M --sizelimit 1727M -f --show $TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img)"
mkfs.vfat "$VFAT_LOOP"
mkfs.ext4 "$EXT4_LOOP"
MOUNTDIR="$TARGET_BUILD_DIR/mount"
mkdir -p "$MOUNTDIR"
mount "$EXT4_LOOP" "$MOUNTDIR"
mkdir -p "$MOUNTDIR/boot/firmware"
mount "$VFAT_LOOP" "$MOUNTDIR/boot/firmware"
rsync -a "$TARGET_ROOTFS_DIR/" "$MOUNTDIR/"
umount "$MOUNTDIR/boot/firmware"
umount "$MOUNTDIR"
losetup -d "$EXT4_LOOP"
losetup -d "$VFAT_LOOP"
if which bmaptool; then
  bmaptool create -o "$TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.bmap" "$TARGET_BUILD_DIR/${DATE}-ubuntukylin-${TARGET_RELEASE}.img"
fi

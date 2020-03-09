#!/usr/bin/env bash
$TARGET_ROOTFS_DIR="$(pwd)/build/rootfs"
mount --types proc /proc $TARGET_ROOTFS_DIR/proc
mount --rbind /sys $TARGET_ROOTFS_DIR/sys
mount --make-rslave $TARGET_ROOTFS_DIR/sys
mount --rbind /dev $TARGET_ROOTFS_DIR/dev
mount --make-rslave $TARGET_ROOTFS_DIR/dev

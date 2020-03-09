# ukarmimg

This project collect some UbuntuKylin image generate script for ARM platform.

Supported platform in plan:

* Kunpeng (aarch64 & armhf)
* Feiteng (aarch64 & armhf)
* Raspberry Pi 4 (aarch64 & armhf)

<<<<<<< HEAD
<<<<<<< HEAD
## Dependencies

All images will create from scratch by debootstrap, then generate to images or isos, so you need install some Ubuntu(Debian) tools. This is a necessary dependencies list: `debootstrap qemu-user-static qemu-debootstrap squashfs-tools genisoimage`.

## Document

## Kunpeng

[ ] In progress.

## Feiteng

[ ] In progress.

=======
## Document

>>>>>>> 0e8872c... Fix README path
=======
## Dependencies

All images will create from scratch by debootstrap, then generate to images or isos, so you need install some Ubuntu(Debian) tools. This is a necessary dependencies list: `debootstrap qemu-user-static qemu-debootstrap syslinux squashfs-tools genisoimage`.

## Document

## Kunpeng

[ ] In progress.

## Feiteng

[ ] In progress.

>>>>>>> 81e5e93... Add kunpeng to plan
### Raspberry Pi 4 (raspi4)

It provided `raspi4/build.sh` to easily build raspi4 preinstalled image. You can run `raspi4/build.sh -h` get usage infomation.

This script supported to assign the arch and ubuntu release version, set repository mirror or http(s) proxy.

After you run build script, an exported image will stored in `raspi4/export` directory, and the build cache will stored in `raspi4/build` directory.

You must assigned the Ubuntu release version when you run the build script. Like this: `raspi4/build.sh -r focal`

Some available  optional arguments:

* `-a` Assign the target image arch when you want to cross build, for example, generate arm64 image on amd64. At the same time, you need activate `-c` arguments. Example: `raspi4/build.sh -a arm64 -c -r focal`
* `-m` Set the mirror url. When you have a slow connections to the offical repository, recommend to use closer mirror site. Example: `raspi4/build.sh -r focal -m http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports`. NOTE: DONT end with a slash.
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> f70afc5... Update README
* `-p` Set http proxy for `apt` and `debootstrap`. Sometimes, the synchronization of the mirror site is not good, you also can choose to use a proxy. Only support http proxy now. Example: `raspi4/build.sh -r focal -p http://127.0.0.1:8080` 

If you want to modifed packages that will be installed on build, you can just edit the package list file in `raspi4/pkg`. different files should store package names for different purposes.

* `common-packages`: Some packages that shared by different release should be put here, such as: `ubuntu-keyring`, `software-properties-common`, etc.
* `RELEASE-packages`: Some packages with differet behavior for specific versions should be put here, usually kernel or firmware.
* `RELEASE-ppas`: The ppa repository you want to add should be put here.
* `ukui-packages`: UKUI desktop environment packages put here.
<<<<<<< HEAD

Tips: If you abort build when script run, you need manually umount `$TARGET_ROOTFS_DIR/{proc,sys}`.
=======
* `-p` Set http proxy for `apt` and `debootstrap`. Sometimes, the synchronization of the mirror site is not good, you also can choose to use a proxy. Only support http proxy now. 
>>>>>>> 0e8872c... Fix README path
=======
>>>>>>> f70afc5... Update README

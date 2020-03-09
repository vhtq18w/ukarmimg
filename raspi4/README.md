# ukarmimg

This project collect some UbuntuKylin image generate script for ARM platform.

Supported platform in plan:

* Kunpeng (aarch64 & armhf)
* Feiteng (aarch64 & armhf)
* Raspberry Pi 4 (aarch64 & armhf)

## Document

### Raspberry Pi 4 (raspi4)

It provided `raspi4/build.sh` to easily build raspi4 preinstalled image. You can run `raspi4/build.sh -h` get usage infomation.

This script supported to assign the arch and ubuntu release version, set repository mirror or http(s) proxy.

After you run build script, an exported image will stored in `raspi4/export` directory, and the build cache will stored in `raspi4/build` directory.

You must assigned the Ubuntu release version when you run the build script. Like this: `raspi4/build.sh -r focal`

Some available  optional arguments:

* `-a` Assign the target image arch when you want to cross build, for example, generate arm64 image on amd64. At the same time, you need activate `-c` arguments. Example: `raspi4/build.sh -a arm64 -c -r focal`
* `-m` Set the mirror url. When you have a slow connections to the offical repository, recommend to use closer mirror site. Example: `raspi4/build.sh -r focal -m http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports`. NOTE: DONT end with a slash.
* `-p` Set http proxy for `apt` and `debootstrap`. Sometimes, the synchronization of the mirror site is not good, you also can choose to use a proxy. Only support http proxy now. 

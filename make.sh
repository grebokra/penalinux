#!/bin/sh
KERNEL_VERSION=6.3.1
BUSYBOX_VERSION=1.36.0

mkdir -p rootfs
mkdir -p staging
mkdir -p iso/boot

SOURCE_DIR=$PWD
ROOTFS=$SOURCE_DIR/rootfs
STAGING=$SOURCE_DIR/staging
ISO_DIR=$SOURCE_DIR/iso

cd $STAGING

set -ex
wget -nc -O kernel.tar.xz http://kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz
#wget -nc -O busybox.tar.bz2 http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
wget -nc -O busybox.tar.gz "https://github.com/mirror/busybox/archive/refs/tags/$(echo $BUSYBOX_VERSION | sed 's/\./_/g').tar.gz"

tar -xvf kernel.tar.xz
tar -xvf busybox.tar.gz

cd "busybox-$(echo $BUSYBOX_VERSION | sed 's/\./_/g')"
make defconfig
LDFLAGS="--static" make busybox install -j$(nproc)
cd _install
cp -r ./ $ROOTFS/
cd $ROOTFS
mkdir -p bin dev mnt proc sys tmp

echo '#!/bin/sh' > init
echo 'dmesg -n 1' >> init
echo 'mount -t devtmpfs none /dev' >> init
echo 'mount -t proc none /proc' >> init
echo 'mount -t sysfs none /sys' >> init
echo 'setsid -c /bin/sh' >> init

chmod +x init

cd $ROOTFS
find . | cpio -R root:root -H newc -o | gzip > $SOURCE_DIR/iso/boot/rootfs.gz

cd $STAGING
cd linux-${KERNEL_VERSION}
make -j$(nproc) defconfig
sed -i "s|.*CONFIG_EFI=y.*|# CONFIG_EFI is not set|" .config
sed -i "s|.*CONFIG_EFI_STUB=y.*|# CONFIG_EFI_STUB is not set|" .config
sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" .config
sed -i "s|.*# CONFIG_KERNEL_XZ is not set.*|CONFIG_KERNEL_XZ=y|" .config
sed -i "s|.*CONFIG_KERNEL_GZIP=y.*|# CONFIG_KERNEL_GZIP is not set|" .config
sed -i "s|.*CONFIG_DEFAULT_HOSTNAME=*|CONFIG_DEFAULT_HOSTNAME=\"penalinux\"|" .config

make bzImage -j$(nproc)
cp arch/x86/boot/bzImage $SOURCE_DIR/iso/boot/bzImage
cp System.map $SOURCE_DIR/iso/boot/System.map

make INSTALL_HDR_PATH=$ROOTFS headers_install -j$(nproc)

cd $SOURCE_DIR/iso/boot
mkdir -p grub
cd grub
cat > grub.cfg << EOF
set default=0
set timeout=30

# Menu Colours
set menu_color_normal=white/black
set menu_color_highlight=white/green

root (hd0,0)

menuentry "penalinux" {      
    linux  /boot/bzImage console=ttyS0
    initrd /boot/rootfs.gz
}
EOF

cd $SOURCE_DIR
grub2-mkrescue --compress=xz -o penalinux.iso iso 
set +ex

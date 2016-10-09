#!/bin/bash 

set -euo pipefail
set -x

usage() {
  echo wrong cmdline
  exit 1
}

TARGET_SIZE=10G
MEMORY=1024
SUITE=jessie
NOOP=false

while getopts ":m:d:s:nh" opt; do
   case $opt in
   m )  MEMORY=$OPTARG ;;
   d )  TARGET_SIZE=$OPTARG ;;
   s )  SUITE=$OPTARG ;;
   h )  echo usage ;;
   n )  NOOP="true" ;;
   \?)  usage ;;
   esac
done

shift $(($OPTIND - 1))

[[ $# -ne 1 ]] && usage

HOSTNAME=$1
DOMAINNAME=$(hostname -d)
TARGET_VG=vgvm
TARGET_LV=lv${HOSTNAME}-vda
ARCH=amd64
EXTRA_PKGS='ssh sudo'
TARGET_DEV=/dev/mapper/${TARGET_VG}-${TARGET_LV//-/--}
TARGET=vm_build
KERNEL=linux-image-amd64

DEFAULT_USER=manager
DEFAULT_PW='$6$vBAxhnQ5j0x7BAs$hwnKNfkPHdq79gjvR1.vJqEO./6AdFICLrglFN8/VHbXTKftz4597ycNN5tLNbEViWA0jtmVMCSmirZMVPB2C1'

mountlist="dev sys proc"

export DEBIAN_FRONTEND=noninteractive

run_in_target(){
  chroot $TARGET $@
}

grub_preconfig(){
  run_in_target apt-get -y install grub-pc  
  cat <<EOF > $TARGET/etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=sb_release -i -s 2> /dev/null || echo Debian
GRUB_TERMINAL=console 
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="text console=tty0 console=ttyS0,115200n8"
EOF
  mkdir -p $TARGET/boot/grub/
  echo "(hd0) ${TARGET_DEV}" >$TARGET/boot/grub/device.map
}

partition_disk(){
  sfdisk -uS --force ${TARGET_DEV} << EOF
2048,,L,*
EOF
}

configure_default_net(){
  cat<<EOF >$TARGET/etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF

}

configure_base(){
  root_uuid=$(blkid -o value -s UUID ${TARGET_DEV}1)
  run_in_target useradd -m -p $DEFAULT_PW \
    -s /bin/bash -G sudo $DEFAULT_USER
  for mount in $mountlist; do
    mount --bind /$mount $TARGET/$mount
  done
  grub_preconfig
  run_in_target grub-install '(hd0)'
  rm $TARGET/boot/grub/device.map
  run_in_target apt-get install -y $KERNEL
  run_in_target update-grub
  echo $HOSTNAME >$TARGET/etc/hostname
  echo "127.0.1.1 $HOSTNAME.$DOMAINNAME $HOSTNAME" > $TARGET/etc/hosts
  echo "UUID=$root_uuid	/ ext4 defaults,relatime,errors=remount-ro 0 1" >$TARGET/etc/fstab
  configure_default_net
}

base_install(){
  debootstrap --arch=$ARCH --include "$EXTRA_PKGS" $SUITE $TARGET
}

create_target_dev(){
  lvcreate -L ${TARGET_SIZE} -n ${TARGET_LV} ${TARGET_VG}
  partition_disk
  kpartx -a $TARGET_DEV
  sleep 1
  mkfs.ext4 -F ${TARGET_DEV}1
  mkdir -p $TARGET
  mount ${TARGET_DEV}1 $TARGET
}

generate_mac_address(){
  printf '02:00:%02x:%02x:%02x:%02x\n'\
    $[RANDOM%256] $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]
}

generate_virsh_config(){
  export MEMORY
  export CPU_COUNT=1
  export MAC_ADDRESS=$(generate_mac_address)
  export TARGET_DEV
  export HOSTNAME

  envsubst <machine.xml.template >define.xml
  virsh define define.xml
  rm -f define.xml
}

cleanup_build_mount(){
  for mount in $mountlist; do
    umount -l $TARGET/$mount
  done
  umount $TARGET
  kpartx -d $TARGET_DEV
}

[[ $NOOP == "true" ]] && exit 0
create_target_dev

base_install

configure_base

cleanup_build_mount

generate_virsh_config 

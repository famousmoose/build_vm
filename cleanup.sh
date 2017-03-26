#!/bin/bash -x

umount vm_build/proc
umount vm_build/sys
umount vm_build/dev
umount vm_build/
virsh undefine $1
kpartx -d /dev/mapper/vgvm-lv${1}--vda
lvremove /dev/vgvm/lv${1}-vda

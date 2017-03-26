#!/bin/bash -x

umount vm_build/proc
umount vm_build/sys
umount vm_build/dev
umount vm_build/
kpartx -d /dev/mapper/vgvm-lvfoo--vda
lvremove /dev/vgvm/lvfoo-vda

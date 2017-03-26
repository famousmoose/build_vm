#!/bin/bash -x

umount vm_build/*
umount vm_build/
kpartx -d /dev/mapper/vgvm-lvfoo--vda
lvremove /dev/vgvm/lvfoo-vda

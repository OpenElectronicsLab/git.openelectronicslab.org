#!/bin/bash
set -e

QCOW_FILE=/var/images/git.openelectronicslab.org.gitlab.qcow2
PID_FILE=/var/images/qemu-git.openelectronicslab.org.pid
KVM_RAM=8G
KVM_CORES=2
HOST_IP=87.233.128.196

qemu-system-x86_64 -hda $QCOW_FILE -pidfile $PID_FILE \
	-m $KVM_RAM -smp $KVM_CORES -machine type=pc,accel=kvm \
	-display none \
	-nic user\
,hostfwd=tcp:$HOST_IP:22-:22\
,hostfwd=tcp:$HOST_IP:80-:80\
,hostfwd=tcp:$HOST_IP:443-:443

#!/bin/bash

QEMU_PID=`cat /var/images/qemu-git.openelectronicslab.org.pid`
#TODO: ensure the QEMU_PID is actually a qemu process
echo kill $QEMU_PID
kill $QEMU_PID

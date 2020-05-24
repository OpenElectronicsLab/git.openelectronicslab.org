# DEBIAN_ISO_URL=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.4.0-amd64-netinst.iso
DEBIAN_ISO_URL=https://cdimage.debian.org/mirror/cdimage/archive/10.3.0/amd64/iso-cd/debian-10.3.0-amd64-netinst.iso
ISO_TARGET=debian_autoinstall.iso

INITIAL_DISK_SIZE=8G
KVM_CORES=2
KVM_RAM=512M
SSH_MAX_INIT_SECONDS=60
DELAY=0.1
QEMU_FORCE_SLEEP=7

RETRIES=$(shell echo "$(SSH_MAX_INIT_SECONDS)/$(DELAY)" | bc)

# $@ : target label
# $< : the first prerequisite after the colon
# $^ : all of the prerequisite files
# $* : wildcard matched part

ISO_CREATED_MARKER=iso/README.txt

default: check

check:
	echo "ok"

clean:
	rm -rf iso $(ISO_TARGET)
	rm -rf git.openelectronicslab.org.qcow2

spotless:
	git clean -dffx
	git submodule foreach --recursive git clean -dffx

# download the base install image
debian_original.iso :
	wget $(DEBIAN_ISO_URL) -O $@

# extract the contents of the image
$(ISO_CREATED_MARKER) : debian_original.iso
	mkdir -pv iso
	cd iso && 7z x ../$<
	touch $@ # update timestamp so make knows when this was extracted

# copy the preseed file to the appropriate location (using m4 to expand macros)
# CONSIDER: could add encryption to preseed file if we decide we need it
iso/preseed/autoinstall-preseed.seed: autoinstall-preseed.seed \
		$(ISO_CREATED_MARKER)
	mkdir -pv iso/preseed
	cp $< $@

iso/authorized_keys: $(ISO_CREATED_MARKER) id_rsa_tmp.pub \
		id_rsa_host_tmp.pub id_rsa_host_tmp
	cp -v ./id_rsa_tmp.pub iso/authorized_keys
	cp -v ./id_rsa_host_tmp.pub iso/id_rsa_host_tmp.pub
	cp -v ./id_rsa_host_tmp iso/id_rsa_host_tmp

# update the grub.cfg to do a preseeded install
# (Used for Legacy BIOS)
iso/isolinux/isolinux.cfg : isolinux.cfg $(ISO_CREATED_MARKER)
	cp $< $@

# generate the new iso install image
$(ISO_TARGET): iso/preseed/autoinstall-preseed.seed \
		iso/isolinux/isolinux.cfg \
		iso/authorized_keys
	genisoimage -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table -J -R \
		-V "Debian AutoInstall" iso

git.openelectronicslab.org.base.qcow2: $(ISO_TARGET)
	qemu-img create -f qcow2 tmp.qcow2 $(INITIAL_DISK_SIZE)
	qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display curses \
		-nic user,hostfwd=tcp:127.0.0.1:10022-:22
	mv tmp.qcow2 $@

git.openelectronicslab.org.gitlab.qcow2: git.openelectronicslab.org.base.qcow2
	cp -v $< git.openelectronicslab.org.gitlab.qcow2

launch-qemu-gitlab: git.openelectronicslab.org.gitlab.qcow2
	qemu-system-x86_64 -hda git.openelectronicslab.org.gitlab.qcow2 \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10022-:22 &
	./retry.sh $(RETRIES) $(DELAY) \
		ssh -p10022 -oNoHostAuthenticationForLocalhost=yes \
			root@127.0.0.1 \
			-i ./id_rsa_tmp \
			'/bin/true'
	ssh-keyscan -p10022 127.0.0.1 \
		| grep `cat id_rsa_host_tmp.pub | cut -f2 -d' '`
	echo ssh -i ./id_rsa_tmp -p10022 \
		-oNoHostAuthenticationForLocalhost=yes \
		root@127.0.0.1
	echo "kvm running"

shutdown-kvm:
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	echo "yay"

install-gitlab: launch-qemu-gitlab install-gitlab.sh
	scp -P10022 -oNoHostAuthenticationForLocalhost=yes
		-i ./id_rsa_tmp \
		./install-gitlab.sh root@127.0.0.1:/root
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'bash /root/install-gitlab.sh'
	echo "gitlab-installed"

kill-qemu:
	kill `ps auxw \
		| grep "qemu-system-x86_64" \
		| grep -v grep \
		| sed -e "s/$(USER) *\([0-9]*\).*/\1/g"`

id_rsa_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f ./id_rsa_tmp

id_rsa_tmp.pub: id_rsa_tmp

id_rsa_host_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temp-host-key" -f ./id_rsa_host_tmp

id_rsa_host_tmp.pub: id_rsa_host_tmp


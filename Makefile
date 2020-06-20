# DEBIAN_ISO_URL=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.4.0-amd64-netinst.iso
DEBIAN_ISO_URL=https://cdimage.debian.org/mirror/cdimage/archive/10.3.0/amd64/iso-cd/debian-10.3.0-amd64-netinst.iso
ISO_TARGET=debian_autoinstall.iso

IMAGE_DIR=/var/images

INITIAL_DISK_SIZE=8G
KVM_CORES=2
KVM_DEBIAN_INSTALL_RAM=1G
KVM_RAM=8G
SSH_MAX_INIT_SECONDS=60
DELAY=0.1
QEMU_FORCE_SLEEP=7
OPENSSL_TMP_SUBJ="/C=NL/ST=Utrecht/L=Utrecht/O=OpenElectronicsLab/OU=Dev/CN=git.openelectronicslab.org"

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
	echo "removing files generated by the build, see also 'make spotless'"
	rm -rf iso $(ISO_TARGET) \
		tmp.qcow2 \
		git.openelectronicslab.org.qcow2 \
		git.openelectronicslab.org.base.qcow2 \
		git.openelectronicslab.org.gitlab.qcow2 \
		tmp_gitlab_admin_passwd \
		id_rsa_tmp.pub \
		id_rsa_tmp \
		id_rsa_host_tmp.pub \
		id_rsa_host_tmp \
		tmp.key \
		tmp.crt

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
		-m $(KVM_DEBIAN_INSTALL_RAM) -smp $(KVM_CORES) \
		-machine type=pc,accel=kvm \
		-display curses \
		-nic user,hostfwd=tcp:127.0.0.1:10022-:22
	mv tmp.qcow2 $@

launch-qemu-gitlab: git.openelectronicslab.org.gitlab.qcow2
	qemu-system-x86_64 -hda $< \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 &
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
	echo "$@ kvm running"


shutdown-kvm:
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	echo "yay"

tmp.crt:
	openssl req -newkey rsa:4096 -x509 -nodes -days 3560 \
		-subj $(OPENSSL_TMP_SUBJ) \
		-out tmp.crt \
		-keyout tmp.key
	ls -l tmp.*

tmp.key: tmp.crt

tmp_gitlab_admin_passwd:
	cat /dev/urandom \
		| tr -dc 'a-zA-Z0-9' \
		| fold -w $${1:-32} \
		| head -n 1 > ./tmp_gitlab_admin_passwd

GITLAB_SCP_FILES=tmp.key tmp.crt install-gitlab.sh tmp_gitlab_admin_passwd

git.openelectronicslab.org.gitlab.qcow2: $(GITLAB_SCP_FILES) \
		git.openelectronicslab.org.base.qcow2
	cp -v git.openelectronicslab.org.base.qcow2 \
		git.openelectronicslab.org.pre-gitlab.qcow2
	qemu-system-x86_64 -hda git.openelectronicslab.org.pre-gitlab.qcow2 \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 &
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
	scp -P10022 -oNoHostAuthenticationForLocalhost=yes \
		-i ./id_rsa_tmp \
		$(GITLAB_SCP_FILES) root@127.0.0.1:/root
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'bash /root/install-gitlab.sh'
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	echo 'todo verify this is not a race'
	mv -v git.openelectronicslab.org.pre-gitlab.qcow2 \
		git.openelectronicslab.org.gitlab.qcow2

install-gitlab: git.openelectronicslab.org.gitlab.qcow2
	true

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

/var/images:
	mkdir -pv /var/images

install: /var/images git.openelectronicslab.org.gitlab.qcow2 \
		stop-qemu-git-openelectronicslab.sh \
		start-qemu-git-openelectronicslab.sh \
		qemu-git-openelectronicslab.service
	-systemctl stop qemu-git-openelectronicslab
	cp -v stop-qemu-git-openelectronicslab.sh /var/images/
	cp -v start-qemu-git-openelectronicslab.sh /var/images/
	cp -v qemu-git-openelectronicslab.service /var/images/
	-ln -s /var/images/qemu-git-openelectronicslab.service \
		/etc/systemd/system/qemu-git-openelectronicslab.service
	cp -v git.openelectronicslab.org.gitlab.qcow2 \
		/var/images/git.openelectronicslab.org.gitlab.qcow2
	systemctl start qemu-git-openelectronicslab

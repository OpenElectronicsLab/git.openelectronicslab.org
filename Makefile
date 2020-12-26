# DEBIAN_ISO_URL=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-10.4.0-amd64-netinst.iso
DEBIAN_ISO_URL=https://cdimage.debian.org/mirror/cdimage/archive/10.3.0/amd64/iso-cd/debian-10.3.0-amd64-netinst.iso
ISO_TARGET=debian_autoinstall.iso

IMAGE_DIR=/var/images
QCOW_FILE=$(IMAGE_DIR)/git.openelectronicslab.org.gitlab.qcow2

BACKUPS_DIR=/backups/git.openelectronicslab.org

INITIAL_DISK_SIZE=20G
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
	{ lsof -i:10022; if [ $$? -eq 0 ]; then echo "port 10022 not free"; false; fi; }
	qemu-img create -f qcow2 tmp.qcow2 $(INITIAL_DISK_SIZE)
	qemu-system-x86_64 -hda tmp.qcow2 -cdrom $(ISO_TARGET) \
		-m $(KVM_DEBIAN_INSTALL_RAM) -smp $(KVM_CORES) \
		-machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10022-:22
	mv tmp.qcow2 $@

launch-qemu-gitlab: git.openelectronicslab.org.gitlab.qcow2
	{ lsof -i:10022; if [ $$? -eq 0 ]; then echo "port 10022 not free"; false; fi; }
	{ lsof -i:10443; if [ $$? -eq 0 ]; then echo "port 10443 not free"; false; fi; }
	{ qemu-system-x86_64 -hda $< \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 & \
		echo "$$!" > 'qemu.pid' ; }
	./retry.sh $(RETRIES) $(DELAY) \
		ssh -p10022 -oNoHostAuthenticationForLocalhost=yes \
			root@127.0.0.1 \
			-i ./id_rsa_tmp \
			'/bin/true'
	echo "check the key matches the one we generated"
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
	{ while kill -0 `cat qemu.pid`; do echo "wating for `cat qemu.pid`"; sleep 1; done }
	sleep 1
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
	{ lsof -i:10022; if [ $$? -eq 0 ]; then echo "port 10022 not free"; false; fi; }
	{ lsof -i:10443; if [ $$? -eq 0 ]; then echo "port 10443 not free"; false; fi; }
	cp -v git.openelectronicslab.org.base.qcow2 \
		git.openelectronicslab.org.pre-gitlab.qcow2
	{ qemu-system-x86_64 -hda git.openelectronicslab.org.pre-gitlab.qcow2 \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 \
		& echo "$$!" > qemu.pid; }
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
	{ while kill -0 `cat qemu.pid`; do echo "wating for `cat qemu.pid`"; sleep 1; done }
	sleep 1
	mv -v git.openelectronicslab.org.pre-gitlab.qcow2 \
		git.openelectronicslab.org.gitlab.qcow2

install-gitlab: git.openelectronicslab.org.gitlab.qcow2
	true

kill-qemu:
	-kill `ps auxw \
		| grep "[q]emu-system-x86_64" \
		| grep "^$(USER)" \
		| sed -e "s/$(USER) *\([0-9]*\).*/\1/g"`


id_rsa_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temporary-key" -f ./id_rsa_tmp

id_rsa_tmp.pub: id_rsa_tmp

id_rsa_host_tmp:
	ssh-keygen -b 4096 -t rsa -N "" -C "temp-host-key" -f ./id_rsa_host_tmp

id_rsa_host_tmp.pub: id_rsa_host_tmp

$(IMAGE_DIR):
	mkdir -pv $(IMAGE_DIR)

install: $(IMAGE_DIR) git.openelectronicslab.org.gitlab.qcow2 \
		stop-qemu-git-openelectronicslab.sh \
		start-qemu-git-openelectronicslab.sh \
		qemu-git-openelectronicslab.service
	-systemctl stop qemu-git-openelectronicslab
	cp -v stop-qemu-git-openelectronicslab.sh $(IMAGE_DIR)/
	cp -v start-qemu-git-openelectronicslab.sh $(IMAGE_DIR)/
	cp -v qemu-git-openelectronicslab.service $(IMAGE_DIR)/
	-ln -sv $(IMAGE_DIR)/qemu-git-openelectronicslab.service \
		/etc/systemd/system/qemu-git-openelectronicslab.service
	cp -v git.openelectronicslab.org.gitlab.qcow2 \
		$(IMAGE_DIR)/git.openelectronicslab.org.gitlab.qcow2
	systemctl daemon-reload
	systemctl start qemu-git-openelectronicslab
	./retry.sh $(RETRIES) $(DELAY) \
		ssh root@git.openelectronicslab.org \
			-i ./id_rsa_tmp \
			'/bin/true'
	scp -i ./id_rsa_tmp \
		./letsencrypt.sh \
		root@git.openelectronicslab.org:/root/
	ssh root@git.openelectronicslab.org \
		-i ./id_rsa_tmp \
		'bash /root/letsencrypt.sh'


NOW=`cat now_timestamp`

git.openelectronicslab.org-tested: git.openelectronicslab.org.gitlab.qcow2
	{ lsof -i:10022; if [ $$? -eq 0 ]; then echo "port 10022 not free"; false; fi; }
	{ lsof -i:10443; if [ $$? -eq 0 ]; then echo "port 10443 not free"; false; fi; }
	# TODO: add backup user, id_rsa_tmp will be wrong
	# TODO: backup the ssh keys
	date --utc +"%Y%m%dT%H%M%SZ" > now_timestamp
	ssh root@git.openelectronicslab.org \
		-i ./id_rsa_tmp \
		'bash gitlab-backup create'
	mkdir -pv $(BACKUPS_DIR)/$(NOW)
	rm -fv $(BACKUPS_DIR)/latest
	ln -s $(BACKUPS_DIR)/$(NOW) \
		$(BACKUPS_DIR)/latest
	cp -v ./id_rsa_tmp $(BACKUPS_DIR)/latest/
	cp -v ./id_rsa_tmp.pub $(BACKUPS_DIR)/latest/
	scp -i ./id_rsa_tmp -r \
		root@git.openelectronicslab.org:/root/.ssh/authorized_keys \
		root@git.openelectronicslab.org:/etc/ssh/ssh_host_rsa_key \
		root@git.openelectronicslab.org:/etc/ssh/ssh_host_rsa_key.pub \
		root@git.openelectronicslab.org:/etc/gitlab/gitlab-secrets.json \
		root@git.openelectronicslab.org:/etc/gitlab/gitlab.rb \
		root@git.openelectronicslab.org:/etc/gitlab/ssl \
		root@git.openelectronicslab.org:/var/opt/gitlab/backups \
		$(BACKUPS_DIR)/latest
	cp -v $< git.openelectronicslab.org.gitlab-pre-restore.qcow2
	{ qemu-system-x86_64 \
		-hda git.openelectronicslab.org.gitlab-pre-restore.qcow2 \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 & echo $$! > qemu.pid ; }
	./retry.sh $(RETRIES) $(DELAY) \
		ssh -p10022 -oNoHostAuthenticationForLocalhost=yes \
			root@127.0.0.1 \
			-i ./id_rsa_tmp \
			'/bin/true'
	scp -P10022 -oNoHostAuthenticationForLocalhost=yes -i ./id_rsa_tmp \
		-r $(BACKUPS_DIR)/latest/backups/* \
		root@127.0.0.1:/var/opt/gitlab/backups/
	scp -P10022 -oNoHostAuthenticationForLocalhost=yes -i ./id_rsa_tmp \
		$(BACKUPS_DIR)/latest/gitlab.rb \
		$(BACKUPS_DIR)/latest/gitlab-secrets.json \
		root@127.0.0.1:/etc/gitlab/
	scp -P10022 -oNoHostAuthenticationForLocalhost=yes -i ./id_rsa_tmp \
		./restore-gitlab.sh \
		root@127.0.0.1:/root/
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'bash /root/restore-gitlab.sh'
	# TODO: restore keys and such, reconnect with new keys
	ssh -p10022 -oNoHostAuthenticationForLocalhost=yes root@127.0.0.1 \
		-i ./id_rsa_tmp \
		'shutdown -h -t 2 now & exit'
	{ while kill -0 `cat qemu.pid`; do echo "wating for `cat qemu.pid`"; sleep 1; done }
	sleep 2
	{ lsof -i:10022; if [ $$? -eq 0 ]; then echo "port 10022 not free"; false; fi; }
	{ lsof -i:10443; if [ $$? -eq 0 ]; then echo "port 10443 not free"; false; fi; }
	mv -v git.openelectronicslab.org.gitlab-pre-restore.qcow2 \
		git.openelectronicslab.org.gitlab-post-restore.qcow2
	# start in "-snapshot" mode to avoid changing the file
	{ qemu-system-x86_64 -snapshot \
		-hda git.openelectronicslab.org.gitlab-post-restore.qcow2 \
		-m $(KVM_RAM) -smp $(KVM_CORES) -machine type=pc,accel=kvm \
		-display none \
		-nic user,hostfwd=tcp:127.0.0.1:10443-:443,hostfwd=tcp:127.0.0.1:10022-:22 \
		& echo "$$!" > qemu.pid; }
	./retry.sh $(RETRIES) $(DELAY) \
		ssh -p10022 -oNoHostAuthenticationForLocalhost=yes \
			root@127.0.0.1 \
			-i ./id_rsa_tmp \
			'/bin/true'
	# run verification tests
	echo rails takes seemingly an eternity to start, will try for 2 minutes
	./retry.sh 120 1 wget -qO- --no-check-certificate https://127.0.0.1:10443
	# TODO: test more than we have Ace
	wget -qO- --no-check-certificate \
		https://127.0.0.1:10443/api/v4/users?username=ace-dvm \
		| jq .[].name \
		| grep 'Medlock'
	kill `cat qemu.pid`
	mv -v git.openelectronicslab.org.gitlab-post-restore.qcow2 \
		git.openelectronicslab.org.gitlab-post-restore.$(NOW).qcow2
	rm -fv $@
	rm git.openelectronicslab.org.gitlab-post-restore.$(NOW).qcow2
	touch $@

# TODO: backup should run every time "make backup" is called
#	rather than depend on the presence of the "foo.tested.qcow2"
backup: git.openelectronicslab.org-tested
	rm -v git.openelectronicslab.org-tested

# TODO separate the making of a backup from testing of a backup
redeploy: git.openelectronicslab.org-tested.qcow2
	echo "shut down running instance"
	systemctl --type=service --state=running
	systemctl stop qemu-git-openelectronicslab.service
	echo "copy new file into place"
	mv -v $(QCOW_FILE) $(QCOW_FILE).`date --utc +"%Y%m%dT%H%M%SZ"`
	cp -v git.openelectronicslab.org-tested.qcow2 $(QCOW_FILE)
	systemctl start qemu-git-openelectronicslab.service
	./retry.sh $(RETRIES) $(DELAY) \
		ssh root@git.openelectronicslab.org \
			-i ./id_rsa_tmp \
			'/bin/true'
	scp -i ./id_rsa_tmp \
		./letsencrypt.sh \
		root@git.openelectronicslab.org:/root/
	ssh root@git.openelectronicslab.org \
		-i ./id_rsa_tmp \
		'bash /root/letsencrypt.sh'

# TODO: restore from disaster, no running instance
# restore: git.openelectronicslab.org-tested.qcow2
	# take the qcow2 image and replace the running one.
	# TODO: restore this to a temp instance, not the running instance
	#	after restore has succeeded, replace running instance
	# TODO: restore the ssh keys

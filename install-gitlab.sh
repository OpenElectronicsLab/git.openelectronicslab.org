#!/bin/bash
set -e

mkdir -pv /etc/gitlab/ssl
chmod -v 755 /etc/gitlab/ssl

# chmod bits: read (4), write (2), and execute (1)
mv -v /root/tmp.key /etc/gitlab/ssl/git.openelectronicslab.org.key
chmod -v 600 /etc/gitlab/ssl/git.openelectronicslab.org.key
mv -v /root/tmp.crt /etc/gitlab/ssl/git.openelectronicslab.org.crt
chmod -v 644 /etc/gitlab/ssl/git.openelectronicslab.org.key


apt-get update
apt-get install -y curl rsync vim ca-certificates

debconf-set-selections <<< "postfix postfix/mailname string git.openelectronicslab.org"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install --assume-yes postfix

wget https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh
bash ./script.deb.sh

export GITLAB_ROOT_PASSWORD=$(cat /root/tmp_gitlab_admin_passwd)
shred -v -u /root/tmp_gitlab_admin_passwd
export EXTERNAL_URL="https://git.openelectronicslab.org"
export GITLAB_ROOT_EMAIL="root@git.openelectronicslab.org"
export RAILS_ENV=production

apt-get install gitlab-ce

gitlab-ctl reconfigure

echo "gitlab-installed"

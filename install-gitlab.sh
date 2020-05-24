apt-get update
apt-get install -y curl vim ca-certificates

debconf-set-selections <<< "postfix postfix/mailname string git.openelectronicslab.org"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install --assume-yes postfix

wget https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh
bash ./script.deb.sh

EXTERNAL_URL="https://git.openelectronicslab.org" apt-get install gitlab-ce

#!/bin/bash
set -x

chown -Rv git:git /var/opt/gitlab/backups*
ls -l /var/opt/gitlab/backups

gitlab-ctl reconfigure
gitlab-ctl start

gitlab-ctl stop unicorn
gitlab-ctl stop puma
gitlab-ctl stop sidekiq
echo 'Verify'
gitlab-ctl status

echo "TODO: this is *Very* fragile; we should pass this name in!"
BACKUP=`ls -tr1 /var/opt/gitlab/backups/*gitlab_backup.tar | tail -n1 | sed -e's@.*/\(.*\)_gitlab_backup.tar@\1@'`
echo "BACKUP='$BACKUP'"


sed -i -e's/gitlab-rake/gitlab-rake --verbose/g' /usr/bin/gitlab-backup
echo ""
echo "========= gitlab-backup restore BACKUP=$BACKUP ========="
echo ""
gitlab-backup restore BACKUP=$BACKUP force=yes

echo ""
echo "========= gitlab-ctl reconfigure ========="
echo ""
gitlab-ctl reconfigure

echo ""
echo "========= gitlab-ctl restart ========="
echo ""
gitlab-ctl restart

echo ""
echo "========= gitlab-rake --verbose gitlab:check SANITIZE=true  ========="
echo ""
gitlab-rake --verbose gitlab:check SANITIZE=true

#!/bin/bash

sed -i -e"s/.*letsencrypt\['enable'\].*/letsencrypt\['enable'\] = true/" \
	/etc/gitlab/gitlab.rb

sed -i -e"s/.*letsencrypt\['auto_renew_hour'\].*/letsencrypt\['auto_renew_hour'\] = 1/" \
	/etc/gitlab/gitlab.rb

sed -i -e"s/.*letsencrypt\['auto_renew_minute'\].*/letsencrypt\['auto_renew_minute'\] = 1/" \
	/etc/gitlab/gitlab.rb

sed -i -e"s/.*letsencrypt\['auto_renew_day_of_month'\].*/letsencrypt\['auto_renew_day_of_month'\] = 1/" \
	/etc/gitlab/gitlab.rb

sed -i -e"s/.*letsencrypt\['auto_renew'\].*/letsencrypt\['auto_renew'\] = true/" \
	/etc/gitlab/gitlab.rb

# letsencrypt['contact_emails'] = ['foo@email.com'] # Optional
gitlab-ctl renew-le-certs

gitlab-ctl reconfigure

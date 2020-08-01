#!/bin/bash

#cd $(HOME)/src/git.openelectronicslab.org
rm -fv git.openelectronicslab.org-tested.qcow2
make backup
rsync --recursive \
	--links \
	--times \
	--human-readable \
	--rsh="ssh -i ${HOME}/.ssh/openelectronicslab_backup" \
	/backups/git.openelectronicslab.org \
	openelectronicslab_backup@magellan.kendrickshaw.org:backups


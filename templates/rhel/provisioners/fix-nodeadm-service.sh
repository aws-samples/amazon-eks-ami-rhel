#!/bin/bash -x
#
# nodeadm-run fails if cloud-init > version 24.4
# If the systemd service file is not updated, you'll see errors like this (from `journalctl -u nodeadm-run`
################# 
#Aug 20 12:46:11 localhost systemd[1]: multi-user.target: Found ordering cycle on nodeadm-run.service/start
#Aug 20 12:46:11 localhost systemd[1]: multi-user.target: Found dependency on cloud-final.service/start
#Aug 20 12:46:11 localhost systemd[1]: multi-user.target: Found dependency on multi-user.target/start
#Aug 20 12:46:11 localhost systemd[1]: multi-user.target: Job nodeadm-run.service/start deleted to break ordering cycle starting with multi-user.target/start
################# 
# This is due to changes in cloud-init's systemd ordering noted in their 'breaking changes' section of release notes
# https://cloudinit.readthedocs.io/en/latest/reference/breaking_changes.html#id4
#
# The decision here is to changed nodeadm-run to be wanted by `cloud-init.target` instead of `multi-user.target`, as cloud-final runs after multi-user.target and nodeadm-run needs to run after cloud-final to ensure it waits until userdata is completed. 
#
######
## Variables
######

# Check current cloud-init version installed
cloud_init_version=$(rpm -q cloud-init --queryformat '%{VERSION}')

# Version with breaking change
# https://cloudinit.readthedocs.io/en/latest/reference/breaking_changes.html#id4
test_version="24.4"

# Path to nodeadm-run service file
path_to_systemd="/etc/systemd/system/nodeadm-run.service"
# Dont' do sudo if we don't have to.
dosudo=""
if [[ "$EUID" -ne 0 ]]; then
   dosudo="sudo"
fi


# If cloud-init > 24.4, fix systemd service.
if echo "$cloud_init_version $test_version" | awk '{ exit !( $1>=$2)}' ; then
	$dosudo sed -i 's/WantedBy=multi-user.target/WantedBy=cloud-init.target/g' $path_to_systemd
        $dosudo fix_nodeadmrun_service $path_to_systemd
        $dosudo systemctl daemon-reload
        $dosudo systemctl disable nodeadm-run.service
        $dosudo systemctl enable nodeadm-run.service
fi

#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

sudo systemctl start containerd

# authenticate with Amazon ECR if using a nodeadm build image hosted in a private ECR repository
if [[ "$BUILD_IMAGE" == *"dkr"* ]]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  aws ecr get-login-password --region $AWS_REGION | sudo nerdctl login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
fi

sudo nerdctl run \
  --rm \
  --network host \
  --workdir /workdir \
  --volume $PROJECT_DIR:/workdir \
  $BUILD_IMAGE \
  make build

# cleanup build image and snapshots
sudo nerdctl rmi \
  --force \
  $BUILD_IMAGE \
  $(sudo nerdctl images -a | grep none | awk '{ print $3 }')

# move the nodeadm binary into bin folder
sudo chmod a+x $PROJECT_DIR/_bin/nodeadm
sudo mv $PROJECT_DIR/_bin/nodeadm /usr/bin/

# change SELinux context for nodeadm binary
sudo semanage fcontext -a -t bin_t "/usr/bin/nodeadm"
sudo restorecon -v /usr/bin/nodeadm

# enable nodeadm bootstrap systemd units
sudo systemctl enable nodeadm-config nodeadm-run

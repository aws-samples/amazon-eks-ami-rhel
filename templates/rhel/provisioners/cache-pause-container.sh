#!/usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail

export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_CA_BUNDLE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
sudo systemctl start containerd
sudo cache-pause-container -i ${PAUSE_CONTAINER_IMAGE}
sudo systemctl stop containerd

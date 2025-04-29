#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

if [ "$ENABLE_ACCELERATOR" != "nvidia" ]; then
  exit 0
fi

# AWS configuration
export AWS_DEFAULT_REGION="${AWS_REGION}"
export AWS_CA_BUNDLE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

# Create directory for RPMs
sudo mkdir -p /tmp/nvidia
cd /tmp/nvidia

RETAIN_NVIDIA_RPM=false

if [ -z "${S3_URL_NVIDIA_RPMS:-}" ]; then
  # Set up repositories only if we're not using S3
  OS_VERSION=$(. /etc/os-release;echo $VERSION_ID | sed -e 's/\..*//g')
  if ( cat /etc/os-release | grep -q Red ); then
    sudo subscription-manager repos --enable codeready-builder-for-rhel-$OS_VERSION-$(arch)-rpms
  elif ( echo $OS_VERSION | grep -q 8 ); then
    sudo dnf config-manager --set-enabled powertools
  else
    sudo dnf config-manager --set-enabled crb
  fi

  # Enable EPEL repository for RHEL 8
  if [ "$OS_VERSION" = "8" ]; then
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  fi

  DISTRO=$(. /etc/os-release;echo rhel$VERSION_ID | sed -e 's/\..*//g')
  if (arch | grep -q x86); then
    ARCH=x86_64
  else
    ARCH=sbsa
  fi
  sudo dnf config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/$ARCH/cuda-$DISTRO.repo

  # Download packages with dependencies
  echo "Downloading packages..."
  sudo dnf download --resolve --downloadonly --downloaddir=/tmp/nvidia dkms kernel-devel kernel-modules-extra unzip gcc make vulkan-devel libglvnd-devel elfutils-libelf-devel xorg-x11-server-Xorg
  sudo dnf download --resolve --downloadonly --downloaddir=/tmp/nvidia $(dnf module list nvidia-driver:latest-dkms -y | grep nvidia-driver | awk '{print $1}')
  sudo dnf download --resolve --downloadonly --downloaddir=/tmp/nvidia cuda-toolkit
  sudo dnf download --resolve --downloadonly --downloaddir=/tmp/nvidia nvidia-container-toolkit
else
  # Copy packages from S3 if S3_URL_NVIDIA_RPMS is provided
  echo "Copying packages from S3..."
  aws s3 cp "$S3_URL_NVIDIA_RPMS" /tmp/nvidia --recursive
fi

# Install the downloaded packages
echo "Installing packages..."
sudo dnf install -y /tmp/nvidia/*.rpm

# Configure nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd

echo "NVIDIA driver installation completed."

# Clean up /tmp/nvidia unless RETAIN_NVIDIA_RPM is true
if [ "$RETAIN_NVIDIA_RPM" = true ]; then
  echo "Keeping NVIDIA RPMs in /tmp/nvidia for potential future use."
else
  echo "Cleaning up NVIDIA RPMs from /tmp/nvidia..."
  sudo rm -rf /tmp/nvidia
fi
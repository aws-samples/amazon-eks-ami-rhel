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

# Create directory for RPMs and GPG keys
sudo mkdir -p /tmp/nvidia
sudo mkdir -p /tmp/nvidia/gpgkeys
cd /tmp/nvidia

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
    # Download and import EPEL GPG key
    sudo curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-8 https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8
    sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-8

    # Save EPEL GPG key to our keys directory
    sudo cp /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-8 /tmp/nvidia/gpgkeys/

    # Now install EPEL release package
    sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  fi

  DISTRO=$(. /etc/os-release;echo rhel$VERSION_ID | sed -e 's/\..*//g')
  if (arch | grep -q x86); then
    ARCH=x86_64
  else
    ARCH=sbsa
  fi

  # Add NVIDIA repository and import GPG keys
  sudo dnf config-manager --add-repo http://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/$ARCH/cuda-$DISTRO.repo

  echo http://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/$ARCH/cuda-$DISTRO.repo
  echo https://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/$ARCH/D42D0685.pub
  
  # Save NVIDIA GPG key
  sudo curl -o /tmp/nvidia/gpgkeys/NVIDIA-keyring.gpg https://developer.download.nvidia.com/compute/cuda/repos/$DISTRO/$ARCH/D42D0685.pub
  sudo rpm --import /tmp/nvidia/gpgkeys/NVIDIA-keyring.gpg
  
  # Save EPEL GPG key
  sudo cp /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-8 /tmp/nvidia/gpgkeys/

  # Download packages with dependencies
  echo "Downloading packages..."
  sudo dnf download --resolve --downloadonly --alldeps --downloaddir=/tmp/nvidia \
      dkms kernel-devel kernel-modules-extra unzip gcc make \
      vulkan-devel libglvnd-devel elfutils-libelf-devel xorg-x11-server-Xorg xorg-x11-nvidia  \
      $(dnf module list nvidia-driver:latest-dkms -y | grep nvidia-driver | awk '{print $1}') \
      cuda-toolkit \
      nvidia-container-toolkit

  # Install the downloaded packages
  echo "Installing packages..."
  sudo dnf install -y /tmp/nvidia/*.rpm
else
  # Copy packages and GPG keys from S3 if S3_URL_NVIDIA_RPMS is provided
  echo "Copying packages and GPG keys from S3..."
  aws s3 cp "$S3_URL_NVIDIA_RPMS" /tmp/nvidia --recursive
  
  # Import GPG keys from the downloaded directory
  if [ -d "/tmp/nvidia/gpgkeys" ]; then
    for key in /tmp/nvidia/gpgkeys/*; do
      if [ -f "$key" ]; then
        sudo rpm --import "$key"
      fi
    done
  fi

  echo "Installing packages..."
  # Issue when using FIPS to install nvidiacontainer.
  #https://github.com/NVIDIA/nvidia-container-toolkit/issues/116
  sudo dnf install -y /tmp/nvidia/*.rpm --allowerasing --best
fi

# Configure nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd

echo "NVIDIA driver installation completed."

# Clean up /tmp/nvidia unless RETAIN_NVIDIA_RPM is true
if [ "$RETAIN_NVIDIA_RPM" == "true" ]; then
  echo "Keeping NVIDIA RPMs and GPG keys in /tmp/nvidia for potential future use."
else
  echo "Cleaning up NVIDIA RPMs and GPG keys from /tmp/nvidia..."
  sudo rm -rf /tmp/nvidia
fi
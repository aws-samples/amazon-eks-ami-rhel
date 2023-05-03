# Amazon EKS AMI RHEL Build Specification

This repository contains resources and configuration scripts for building a
custom Amazon EKS AMI running on Red Hat Enterprise Linux. This is a forked version of the configuration that Amazon EKS uses to create the official Amazon
EKS-optimized AMI.

**Check out the AMI's [user guide](doc/USER_GUIDE.md) for more information.**

## 🚀 Getting started

If you are new to Amazon EKS, we recommend that you follow
our [Getting Started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
chapter in the Amazon EKS User Guide. If you already have a cluster, and you
want to launch a node group with your new AMI, see [Launching Amazon EKS Worker
Nodes](https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html).

## 🔢 Pre-requisites

* RHEL image of your choosing.
* Internet connectivity from EC2 for file downloads OR files stored locally in S3 bucket.

## 👷 Building the AMI

1. Launch an EC2 instance from the base AMI you would like to build from. In your EC2 instance User Data script, pull down the github repository and copy files to a temp directory for execution. See User Data bash script below, which is for an instance launched in the AWS GovCloud us-gov-east-1 region.
```bash
#!/bin/bash

yum install -y https://amazon-ssm-us-gov-east-1.s3.us-gov-east-1.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

yum install -y git
cd /home/ec2-user
git clone https://github.com/aws-samples/amazon-eks-ami-rhel
mkdir -p /tmp/worker
cp -r /home/ec2-user/amazon-eks-rhel-ami/scripts /tmp/
cp -r /home/ec2-user/amazon-eks-rhel-ami/files/* /tmp/worker/
cp -r /home/ec2-user/amazon-eks-rhel-ami/log-collector-script /tmp/worker/
```

2. Terminal into your new instance and kickoff the /tmp/scripts/install-worker.sh bash script that should have been copied over as part of your User Data script in step 1. Example launch command:
```bash
KUBERNETES_VERSION=1.24.7 BINARY_BUCKET_NAME=amazon-eks BINARY_BUCKET_REGION=us-west-2 KUBERNETES_BUILD_DATE=2022-10-31 DOCKER_VERSION=ce-3:23.0.1-1.el8.x86_64 CONTAINERD_VERSION=1.6.16-3.1.el7 RUNC_VERSION=1:1.1.4-1.module+el8.7.0+17498+a7f63b89 INSTALL_DOCKER=true CNI_PLUGIN_VERSION=v0.8.6 PULL_CNI_FROM_GITHUB=true PAUSE_CONTAINER_VERSION=3.5 CACHE_CONTAINER_IMAGES=false USE_AWS_CLI=false SONOBUOY_E2E_REGISTRY= INSTALL_AWS_CLI=false bash /tmp/scripts/install-worker.sh
```
Note: If the AWS CLI and SSM Agent are not already installed, pass in the INSTALL_AWS_CLI and INSTALL_SSM_AGENT variables set to true.

**Note**
The default instance type to build this AMI does not qualify for the AWS free tier. You are charged for any instances created when building this AMI.

**Note**
This has been tested on RHEL 8.6 and RHEL 8.7 images with 80+ DISA STIG SCAP scores.

## 🔒 Security

For security issues or concerns, please do not open an issue or pull request on GitHub. Please report any suspected or confirmed security issues to AWS Security https://aws.amazon.com/security/vulnerability-reporting/

## ⚖️ License Summary

This library is licensed under the MIT-0 License. See the LICENSE file.


# Amazon EKS AMI RHEL Build Specification

This repository contains resources and configuration scripts for building a
custom Amazon EKS AMI running on Red Hat Enterprise Linux with [HashiCorp Packer](https://www.packer.io/). This is
a forked version of the configuration that Amazon EKS uses to create the official Amazon EKS-optimized AMI.

**Check out the [📖 documentation](https://aws-samples.github.io/amazon-eks-ami-rhel/) to learn more.**

---

## 🔔 Announcements

### November 23, 2024 - Pause container image caching requires IAM credentials

Pause container image caching was [readded to the upstream build process](https://github.com/awslabs/amazon-eks-ami/pull/2000). This requires a few configurations for the build to complete successfully:
* Proper configuration of the new ```pause_container_image``` parameter. You can find the AWS managed regional repository using the [documented list](https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html).
* IAM credentials with permissions to read from AWS managed ECR repositories.
  * These credentials can either be passed in via API keys or (recommended) you can attach an IAM Instance Profile during the build process by passing in the ```iam_instance_profile``` parameter.
  
Example commands with the ```pause_container_image``` and ```iam_instance_profile``` parameters configured can be found below.
 
### March 6, 2024 - This code base now follows the Amazon Linux 2023 custom EKS AMI code base

This code base has always followed the [awslabs amazon-eks-ami](https://github.com/awslabs/amazon-eks-ami) code base as closely as possible.
* Significant changes were made to that upstream code base to provide EKS support for Amazon Linux 2023.
* Because Amazon Linux 2 is now under extended support, this code base will now follow the Amazon Linux 2023 code base of the upstream repository.
* The [scripts for creating worker node groups](https://aws-samples.github.io/amazon-eks-ami-rhel/nodegroups/) have been modified to account for how worker nodes join EKS clusters under the new process.
* The previous code base, which was based on Amazon Linux 2 build scripts, will remain available under the [al2-base branch](https://github.com/aws-samples/amazon-eks-ami-rhel/tree/al2-base).

## 🚀 Getting started

If you are new to Amazon EKS, we recommend that you follow
our [Getting Started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
chapter in the Amazon EKS User Guide. If you already have a cluster, and you
want to launch a node group with your new AMI, see [Launching Amazon EKS Worker
Nodes](https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html).

## 🔢 Pre-requisites

* RHEL image of your choosing.
* Internet connectivity from EC2 for file downloads OR files stored locally in S3 bucket.
* You must have [Packer](https://www.packer.io/) version 1.8.0 or later installed on your local system, an EC2 Instance in AWS, or in [AWS CloudShell](https://aws.amazon.com/cloudshell/). For more information, see [Installing Packer](https://www.packer.io/docs/install/index.html) in the Packer documentation.
* You must also have AWS account credentials configured so that Packer can make calls to AWS API operations on your behalf. For more information, see [Authentication](https://www.packer.io/docs/builders/amazon.html#specifying-amazon-credentials) in the Packer documentation.
* We recommend using AWS CloudShell for simplicity.

## 🪪 Minimal Packer IAM Permissions
```bash
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CopyImage",
        "ec2:CreateImage",
        "ec2:CreateKeypair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:GetPasswordData",
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

## ⚙️ Installing Packer in CloudShell
```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install packer
packer plugins install github.com/hashicorp/amazon

```

## 🗂️ Cloning the Github repository
```bash
git clone https://github.com/aws-samples/amazon-eks-ami-rhel.git && cd amazon-eks-ami-rhel

```

## 👷 Building the AMI

A Makefile is provided to build the Amazon EKS Worker AMI, but it is just a small wrapper around
invoking Packer directly. You can initiate the build process by running the
following command in the root of this repository:

```bash
# Example for building an AMI with the latest Kubernetes version and the latest RHEL 8.9 AMI. This would use all variables stored in the variables-default.json file.
make

# Example for building an AMI with the latest Kubernetes version and the latest RHEL 8.9 AMI in us-gov-east-1
make k8s=1.30 ami_regions=us-gov-east-1 aws_region=us-gov-east-1 iam_instance_profile=EC2Role pause_container_image=151742754352.dkr.ecr.us-gov-east-1.amazonaws.com/eks/pause:3.5

# Example for building an AMI off of the latest RHEL 9.0.0 AMI in us-east-2 region
make k8s=1.30 source_ami_filter_name=RHEL-9.0.0_HVM-2023*-x86_64-* ami_regions=us-east-2 aws_region=us-east-2 iam_instance_profile=EC2Role pause_container_image=602401143452.dkr.ecr.us-east-2.amazonaws.com/eks/pause:3.5

# Example for building a customized DISA STIG compliant AMI, owned by a specific AWS Account in AWS GovCloud us-gov-east-1 region, with binaries stored in a private S3 bucket, an IAM instance profile attached, a user data script to install the AWS Systems Manager agent, and using AWS Systems Manager Session Manager for Packer terminal access.
make k8s=1.30 source_ami_owners=123456789123 source_ami_filter_name=RHEL9_STIG_BASE*2023-04-14* ami_regions=us-gov-east-1 aws_region=us-gov-east-1 binary_bucket_name=my-eks-bucket binary_bucket_region=us-gov-east-1 iam_instance_profile=EC2Role pause_container_image=151742754352.dkr.ecr.us-gov-east-1.amazonaws.com/eks/pause:3.5 pull_cni_from_github=false ssh_interface=session_manager user_data_file=/path/to/ssm_install.txt

# Check default value and options in help doc
make help
```

The Makefile chooses a particular kubelet binary to use per Kubernetes version which you can [view here](Makefile).

> **Note**
> There is a network routing issue caused by the nm-cloud-setup service that comes preinstalled on RHEL machines. In the AWS [Blog](https://aws.amazon.com/blogs/containers/run-amazon-eks-on-rhel-worker-nodes-with-ipvs-networking), we demonstrate how to disable this service and reboot the EC2 instances as recommended by Red Hat in the following KB [article](https://access.redhat.com/solutions/6319811).

> **Note**
> The default instance type to build this AMI does not qualify for the AWS free tier.
> You are charged for any instances created when building this AMI.

> **Note**
> This has been tested on RHEL 8.6+ and RHEL 9+ images with 80+ DISA STIG SCAP scores.

## 🔒 Security

For security issues or concerns, please do not open an issue or pull request on GitHub. Please report any suspected or confirmed security issues to AWS Security https://aws.amazon.com/security/vulnerability-reporting/

## ⚖️ License Summary

This library is licensed under the MIT-0 License. See the LICENSE file.

## 📝 Legal Disclaimer

The sample code; software libraries; command line tools; proofs of concept; templates; or other related technology (including any of the foregoing that are provided by our personnel) is provided to you as AWS Content under the AWS Customer Agreement, or the relevant written agreement between you and AWS (whichever applies). You should not use this AWS Content in your production accounts, or on production or other critical data. You are responsible for testing, securing, and optimizing the AWS Content, such as sample code, as appropriate for production grade use based on your specific quality control practices and standards. Deploying AWS Content may incur AWS charges for creating or using AWS chargeable resources, such as running Amazon EC2 instances or using Amazon S3 storage.

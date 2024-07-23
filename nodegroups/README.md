# Worker node group creation scripts

This directory contains sample scripts for creating EKS worker node groups after worker node AMI creation. These scripts were written to help you get started, not for production implementation!

## 🔔 Announcements

### Worker nodes are now joined to EKS clusters using [nodeadm](../nodeadm/README.md)

The new method of joining EKS clusters using [nodeadm](../nodeadm/README.md) is significantly different than the deprecated bootstrap.sh script method. For this reason, some sample scripts have been provided here to get you started.

> **Note**
> These changes require functionality that is not curently available using [eksctl](https://eksctl.io/), so for now any scripts that reference eksctl are not working. A bug report has been submitted to address this issue.

## 👷 Usage

Example command to launch a new worker node group with a custom configuration:
```bash
./create_nodegroup_cfn_zsh.sh rhel-eks ami-0b2e96e12344a54c0 rhel-eks-node-group us-gov-east-1 govcloud2024 t3.medium 3 3 3 https://5B3FFDCDC05F2D983E65079309123456.gr7.us-gov-east-1.eks.amazonaws.com 10.100.0.0/16 LS0tLS1CRUdLS0tLS0K "subnet-0f034415c5b771234 subnet-0bdba07340be11234 subnet-05c651fa62a571234" sg-038c07b2206e12345
```
This would create a node group with the following configuration:
```yaml
Cluster: rhel-eks
AMI ID: ami-0b2e96e12344a54c0
Node group name: rhel-eks-node-group
AWS Region: us-gov-east-1
Keypair name: govcloud2024
Instance type: t3.medium
Min node group size: 3
Desired node group size: 3
Max node group size: 3
EKS API endpoint: https://5B3FFDCDC05F2D983E65079309123456.gr7.us-gov-east-1.eks.amazonaws.com
CIDR range: 10.100.0.0/16
Certificate: LS0tLS1CRUdLS0tLS0K
Subnet IDs: subnet-0f034415c5b771234 subnet-0bdba07340be11234 subnet-05c651fa62a571234
Security group ID: sg-038c07b2206e12345
```

This command would generate a local CloudFormation template and execute the CloudFormation stack via the AWS CLI.

## 🔒 Security

For security issues or concerns, please do not open an issue or pull request on GitHub. Please report any suspected or confirmed security issues to AWS Security https://aws.amazon.com/security/vulnerability-reporting/

## ⚖️ License Summary

This library is licensed under the MIT-0 License. See the LICENSE file.

## 📝 Legal Disclaimer

The sample code; software libraries; command line tools; proofs of concept; templates; or other related technology (including any of the foregoing that are provided by our personnel) is provided to you as AWS Content under the AWS Customer Agreement, or the relevant written agreement between you and AWS (whichever applies). You should not use this AWS Content in your production accounts, or on production or other critical data. You are responsible for testing, securing, and optimizing the AWS Content, such as sample code, as appropriate for production grade use based on your specific quality control practices and standards. Deploying AWS Content may incur AWS charges for creating or using AWS chargeable resources, such as running Amazon EC2 instances or using Amazon S3 storage.
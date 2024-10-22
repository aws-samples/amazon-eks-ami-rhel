# Red Hat Enterprise Linux

## Template variables

<!-- template-variable-table-boundary -->
| Variable | Description |
| - | - |
| `ami_component_description` |  |
| `ami_description` |  |
| `ami_name` |  |
| `ami_regions` |  |
| `ami_users` |  |
| `arch` |  |
| `associate_public_ip_address` |  |
| `aws_access_key_id` |  |
| `aws_region` |  |
| `aws_secret_access_key` |  |
| `aws_session_token` |  |
| `binary_bucket_name` |  |
| `binary_bucket_region` |  |
| `container_selinux_version` |  |
| `containerd_url` | URL for downloading containerd binaries. Specify S3 URI (s3://my_bucket/containerd.tgz) to download from an S3 bucket using the AWS CLI. |
| `containerd_version` |  |
| `creator` |  |
| `enable_efa` | Valid options are ```true``` or ```false```. Wheather or not to install the software needed to use AWS Elastic Fabric Adapter (EFA) network interfaces. |
| `enable_fips` | Install openssl and enable fips related kernel parameters |
| `encrypted` |  |
| `iam_instance_profile` | The name of an IAM instance profile to launch the EC2 instance with. |
| `instance_type` |  |
| `kms_key_id` |  |
| `kubernetes_build_date` |  |
| `kubernetes_version` |  |
| `launch_block_device_mappings_volume_size` |  |
| `nerdctl_url` | URL for downloading nerdctl binaries. Specify S3 URI (s3://my_bucket/nerdctl.tgz) to download from an S3 bucket using the AWS CLI. |
| `nerdctl_version` |  |
| `nodeadm_build_image` | Image to use as a build environment for nodeadm |
| `remote_folder` | Directory path for shell provisioner scripts on the builder instance |
| `runc_version` |  |
| `security_group_id` |  |
| `source_ami_filter_name` |  |
| `source_ami_id` |  |
| `source_ami_owners` |  |
| `ssh_interface` | If using ```session_manager```, you need to ensure your AMI has the SSM agent installed as the default RHEL AMIs do not have the SSM agent installed. This can be achieved through a user_data_file script. |
| `ssh_username` |  |
| `ssm_agent_version` | Version of the SSM agent to install from the S3 bucket provided by the SSM agent project, such as ```latest```. If empty, the latest version of the SSM agent available will be installed. |
| `subnet_id` |  |
| `temporary_key_pair_type` |  |
| `temporary_security_group_source_cidrs` |  |
| `user_data_file` | Path to a file that will be used for the user data when launching the instance. |
| `volume_type` |  |
| `vpc_id` |  |
| `working_dir` | Directory path for ephemeral resources on the builder instance |
<!-- template-variable-table-boundary -->
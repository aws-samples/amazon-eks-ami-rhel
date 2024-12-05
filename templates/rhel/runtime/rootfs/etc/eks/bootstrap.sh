#!/usr/bin/env bash

echo >&2 '
!!!!!!!!!!
!!!!!!!!!! ERROR: bootstrap.sh has been removed from RHEL-based EKS AMIs.
!!!!!!!!!!
!!!!!!!!!! EKS nodes are now initialized by nodeadm.
!!!!!!!!!!
!!!!!!!!!! To migrate your user data, see:
!!!!!!!!!!
!!!!!!!!!!     https://aws-samples.github.io/amazon-eks-ami-rhel/nodeadm/
!!!!!!!!!!
'

exit 1

#!/bin/zsh

EKS_CLUSTER=$1
AMI_ID=$2
MANAGED_NODE_GROUP=$3
AWS_REGION=$4
KEY_PAIR=$5
INSTANCE_TYPE=$6
MIN_SIZE=$7
DESIRED_SIZE=$8
MAX_SIZE=$9
USER_DATA=$(printf "#!/bin/bash\n\n/etc/eks/bootstrap.sh $EKS_CLUSTER --container-runtime containerd\nsystemctl disable nm-cloud-setup.timer\nsystemctl disable nm-cloud-setup.service\nreboot" | base64)
DATE_TIME=$(date +'%Y%m%d%H%M')

cat > managednodegroup-$DATE_TIME.yaml << EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $EKS_CLUSTER
  region: $AWS_REGION

managedNodeGroups:
  - name: $MANAGED_NODE_GROUP
    minSize: $MIN_SIZE
    desiredCapacity: $DESIRED_SIZE
    maxSize: $MAX_SIZE
    ami: $AMI_ID
    amiFamily: AmazonLinux2
    instanceType: $INSTANCE_TYPE
    labels:
      role: worker
    tags:
      nodegroup-name: $MANAGED_NODE_GROUP
    privateNetworking: true

    overrideBootstrapCommand: |
      #!/bin/bash
      /etc/eks/bootstrap.sh $EKS_CLUSTER --container-runtime containerd
      systemctl disable nm-cloud-setup.timer
      systemctl disable nm-cloud-setup.service
      reboot
EOF

eksctl create nodegroup --config-file=managednodegroup-$DATE_TIME.yaml --cfn-disable-rollback
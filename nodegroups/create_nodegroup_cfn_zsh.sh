#!/bin/zsh

# Short and long options
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--cluster-name)
      EKS_CLUSTER=$2
      shift 2
      ;;
    -a|--ami-id)
      AMI_ID=$2
      shift 2
      ;;
    -m|--managed-node-group)
      MANAGED_NODE_GROUP=$2
      shift 2
      ;;
    -r|--region)
      AWS_REGION=$2
      shift 2
      ;;
    -i|--instance-type)
      INSTANCE_TYPE=$2
      shift 2
      ;;
    -n|--min-size)
      MIN_SIZE=$2
      shift 2
      ;;
    -d|--desired-size)
      DESIRED_SIZE=$2
      shift 2
      ;;
    -x|--max-size)
      MAX_SIZE=$2
      shift 2
      ;;
    -s|--subnets)
      SUBNET_OPTION=$2
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check if required parameters are provided
if [ -z "$EKS_CLUSTER" ] || [ -z "$AMI_ID" ] || [ -z "$MANAGED_NODE_GROUP" ] || [ -z "$AWS_REGION" ] || [ -z "$INSTANCE_TYPE" ] || [ -z "$MIN_SIZE" ] || [ -z "$DESIRED_SIZE" ] || [ -z "$MAX_SIZE" ] || [ -z "$SUBNET_OPTION" ]; then
  echo "Usage: $0 --cluster-name <name> --ami-id <id> [--managed-node-group <name>] [--region <aws-region>] [--instance-type <type>] [--min-size <number>] [--desired-size <number>] [--max-size <number>] [--subnets <public|private|all>]"
  exit 1
fi

SUBNETS=$(echo "$SUBNET_OPTION" | tr '[:upper:]' '[:lower:]')
API_ENDPOINT=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.endpoint)
CIDR=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.kubernetesNetworkConfig.serviceIpv4Cidr)
CERTIFICATE=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.certificateAuthority.data)
SECURITY_GROUP_ID=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.resourcesVpcConfig.clusterSecurityGroupId)
DATE_TIME=$(date +'%Y%m%d%H%M')

# List of subnet IDs
subnets=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.resourcesVpcConfig.subnetIds)

public_subnets=""
private_subnets=""

# Loop through subnets and determine if they are public or private
for subnet in ${=subnets}; do
  cleaned_subnet=$(echo $subnet | tr -d '[]",')

  if [ -n "$cleaned_subnet" ]; then
    is_public=$(aws ec2 describe-subnets --subnet-ids $cleaned_subnet --query "Subnets[0].MapPublicIpOnLaunch" --output text)
    
    if [ "$is_public" = "True" ]; then
      public_subnets+="${cleaned_subnet} "
    else
      private_subnets+="${cleaned_subnet} "
    fi
  fi
done

public_subnets=$(echo "$public_subnets" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
private_subnets=$(echo "$private_subnets" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Build subnet list for CloudFormation template based on user's specified type of subnet or explicit string of subnets
if [ "$SUBNETS" = "public" ]; then
  SUBNETS=$(echo "$public_subnets" | tr ' ' '\n' | while read public_subnet; do echo "        - ${public_subnet}"; done)
elif [ "$SUBNETS" = "private" ]; then
  SUBNETS=$(echo "$private_subnets" | tr ' ' '\n' | while read private_subnet; do echo "        - ${private_subnet}"; done)
elif [ "$SUBNETS" = "all" ]; then
  SUBNETS=$(echo -e "${public_subnets}\n${private_subnets}" | tr ' ' '\n' | while read subnet; do echo "        - ${subnet}"; done)
else
  SUBNETS=$(echo "$9" | tr ' ' '\n' | while read subnet; do echo "        - ${subnet}"; done)
fi

# Create CloudFormation template
cat > cf-template-$DATE_TIME.yaml << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'EKS Managed Nodes (SSH access: false)'
Mappings:
  ServicePrincipalPartitionMap:
    aws:
      EC2: ec2.amazonaws.com
      EKS: eks.amazonaws.com
      EKSFargatePods: eks-fargate-pods.amazonaws.com
    aws-cn:
      EC2: ec2.amazonaws.com.cn
      EKS: eks.amazonaws.com
      EKSFargatePods: eks-fargate-pods.amazonaws.com
    aws-iso:
      EC2: ec2.c2s.ic.gov
      EKS: eks.amazonaws.com
      EKSFargatePods: eks-fargate-pods.amazonaws.com
    aws-iso-b:
      EC2: ec2.sc2s.sgov.gov
      EKS: eks.amazonaws.com
      EKSFargatePods: eks-fargate-pods.amazonaws.com
    aws-us-gov:
      EC2: ec2.amazonaws.com
      EKS: eks.amazonaws.com
      EKSFargatePods: eks-fargate-pods.amazonaws.com
Resources:
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateData:
        BlockDeviceMappings:
          - DeviceName: /dev/sda1
            Ebs:
              Encrypted: false
              Iops: 3000
              Throughput: 125
              VolumeSize: 80
              VolumeType: gp3
        ImageId: $AMI_ID
        MetadataOptions:
          HttpPutResponseHopLimit: 2
          HttpTokens: required
        SecurityGroupIds:
          - $SECURITY_GROUP_ID
        TagSpecifications:
          - ResourceType: instance
            Tags:
              - Key: Name
                Value: ${EKS_CLUSTER}-${MANAGED_NODE_GROUP}-Node
              - Key: alpha.eksctl.io/nodegroup-type
                Value: managed
              - Key: nodegroup-name
                Value: $MANAGED_NODE_GROUP
              - Key: alpha.eksctl.io/nodegroup-name
                Value: $MANAGED_NODE_GROUP
          - ResourceType: volume
            Tags:
              - Key: Name
                Value: ${EKS_CLUSTER}-${MANAGED_NODE_GROUP}-Node
              - Key: alpha.eksctl.io/nodegroup-type
                Value: managed
              - Key: nodegroup-name
                Value: $MANAGED_NODE_GROUP
              - Key: alpha.eksctl.io/nodegroup-name
                Value: $MANAGED_NODE_GROUP
          - ResourceType: network-interface
            Tags:
              - Key: Name
                Value: ${EKS_CLUSTER}-${MANAGED_NODE_GROUP}-Node
              - Key: alpha.eksctl.io/nodegroup-type
                Value: managed
              - Key: nodegroup-name
                Value: $MANAGED_NODE_GROUP
              - Key: alpha.eksctl.io/nodegroup-name
                Value: $MANAGED_NODE_GROUP
        UserData:
          Fn::Base64: !Sub |
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="BOUNDARY"

            --BOUNDARY
            Content-Type: application/node.eks.aws

            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              cluster:
                name: $EKS_CLUSTER
                apiServerEndpoint: $API_ENDPOINT
                certificateAuthority: $CERTIFICATE
                cidr: $CIDR

            --BOUNDARY
            Content-Type: text/x-shellscript;

            #!/bin/bash
            set -ex
            systemctl enable kubelet.service
            systemctl disable nm-cloud-setup.timer
            systemctl disable nm-cloud-setup.service
            reboot

            --BOUNDARY--
      LaunchTemplateName: !Sub '\${AWS::StackName}'
  ManagedNodeGroup:
    Type: AWS::EKS::Nodegroup
    Properties:
      ClusterName: $EKS_CLUSTER
      InstanceTypes:
        - $INSTANCE_TYPE
      Labels:
        alpha.eksctl.io/cluster-name: $EKS_CLUSTER
        alpha.eksctl.io/nodegroup-name: $MANAGED_NODE_GROUP
        role: worker
      LaunchTemplate:
        Id: !Ref 'LaunchTemplate'
      NodeRole: !GetAtt 'NodeInstanceRole.Arn'
      NodegroupName: $MANAGED_NODE_GROUP
      ScalingConfig:
        MinSize: $MIN_SIZE
        DesiredSize: $DESIRED_SIZE
        MaxSize: $MIN_SIZE
      Subnets:
$SUBNETS
      Tags:
        alpha.eksctl.io/nodegroup-name: $MANAGED_NODE_GROUP
        alpha.eksctl.io/nodegroup-type: managed
        nodegroup-name: $MANAGED_NODE_GROUP
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Action:
              - sts:AssumeRole
            Effect: Allow
            Principal:
              Service:
                - !FindInMap
                  - ServicePrincipalPartitionMap
                  - !Ref 'AWS::Partition'
                  - EC2
        Version: '2012-10-17'
      ManagedPolicyArns:
        - !Sub 'arn:\${AWS::Partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly'
        - !Sub 'arn:\${AWS::Partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy'
        - !Sub 'arn:\${AWS::Partition}:iam::aws:policy/AmazonEKS_CNI_Policy'
        - !Sub 'arn:\${AWS::Partition}:iam::aws:policy/AmazonSSMManagedInstanceCore'
      Path: /
      Tags:
        - Key: Name
          Value: !Sub '\${AWS::StackName}/NodeInstanceRole'
EOF

aws cloudformation create-stack \
  --stack-name ${EKS_CLUSTER}-${MANAGED_NODE_GROUP}-${DATE_TIME} \
  --template-body file://cf-template-${DATE_TIME}.yaml \
  --capabilities CAPABILITY_IAM \
  --region ${AWS_REGION}
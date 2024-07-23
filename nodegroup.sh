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
API_ENDPOINT=$10
CIDR=$11
CERTIFICATE=$12
SUBNETS=$(echo "${13}" | tr ' ' '\n' | while read subnet; do echo "        - $subnet"; done)
SECURITY_GROUP_ID=$14
DATE_TIME=$(date +'%Y%m%d%H%M')

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
                Value: $EKS_CLUSTER-$MANAGED_NODE_GROUP-Node
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
                Value: $EKS_CLUSTER-$MANAGED_NODE_GROUP-Node
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
  --stack-name ${EKS_CLUSTER}-node-launch-template-${DATE_TIME} \
  --template-body file://cf-template-$DATE_TIME.yaml \
  --capabilities CAPABILITY_IAM \
  --region ${AWS_REGION}
#!/bin/zsh

EKS_CLUSTER=$1
SUBNETS=$2

# List of subnet IDs
subnets=$(aws eks describe-cluster --name $EKS_CLUSTER --query cluster.resourcesVpcConfig.subnetIds)

public_subnets=""
private_subnets=""

# Loop through subnets and determine if they are public or private
for subnet in ${=subnets}; do
  cleaned_subnet=$(echo $subnet | tr -d '[]",')

  if [ -n "$cleaned_subnet" ]; then
    is_public=$(aws ec2 describe-subnets --subnet-ids $cleaned_subnet --query "Subnets[0].MapPublicIpOnLaunch" --output text)
    
    if [ "${is_public}" = "True" ]; then
      public_subnets+="        - ${cleaned_subnet}\n"
    else
      private_subnets+="        - ${cleaned_subnet}\n"
    fi
  fi
done

echo -e "Public subnets:\n$public_subnets"
echo -e "Private subnets:\n$private_subnets"
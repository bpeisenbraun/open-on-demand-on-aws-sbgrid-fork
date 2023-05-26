#!/bin/bash

# this script creates a sample parallelcluster config file to work with your OOD environment.
# It needs to read outputs from your OOD stack you already deployed. So you need to have the AWS_PROFILE or access key environment variables set
# The cluster will have two partitions defined, one for general workload, one for interactive desktop.
# Please update your
STACK_NAME="odd-demo-2"
SSH_KEY='sbgrid-ood-demo'

REGION="us-east-1"
DOMAIN_1="sbgrid"
DOMAIN_2="local"

OOD_STACK=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" )

AD_SECRET_ARN=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ADAdministratorSecretARN") | .OutputValue')
SUBNET=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="PrivateSubnet1") | .OutputValue')
HEAD_SG=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeSecurityGroup") | .OutputValue')
HEAD_POLICY=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeIAMPolicyArn") | .OutputValue')
COMPUTE_SG=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeSecurityGroup") | .OutputValue')
COMPUTE_POLICY=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeIAMPolicyArn") | .OutputValue')
BUCKET_NAME=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
LDAP_ENDPOINT=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="LDAPNLBEndPoint") | .OutputValue')
EFS_PROGRAMS_FS_ID=$(aws efs describe-file-systems | jq -r '.FileSystems[] | select(.Tags[] | select(.Value == "SBGridProgramsInstallation")) | .FileSystemId')
FSX_CLUSTER_FS_ID=$(aws fsx describe-file-systems | jq -r '.FileSystems[] | select(.Tags[] | select(.Value == "SBGridPosixFS")) | .FileSystemId')

cat << EOF > "../pcluster-config-devcluster-$(date '+%Y%m%d-%H%M%S').yml"
---
HeadNode:
  InstanceType: c5.large
  Ssh:
    KeyName: $SSH_KEY
  Networking:
    SubnetId: $SUBNET
    AdditionalSecurityGroups:
      - $HEAD_SG
  LocalStorage:
    RootVolume:
      VolumeType: gp3
      Size: 50
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      - Policy: arn:aws:iam::aws:policy/AmazonS3FullAccess
      - Policy: $HEAD_POLICY
  CustomActions:
    OnNodeConfigured:
      Script: >-
        s3://$BUCKET_NAME/pcluster_head_node-devcluster.sh
      Args:
        - $STACK_NAME
Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: general
      AllocationStrategy: lowest-price
      ComputeResources:
        - Name: general-cr
          Instances:
            - InstanceType: c5n.large
          MinCount: 0
          MaxCount: 4
      Networking:
        SubnetIds:
          - $SUBNET
        AdditionalSecurityGroups:
          - $COMPUTE_SG
      ComputeSettings:
        LocalStorage:
          RootVolume:
            VolumeType: gp3
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/pcluster_worker_node.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: $COMPUTE_POLICY
          - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
          - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    - Name: desktop
      AllocationStrategy: lowest-price
      ComputeResources:
        - Name: desktop-cr
          Instances:
            - InstanceType: g4dn.xlarge
          MinCount: 0
          MaxCount: 10
      Networking:
        SubnetIds:
          - $SUBNET
        AdditionalSecurityGroups:
          - $COMPUTE_SG
      ComputeSettings:
        LocalStorage:
          RootVolume:
            VolumeType: gp3
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/pcluster_worker_node_desktop.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: $COMPUTE_POLICY
          - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
          - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    - Name: cryosparc-master
      AllocationStrategy: lowest-price
      ComputeResources:
        - Name: cryosparc-master-cr
          Instances:
            - InstanceType: r5d.xlarge
          MinCount: 0
          MaxCount: 1
      Networking:
        SubnetIds:
          - $SUBNET
        AdditionalSecurityGroups:
          - $COMPUTE_SG
      ComputeSettings:
        LocalStorage:
          RootVolume:
            VolumeType: gp3
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/pcluster_cryosparc_master.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: $COMPUTE_POLICY
          - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
          - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
          # NOTE/TODO: this policy gives access to all ECR repositories in the
          # account. This should be replaced by a policy that gives access to
          # only the cryosparc repository (and cross-account access to the
          # repository in the other account if we use a centralized ECR
          # repository)
          - Policy: arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  SlurmSettings:
    QueueUpdateStrategy: DRAIN
Region: $REGION
Image:
  Os: alinux2
DirectoryService:
  DomainName: $DOMAIN_1.$DOMAIN_2
  DomainAddr: $LDAP_ENDPOINT
  PasswordSecretArn: $AD_SECRET_ARN
  DomainReadOnlyUser: cn=Admin,ou=Users,ou=$DOMAIN_1,dc=$DOMAIN_1,dc=$DOMAIN_2
  AdditionalSssdConfigs:
    override_homedir: /shared/home/%u
SharedStorage:
  - MountDir: /shared
    Name: SBGridPosixFS
    StorageType: FsxLustre
    FsxLustreSettings:
      FileSystemId: $FSX_CLUSTER_FS_ID
  - MountDir: /programs
    Name: SBGridProgramsInstallation
    StorageType: Efs
    EfsSettings:
      FileSystemId: $EFS_PROGRAMS_FS_ID
EOF

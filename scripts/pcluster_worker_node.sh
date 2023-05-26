#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

yum -y -q install jq mysql amazon-efs-utils
# Get OOD Stack data
OOD_STACK_NAME=$1
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)

OOD_STACK=$(aws cloudformation describe-stacks --stack-name "$OOD_STACK_NAME" --region "$REGION" )

S3_CONFIG_BUCKET=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')

# Copy Common Munge Key
aws s3 cp "s3://$S3_CONFIG_BUCKET/munge.key" /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# Add spack-users group
groupadd spack-users -g 4000

#fix the sssd script so getent passws command can find the domain user
#This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
#This line configure sssd to create the home directories in the shared folder
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd

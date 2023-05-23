#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

yum -y install jq mysql amazon-efs-utils eom

# Get OOD Stack data
OOD_STACK_NAME=$1
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)

OOD_STACK=$(aws cloudformation describe-stacks --stack-name "$OOD_STACK_NAME" --region "$REGION")

S3_CONFIG_BUCKET=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')

# Copy Common Munge Key
aws s3 cp s3://"$S3_CONFIG_BUCKET"/munge.key /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# Add spack-users group
groupadd spack-users -g 4000

# Fix the sssd script so getent passws command can find the domain user
# This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
# This line configure sssd to create the home directories in the shared folder
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd

# Add desktop environment and noVNC tools
amazon-linux-extras install firefox python3.8 mate-desktop1.x
ln -sf /usr/bin/python3.8 /usr/bin/python3
pip3 install --no-input websockify
ln -sf /usr/local/bin/websockify /usr/bin/websockify
pip3 install --no-input jupyter

# Install TurboVNC and VirtualGL for GL accelerated desktops
curl -o /etc/yum.repos.d/VirtualGL.repo https://virtualgl.org/pmwiki/uploads/Downloads/VirtualGL.repo
curl -o /etc/yum.repos.d/TurboVNC.repo https://turbovnc.org/pmwiki/uploads/Downloads/TurboVNC.repo
yum install -y VirtualGL turbojpeg turbovnc nmap-ncat

# Update system path
cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/opt/TurboVNC/bin:/opt/VirtualGL/bin
#this is to fix the dconf permission error
export XDG_RUNTIME_DIR="$HOME/.cache/dconf"
EOF



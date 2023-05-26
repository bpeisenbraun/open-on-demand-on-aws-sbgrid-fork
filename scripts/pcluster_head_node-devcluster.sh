#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Install packages for domain
yum -y -q install jq mysql amazon-efs-utils adcli
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

OOD_STACK_NAME="$1"

OOD_STACK=$(aws cloudformation describe-stacks --stack-name "$OOD_STACK_NAME" --region "$REGION" )

# shellcheck disable=SC2016
STACK_NAME=$(aws ec2 describe-instances --instance-id="$INSTANCE_ID" --region "$REGION" --query 'Reservations[].Instances[].Tags[?Key==`parallelcluster:cluster-name`].Value' --output text)
RDS_SECRET_ID=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="DBSecretId") | .OutputValue')
S3_CONFIG_BUCKET=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')

CLUSTER_NAME="$STACK_NAME-devcluster"

RDS_SECRET=$(aws secretsmanager --region "$REGION" get-secret-value --secret-id "$RDS_SECRET_ID" --query SecretString --output text)
RDS_USER=$(echo "$RDS_SECRET" | jq -r ".username")
RDS_PASSWORD=$(echo "$RDS_SECRET" | jq -r ".password")
RDS_ENDPOINT=$(echo "$RDS_SECRET" | jq -r ".host")
RDS_PORT=$(echo "$RDS_SECRET" | jq -r ".port")
export RDS_USER RDS_PASSWORD RDS_ENDPOINT RDS_PORT

# Add spack-users group
groupadd spack-users -g 4000

## Remove slurm cluster name; will be repopulated when instance restarts
rm -f /var/spool/slurm.state/clustername
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
service sshd restart

#This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd

SLURM_VERSION=$(. /etc/profile && sinfo --version | cut -d' ' -f 2)
export SLURM_VERSION
sed -i "s/ClusterName=.*$/ClusterName=${CLUSTER_NAME}/" /opt/slurm/etc/slurm.conf

cat << EOF > /opt/slurm/etc/slurmdbd.conf
ArchiveEvents=yes
ArchiveJobs=yes
ArchiveResvs=yes
ArchiveSteps=no
ArchiveSuspend=no
ArchiveTXN=no
ArchiveUsage=no
AuthType=auth/munge
DbdHost=$(hostname -s)
DbdPort=6819
DebugLevel=info
PurgeEventAfter=1month
PurgeJobAfter=12month
PurgeResvAfter=1month
PurgeStepAfter=1month
PurgeSuspendAfter=1month
PurgeTXNAfter=12month
PurgeUsageAfter=24month
SlurmUser=slurm
LogFile=/var/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageUser=$RDS_USER
StoragePass=$RDS_PASSWORD
StorageHost=$RDS_ENDPOINT # Endpoint from RDS console
StoragePort=$RDS_PORT  # Port from RDS console
EOF

cat << EOF >> /opt/slurm/etc/slurm.conf
# ACCOUNTING
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=$(hostname -s)
AccountingStorageUser=$RDS_USER
AccountingStoragePort=6819
EOF

chmod 600 /opt/slurm/etc/slurmdbd.conf
chown slurm /opt/slurm/etc/slurmdbd.conf

# Copy Common Munge Key
aws s3 cp "s3://$S3_CONFIG_BUCKET/munge.key" /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# Add cluster to slurm accounting
sacctmgr add cluster "$CLUSTER_NAME"
systemctl restart slurmctld
systemctl enable slurmctld
systemctl restart slurmdbd
systemctl enable slurmdbd
systemctl restart slurmctld # TODO: Investigate why this fixes clusters not registered issues

# Build the OOD cluster config on the PCluster head node and then copy it
# to S3 for use by OOD
mkdir -p /tmp/ood-config/
cat << EOF > "/tmp/ood-config/$CLUSTER_NAME.yml"
---
v2:
  metadata:
    title: "$CLUSTER_NAME"
    hidden: false
  login:
    host: "$(hostname -s)"
  job:
    adapter: "slurm"
    cluster: "$CLUSTER_NAME"
    bin: "/bin"
    bin_overrides:
      sbatch: "/etc/ood/config/bin_overrides.py"
EOF
aws s3 cp "/tmp/ood-config/$CLUSTER_NAME.yml" "s3://$S3_CONFIG_BUCKET/clusters/$CLUSTER_NAME.yml"

### this is for lustre cache eviction -- not working yet
#echo "5 * * * * /programs/local/bin/cache-eviction-wrapper.sh -mountpath /fsx -mountpoint /shared -minage 30 -minsize 2000 -bucket bucket" | crontab 